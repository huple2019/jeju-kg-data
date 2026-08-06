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
// [T1] 휠체어 + 바다 — 방문 목적과 계절에 따라 판정이 갈린다
//
//      슬롯: $month(1~12), $purpose('SWIM'|'SIGHTSEE')
//      질문 예:
//        "8월에 휠체어로 물놀이할 수 있는 바다"   → month=8,  purpose='SWIM'
//        "1월에 휠체어로 바다 보러 갈 곳"          → month=1,  purpose='SIGHTSEE'
//        "10월에 휠체어로 해안 산책"               → month=10, purpose='SIGHTSEE'
//
//      계절이 판정을 바꾸는 지점
//        · 해수욕장 안전요원은 성수기(7~8월)에만 배치됩니다.
//          그 외 기간의 입수는 안전요원 없이 하는 것이므로 별도 경고가 필요합니다.
//        · 가을(9~11)에는 갯바위·테트라포드 낚시 사고 주의보가 발령됩니다.
//        · 겨울(12~2)에는 해안 결빙·강풍이, 여름(7~9)에는 태풍이 변수입니다.
//        · 어항 물놀이 금지는 계절과 무관하게 적용됩니다.
//
//      휠체어 × 해변에서 반드시 나가야 할 두 가지
//        · 모래사장은 바퀴가 빠져 이동이 어렵습니다. 진입로·데크가 있는 곳은 4곳뿐이며
//          나머지는 미확인이므로 "접근 가능"으로 뭉뚱그리면 안 됩니다.
//        · 입수는 접근과 별개입니다. 동행자 없이 깊은 물에 들어가면
//          파도에 중심을 잃고 스스로 빠져나오기 어렵습니다.
//
//      검증: ① 비수기 입수에 안전요원 부재 경고가 나가는가
//            ② 해당 월의 소방 계절 주의보가 함께 제시되는가
//            ③ SWIM 이면 어항이 제외되고, SIGHTSEE 면 포함되되 금지가 고지되는가
//            ④ 모래사장 이동 제약과 입수 시 동행 필요가 안내되는가
//      오답: "접근 가능합니다"로만 답해 모래사장을 건널 수 있는 것처럼 오인하게 함
//            1월에 "안전요원 근무 시간대를 이용하세요"만 안내 (그 시기엔 근무 안 함)
// ════════════════════════════════════════════════════════════════
:param month   => 8;          // 1~12
:param purpose => 'SWIM';     // 'SWIM' | 'SIGHTSEE'

// :param 없이 실행해도 동작합니다(기본 8월·SWIM).
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WITH p, ac,
     coalesce($month, 8) AS mon,
     coalesce($purpose, 'SWIM') AS purpose
WITH p, ac, mon, purpose,
     CASE WHEN mon IN [3,4,5] THEN '봄' WHEN mon IN [6,7,8] THEN '여름'
          WHEN mon IN [9,10,11] THEN '가을' ELSE '겨울' END AS season,
     (mon IN [7,8]) AS 해수욕장_개장기간
WHERE p.recommendable='Y'
  AND NOT p.categoryMain IN ['숙박시설','교통시설']
  AND (p.categoryMid IN ['해양','해변'] OR p.name =~ '.*(해수욕장|해변|포구|해안).*')
  AND ac.wheelchairAccess IN ['FULL','PARTIAL']
  AND ( purpose <> 'SWIM'
        OR coalesce(p.swimmingRestriction,'') <> 'PROHIBITED_FROM_2027' )
WITH p, ac, mon, purpose, season, 해수욕장_개장기간,
     CASE WHEN p.name =~ '.*(해수욕장|해변).*' THEN '해수욕장'
          WHEN p.name =~ '.*(포구|항).*'      THEN '포구·항'
          ELSE '해안' END AS 장소유형
WHERE purpose <> 'SWIM' OR 장소유형 = '해수욕장'

// 장소별 안전 안내 — 해당 계절 것만
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
WHERE coalesce(adv.peakSeason,'') IN ['', season]

// 해당 월에 발령되는 소방 계절 주의보 (해양·낚시·기상 관련만)
OPTIONAL MATCH (sa:SafetyAdvisory)
WHERE toString(mon) IN split(coalesce(sa.issue_months,''), ',')
  AND coalesce(sa.advisory_name,'') =~ '.*(수난|낚시|태풍|폭염|미끄러짐|야외활동).*'

WITH p, ac, mon, purpose, season, 해수욕장_개장기간, 장소유형, adv,
     collect(DISTINCT coalesce(sa.advisory_name,'')) AS 계절주의보
