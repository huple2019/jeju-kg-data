// ════════════════════════════════════════════════════════════════
//  06_TEST_SCENARIOS.cypher — 복합 판정 테스트 10종
//
//  목적: 안전·무장애 판정이 실제로 작동하는지 확인합니다.
//        각 시나리오는 "이렇게 답하면 안 되는 경우"를 함께 명시했습니다.
//
//  사용법: :param 을 먼저 실행한 뒤 본 쿼리를 실행합니다.
//         결과가 [기대]와 다르면 데이터 또는 판정 로직 문제입니다.
// ════════════════════════════════════════════════════════════════


// ════════════════════════════════════════════════════════════════
// [T1] 휠체어 + 여름 오후 + 바다 — 방문 목적에 따라 판정이 갈린다
//      질문A: "휠체어로 물놀이할 수 있는 바다 알려줘"   → $purpose='SWIM'
//      질문B: "휠체어로 바다 구경하기 좋은 곳 알려줘"     → $purpose='SIGHTSEE'
//
//      핵심: 어촌·어항법이 금지하는 것은 물놀이·다이빙·취사·야영뿐입니다.
//            산책·경관 감상은 제한 대상이 아니므로 포구도 추천 가능합니다.
//            목적을 구분하지 않으면 포구를 무조건 배제하거나(과잉),
//            물놀이 장소로 추천하는(위험) 오류가 납니다.
//
//      검증: ① SWIM 이면 어항구역이 결과에서 제외되는가
//            ② SIGHTSEE 이면 포구도 나오되 물놀이 금지가 함께 고지되는가
//            ③ 안전요원 배치 여부(해수욕장)가 안내되는가
//      오답: 목적과 무관하게 포구를 "물놀이 명소"로 추천 / 산책 목적인데 포구를 전부 배제
// ════════════════════════════════════════════════════════════════
:param purpose => 'SWIM';     // 'SWIM' 또는 'SIGHTSEE'
:param season  => '여름';

// ⚠ 아래는 :param 없이 실행해도 동작합니다(기본 SWIM/여름).
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WITH p, ac, coalesce($purpose,'SWIM') AS purpose, coalesce($season,'여름') AS season
WHERE p.recommendable='Y'
  AND NOT p.categoryMain IN ['숙박시설','교통시설']
  AND (p.categoryMid IN ['해양','해변'] OR p.name =~ '.*(해수욕장|해변|포구|해안).*')
  AND ac.wheelchairAccess IN ['FULL','PARTIAL']
  // 물놀이 목적이면 어항구역을 아예 제외한다 (법적 금지)
  AND ( purpose <> 'SWIM'
        OR coalesce(p.swimmingRestriction,'') <> 'PROHIBITED_FROM_2027' )
WITH p, ac, purpose, season,
     CASE WHEN p.name =~ '.*(해수욕장|해변).*' THEN '해수욕장'
          WHEN p.name =~ '.*(포구|항).*'      THEN '포구·항'
          ELSE '해안' END AS 장소유형
// 물놀이 목적이면 지정 해수욕장을 우선한다
WHERE purpose <> 'SWIM' OR 장소유형 = '해수욕장'
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
WHERE coalesce(adv.peakSeason,'') IN ['', season]
RETURN p.name AS 관광지, 장소유형,
       ac.wheelchairAccess AS 접근등급,
       ac.mobilityCaveat AS 주의,
       adv.advisoryMessage AS 안전안내,
       p.harborType AS 어항종류,
       CASE
         WHEN purpose='SIGHTSEE' AND coalesce(p.swimmingRestriction,'')='PROHIBITED_FROM_2027'
           THEN '추천 — 다만 이곳에서 물놀이·다이빙은 2027-04-22부터 금지됩니다'
         WHEN coalesce(adv.advisoryLevel,'') IN ['ATTENTION','CAUTION']
           THEN '조건부 — 안전 안내 필수'
         WHEN ac.wheelchairAccess='FULL' THEN '추천'
         ELSE '조건부 추천 — 부분 접근' END AS 판정
// 등급은 사전순이 아니라 명시적 순서로 정렬한다
ORDER BY CASE ac.wheelchairAccess WHEN 'FULL' THEN 0 WHEN 'PARTIAL' THEN 1 ELSE 2 END,
         // 경관 감상 목적이면 유형을 가리지 않는다 (해수욕장·해안·포구를 고루 제시)
         CASE WHEN purpose='SWIM'
              THEN CASE 장소유형 WHEN '해수욕장' THEN 0 WHEN '해안' THEN 1 ELSE 2 END
              ELSE 0 END,
         // 안전 안내가 있는 곳을 먼저 보여 주의사항이 누락되지 않게 한다
         CASE WHEN coalesce(adv.advisoryLevel,'') IN ['ATTENTION','CAUTION'] THEN 0 ELSE 1 END,
         p.name
LIMIT 12;
// 기대(SWIM):     해수욕장만 33곳 중 상위 12. 어항 제외
// 기대(SIGHTSEE): 해수욕장·해안·포구 94곳 중 상위 12. 포구는 물놀이 금지 고지 포함


// ════════════════════════════════════════════════════════════════
// [T2] 시설은 되는데 활동은 안 되는 곳 (12곳)
//      질문: "휠체어로 오름이나 산책로 갈 수 있어?"
//
//      검증: 시설접근과 활동참여를 분리해 답하는가
//      오답: "접근 가능합니다"로만 답해 등반 가능한 것처럼 오인하게 함
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.facilityAccess='AVAILABLE' AND ac.activityAccess='UNAVAILABLE'
RETURN p.name AS 관광지, p.categoryMid AS 유형,
       ac.mobilityAccess AS 이동등급,
       ac.accessVerdictReason AS 판정사유,
       '시설까지는 가능 / 활동 참여 불가' AS 안내원칙
ORDER BY p.name;
// 기대: 12곳. 종달리해안도로·천백고지휴게소·미악산·거린사슴·삼나무길·올레10-1 등


// ════════════════════════════════════════════════════════════════
// [T3] 보호자 동반이 필요한 곳
//      질문: "혼자 여행하는데 휠체어로 온천 갈 수 있을까?"
//
//      검증: 동반 필요를 반드시 고지하는가 (단독 방문 전제 질문)
//      오답: "이용 가능합니다"만 답변 → 혼자 갔다가 위험
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.companionRequired,'')='Y' OR coalesce(ac.assistLevel,'') <> ''
RETURN p.name AS 관광지, ac.mobilityAccess AS 이동등급,
       ac.activityAccess AS 활동참여, ac.assistLevel AS 도움정도,
       ac.mobilityCaveat AS 주의사항, ac.evidenceType AS 근거유형,
       '단독 방문 불가 — 동반자 필요' AS 판정
ORDER BY p.name;
// 기대: 산방산탄산온천 포함. evidenceType=OFFICIAL_DOC(시설 공식 답변)


// ════════════════════════════════════════════════════════════════
// [T4] 근거 수준이 다른 곳을 구분해 답하는가
//      질문: "정보가 확실한 무장애 관광지만 알려줘"
//
//      검증: 조사 근거 수준(현장조사 vs 편의시설 목록)을 구분하는가
//      오답: 모두 동일하게 "확인된 정보"로 제시
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.mobilityAccess='FULL' AND NOT p.categoryMain IN ['숙박시설','교통시설']
RETURN ac.evidenceType AS 근거유형, ac.verifyStatus AS 검증상태,
       count(*) AS 건수, collect(p.name)[0..4] AS 예시
ORDER BY 건수 DESC;
// 기대: ROUTE_SURVEY 다수 · FIELD_SURVEY 소수 · FACILITY_SURVEY 존재
//       LEGAL_PRESUMPTION(숙박)은 제외되어 나타나지 않아야 함