RETURN p.name AS 관광지, 장소유형, season AS 계절,
       ac.wheelchairAccess AS 접근등급,
       ac.mobilityCaveat AS 주의,
       adv.advisoryMessage AS 안전안내,
       [x IN 계절주의보 WHERE x <> ''] AS 발령중_주의보,
       // 휠체어 × 해변 특화 안내 — 모래사장 이동과 입수는 별개 문제
       CASE WHEN 장소유형='해수욕장' THEN ac.beachEntryNote ELSE '' END AS 모래사장_이동,
       CASE WHEN 장소유형='해수욕장' AND purpose='SWIM'
            THEN ac.waterEntryNote ELSE '' END AS 입수_주의,
       // 계절이 만드는 추가 안내
       CASE
         WHEN purpose='SWIM' AND NOT 해수욕장_개장기간
           THEN '※ 해수욕장 개장기간(7~8월)이 아닙니다. 안전요원이 배치되지 않으므로 입수를 권하지 않습니다'
         WHEN season='가을' AND 장소유형 IN ['해안','포구·항']
           THEN '※ 갯바위·테트라포드 낚시 사고가 잦은 시기입니다. 방파제 위로 올라가지 마세요'
         WHEN season='겨울'
           THEN '※ 해안 강풍과 결빙에 유의하시고, 파도가 높은 날은 방문을 미루십시오'
         WHEN season='봄' AND 장소유형='해안'
           THEN '※ 해무가 끼는 시기입니다. 시야가 나쁠 때는 해안 산책을 자제하십시오'
         ELSE '' END AS 계절안내,
       CASE
         WHEN purpose='SIGHTSEE' AND coalesce(p.swimmingRestriction,'')='PROHIBITED_FROM_2027'
           THEN '추천 — 다만 이곳에서 물놀이·다이빙은 2027-04-22부터 금지됩니다'
         WHEN purpose='SWIM' AND NOT 해수욕장_개장기간
           THEN '비추천 — 비개장기 입수'
         WHEN coalesce(adv.advisoryLevel,'') IN ['ATTENTION','CAUTION']
           THEN '조건부 — 안전 안내 필수'
         WHEN ac.wheelchairAccess='FULL' THEN '추천'
         ELSE '조건부 추천 — 부분 접근' END AS 판정
ORDER BY CASE ac.wheelchairAccess WHEN 'FULL' THEN 0 WHEN 'PARTIAL' THEN 1 ELSE 2 END,
         CASE WHEN purpose='SWIM'
              THEN CASE 장소유형 WHEN '해수욕장' THEN 0 WHEN '해안' THEN 1 ELSE 2 END
              ELSE 0 END,
         CASE WHEN coalesce(adv.advisoryLevel,'') IN ['ATTENTION','CAUTION'] THEN 0 ELSE 1 END,
         p.name
LIMIT 12;
// 기대(8월·SWIM):    해수욕장만. 발령중_주의보에 여름철 수난사고·폭염·태풍
// 기대(1월·SWIM):    전 건에 "개장기간 아님 — 입수 권하지 않음", 판정=비추천
// 기대(10월·SIGHTSEE): 포구·해안 포함, 갯바위 낚시 주의 + 물놀이 금지 고지


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
:param month => 8;
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WITH p, ac, coalesce($month,8) AS mon
WITH p, ac, mon,
     CASE WHEN mon IN [3,4,5] THEN '봄' WHEN mon IN [6,7,8] THEN '여름'
          WHEN mon IN [9,10,11] THEN '가을' ELSE '겨울' END AS season
WHERE coalesce(ac.wheelchairSection,'') <> ''
RETURN p.name AS 코스, season AS 계절, ac.wheelchairSection AS 이용가능구간,
       ac.wheelchairSectionDist AS 구간거리,
       ac.wheelchairDifficulty AS 난이도,
       ac.companionRequired AS 동행필요,
       ac.vehicleAccessible AS 차량접근,
       ac.disabledToiletOnRoute AS 경로상화장실,
       ac.wheelchairCaveat AS 주의사항,
       CASE season
         WHEN '여름' THEN '※ 그늘이 적은 구간이 있습니다. 폭염 시간대(11~16시)를 피하고 수분을 준비하십시오'
         WHEN '겨울' THEN '※ 해안 구간은 강풍과 결빙에 유의하시고, 일몰이 이르니 오후 3시 이후 출발은 피하십시오'
         WHEN '가을' THEN '※ 갯바위·방파제 구간은 낚시 사고가 잦은 시기입니다. 지정 경로를 벗어나지 마십시오'
         ELSE '※ 해무가 끼면 시야가 급격히 나빠집니다. 기상을 확인하고 출발하십시오' END AS 계절안내,
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
:param month => 8;
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WITH p, ac, coalesce($month,8) AS mon
WITH p, ac, mon,
     CASE WHEN mon IN [3,4,5] THEN '봄' WHEN mon IN [6,7,8] THEN '여름'
          WHEN mon IN [9,10,11] THEN '가을' ELSE '겨울' END AS season
WHERE coalesce(p.isIsland,'')='Y'
RETURN p.name AS 섬, season AS 계절, p.ferryPort AS 출발항, p.ferryMinutes AS 소요분,
       p.halfDayRequired AS 반나절소요,
       ac.mobilityAccess AS 이동등급, ac.facilityAccess AS 시설접근,
       ac.activityAccess AS 활동참여, ac.mobilityCaveat AS 주의사항,
       p.islandAccessNote AS 도서안내,
       CASE season
         WHEN '겨울' THEN '※ 북서풍이 강해 결항이 잦은 시기입니다. 당일 운항 여부를 반드시 확인하십시오'
         WHEN '여름' THEN '※ 태풍 내습 시 결항되며, 섬에 고립될 수 있습니다. 기상 예보를 확인하십시오'
         WHEN '가을' THEN '※ 너울성 파도로 결항될 수 있습니다. 출항 전 확인하십시오'
         ELSE '※ 해무로 결항될 수 있습니다. 출항 전 확인하십시오' END AS 계절_결항주의,
       '휠체어 이용 시 승하선에 도움이 필요합니다. 선사에 미리 알려 주십시오' AS 승선안내
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