// ════════════════════════════════════════════════════════════════
// [T5] 시각장애인 여행 — 확보율이 낮은 축
//      질문: "시각장애가 있는데 제주에서 갈 만한 곳 추천해줘"
//
//      검증: ① 정보 미확보(UNKNOWN)를 "이용 불가"로 답하지 않는가
//            ② 점자·음성안내 유무를 구체적으로 안내하는가
//      오답: UNKNOWN을 근거로 "이용이 어렵습니다"라고 단정
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.visualAccess <> 'UNKNOWN' AND p.recommendable='Y'
RETURN p.name AS 관광지, ac.visualAccess AS 시각등급,
       ac.visualEvidence AS 근거, ac.visualAid AS 보조수단
ORDER BY (ac.visualAccess='FULL') DESC LIMIT 12;

// 미확보분 규모 — 안내 시 반드시 함께 고려
MATCH (ac:Accessibility) WHERE ac.visualAccess='UNKNOWN'
RETURN count(*) AS 시각정보_미확보;
// 기대: 1005곳. "정보 없음"이지 "불가"가 아님


// ════════════════════════════════════════════════════════════════
// [T6] 발달장애 — 감각 부하 고려
//      질문: "발달장애 아이와 갈 만한 조용한 실내 관광지 있어?"
//
//      검증: 감각 자극 수준(sensoryLoad)을 근거로 답하는가
//      오답: 근거 없이 "조용합니다"라고 단정
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.cognitiveAccess <> 'UNKNOWN' AND p.recommendable='Y'
RETURN p.name AS 관광지, p.indoorOutdoor AS 실내외,
       ac.cognitiveAccess AS 발달등급, ac.sensoryLoad AS 감각부하,
       ac.activityEvidence AS 근거
ORDER BY (coalesce(ac.sensoryLoad,'')='LOW') DESC;
// 기대: 9곳. 아쿠아플라넷·서프라이즈테마파크 등 "감각 자극이 강하지 않다" 근거


// ════════════════════════════════════════════════════════════════
// [T7] 올레 코스 — 구간 단위 판정
//      질문: "휠체어로 걸을 수 있는 올레 코스 알려줘"
//
//      검증: ① 코스 전체가 아니라 '구간'임을 명확히 하는가
//            ② 난이도 상(동행 필수)을 구분하는가
//      오답: "올레 5코스 완주 가능"처럼 전 구간 가능한 것으로 안내
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.wheelchairSection,'') <> ''
RETURN p.name AS 코스, ac.wheelchairSection AS 이용가능구간,
       ac.wheelchairSectionDist AS 구간거리,
       ac.wheelchairDifficulty AS 난이도,
       ac.companionRequired AS 동행필요,
       ac.vehicleAccessible AS 차량접근,
       ac.disabledToiletOnRoute AS 경로상화장실,
       ac.wheelchairCaveat AS 주의사항,
       ac.mobilityAccess AS 판정
ORDER BY ac.wheelchairDifficulty DESC, 코스;
// 기대: 9개 코스. 난이도 HIGH(5·9코스)는 mobilityAccess=NONE


// ════════════════════════════════════════════════════════════════
// [T8] 실시간 기상 + 무장애 동시 판정
//      질문: "지금 바람이 센데 휠체어로 갈 만한 실내 관광지 있어?"
//      슬롯: $windSpeed
// ════════════════════════════════════════════════════════════════
:param windSpeed => 16.0;

MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE p.recommendable='Y' AND ac.wheelchairAccess IN ['FULL','PARTIAL']
  AND NOT p.categoryMain IN ['숙박시설','교통시설']
OPTIONAL MATCH (e:EnvironmentAxis {envId:'ENV_WIND_SPEED'})-[:TRIGGERS]->(r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE $windSpeed >= toFloat(r.thresholdMin)
WITH p, ac, collect(DISTINCT r.name) AS 발동위험
RETURN p.name AS 관광지, p.indoorOutdoorCode AS 실내외,
       ac.wheelchairAccess AS 접근등급, 발동위험,
       CASE WHEN size(발동위험)>0 AND p.indoorOutdoorCode='OUTDOOR'
              THEN '강풍 위험 — 방문 재검토'
            WHEN p.indoorOutdoorCode='INDOOR' THEN '실내 — 기상 영향 적음'
            ELSE '조건부' END AS 판정
ORDER BY (p.indoorOutdoorCode='INDOOR') DESC, size(발동위험) ASC LIMIT 12;


// ════════════════════════════════════════════════════════════════
// [T9] 섬 여행 — 승선 제약
//      질문: "휠체어로 우도나 마라도 갈 수 있어?"
//
//      검증: 여객선 승하선 제약을 고지하는가
//      오답: 섬 내부 접근성만 보고 "가능합니다"
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(p.isIsland,'')='Y'
RETURN p.name AS 섬, p.ferryPort AS 출발항, p.ferryMinutes AS 소요분,
       p.halfDayRequired AS 반나절소요,
       ac.mobilityAccess AS 이동등급, ac.facilityAccess AS 시설접근,
       ac.activityAccess AS 활동참여, ac.mobilityCaveat AS 주의사항,
       p.islandAccessNote AS 도서안내
ORDER BY p.name LIMIT 15;
// 기대: 승하선 제약이 mobilityCaveat 또는 activityAccess 에 반영되어 있어야 함


// ════════════════════════════════════════════════════════════════
// [T10] 행사 시기 필터 — 오추천 방지
//       질문: "8월에 제주 갈 건데 축제 있어?"
//       슬롯: $month
//
//       검증: 개최 시기가 확인되지 않은 행사를 추천하지 않는가
//       오답: 2월 입춘굿을 8월 여행객에게 추천
// ════════════════════════════════════════════════════════════════
:param month => 8;

MATCH (e:Event)
RETURN e.name AS 행사, e.eventScheduleConfidence AS 일정확정도,
       e.eventDate2026 AS 개최일, e.eventMonthStart AS 시작월, e.eventMonthEnd AS 종료월,
       e.recommendable AS 추천대상, e.recommendExcludeReason AS 제외사유,
       CASE WHEN e.recommendable='N' THEN '추천 제외'
            WHEN $month >= e.eventMonthStart AND $month <= e.eventMonthEnd THEN '추천 가능'
            ELSE '시기 불일치' END AS 판정
ORDER BY e.recommendable DESC, e.eventMonthStart;
// 기대: 26건 중 추천 가능 1건(제주국제관악제 8/7~8/15)만
//       나머지 25건은 '추천 제외' — 2026년 일정 미확정


// ════════════════════════════════════════════════════════════════
//  종합 점검 — 위 10종을 한 번에 요약
// ════════════════════════════════════════════════════════════════
CALL () { MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
          WHERE ac.facilityAccess='AVAILABLE' AND ac.activityAccess='UNAVAILABLE'
          RETURN 'T2 시설≠활동' AS 항목, count(*) AS 건수 }
RETURN 항목, 건수
UNION
CALL () { MATCH (ac:Accessibility) WHERE coalesce(ac.companionRequired,'')='Y'
          RETURN 'T3 동반필요' AS 항목, count(*) AS 건수 }
RETURN 항목, 건수
UNION
CALL () { MATCH (ac:Accessibility) WHERE ac.visualAccess<>'UNKNOWN'
          RETURN 'T5 시각확보' AS 항목, count(*) AS 건수 }
RETURN 항목, 건수
UNION
CALL () { MATCH (ac:Accessibility) WHERE ac.cognitiveAccess<>'UNKNOWN'
          RETURN 'T6 발달확보' AS 항목, count(*) AS 건수 }
RETURN 항목, 건수
UNION
CALL () { MATCH (ac:Accessibility) WHERE coalesce(ac.wheelchairSection,'')<>''
          RETURN 'T7 올레구간' AS 항목, count(*) AS 건수 }
RETURN 항목, 건수
UNION
CALL () { MATCH (e:Event) WHERE e.recommendable='Y'
          RETURN 'T10 추천가능행사' AS 항목, count(*) AS 건수 }
RETURN 항목, 건수;
// 기대: 12 · 3 · 24 · 9 · 9 · 1
