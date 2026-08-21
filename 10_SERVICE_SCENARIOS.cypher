// ════════════════════════════════════════════════════════════════════════
//  10_SERVICE_SCENARIOS.cypher   실제 서비스 질의 흐름 테스트   (schema v3 / FIX73)
//
//  서비스 흐름:  ① 관광지 입력 → ② 대상 날짜 입력 → ③ 안전지식 선택
//  이 파일은 ③에서 고른 선택지가 실제로 답을 내는지 확인합니다.
//
//  ※ 07번(프로필·날씨 시나리오)은 "데이터가 답을 낼 수 있나" 를 봅니다.
//    이 파일은 "이용자 질의 형태 그대로 답이 나오나" 를 봅니다.
//
//  실행 전에 :param 을 먼저 실행하십시오.
//  속성명 주의 — 로더가 카멜케이스로 바꿔 넣습니다.
//    risk_name→name  risk_level→riskLevel  condition_expr→conditionExpr
//    threshold_min→thresholdMin  target_scope→targetScope  distance_m→distanceM
// ════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════
//  공통 파라미터 — 여기만 바꿔가며 전체를 돌려보십시오
// ══════════════════════════════════════════════════
:param placeName => '성산일출봉';
:param visitMonth => 8;
:param visitSeason => '여름';
// 실시간 기상 (없으면 계절 위험만 판정됨)
:param windSpeed => 0.0;
:param rainMmH => 0.0;
:param visibility => 10000;
:param waveHeight => 0.0;
:param apparentTemp => 0.0;


// ─────────────────────────────────────────────────
//  ① 장소 확인 — 이게 실패하면 뒤가 전부 무의미합니다
//     이름 완전일치이므로 place_resolver.py 로 정규화한 값을 넣으십시오.
// ─────────────────────────────────────────────────
MATCH (p:Place {name: $placeName})
RETURN p.placeId AS 코드, p.name AS 장소, p.categoryMain AS 대분류,
       p.categoryMid AS 중분류, p.indoorOutdoor AS 실내외,
       p.recommendable AS 추천대상,
       coalesce(p.isIsland,'N') AS 섬여부;
//  0행이면 이름이 안 맞는 것입니다. 아래로 후보를 찾으십시오.
MATCH (p:Place) WHERE p.name CONTAINS $placeName AND p.recommendable='Y'
RETURN p.placeId AS 코드, p.name AS 후보 LIMIT 10;


// ══════════════════════════════════════════════════
//  선택지 1 — 보행·이동 편의
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN '보행·이동 편의' AS 선택지,
       CASE coalesce(ac.mobilityAccess,'UNKNOWN')
            WHEN 'FULL' THEN '이용 가능' WHEN 'PARTIAL' THEN '부분 이용 가능'
            WHEN 'NONE' THEN '이용 어려움' ELSE '정보 미확보 — 방문 전 문의' END AS 이동,
       CASE coalesce(ac.wheelchairAccess,'UNKNOWN')
            WHEN 'FULL' THEN '이용 가능' WHEN 'PARTIAL' THEN '부분 이용 가능'
            WHEN 'NONE' THEN '이용 어려움' ELSE '정보 미확보' END AS 휠체어,
       coalesce(ac.routeCondition,'-') AS 경로상태,
       coalesce(ac.slopeInfo,'-') AS 경사,
       coalesce(ac.wheelchairSection,'') AS 무장애구간,
       coalesce(ac.wheelchairSectionDist,'') AS 구간거리,
       coalesce(ac.mobilityCaveat,'') AS 주의안내;
//  ★ 무장애구간이 있으면 구간명·거리를 반드시 함께 보여주십시오.
//    값이 '전 구간' 으로 시작하면 코스 전체 가능, 아니면 그 구간에 한합니다.
//  ★ 주의안내(mobilityCaveat)는 요약하지 마십시오. 실행 정보가 들어 있습니다.


// ══════════════════════════════════════════════════
//  선택지 2 — 어르신과 함께
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE r.risk_id STARTS WITH 'RP_HEAT' OR r.risk_id STARTS WITH 'RP_SLIP'
   OR r.risk_id STARTS WITH 'RP_COLD' OR r.risk_id STARTS WITH 'RP_FALL'
RETURN '어르신과 함께' AS 선택지,
       CASE coalesce(ac.elderlyAccess,'UNKNOWN')
            WHEN 'FULL' THEN '이용 가능' WHEN 'PARTIAL' THEN '부분 이용 가능'
            WHEN 'NONE' THEN '이용 어려움' ELSE '정보 미확보' END AS 고령접근,
       coalesce(ac.slopeInfo,'-') AS 경사,
       CASE coalesce(ac.disabledToilet,'UNKNOWN')
            WHEN 'UNKNOWN' THEN '미확인' WHEN 'NONE' THEN '없음' ELSE '있음' END AS 장애인화장실,
       collect(DISTINCT r.name) AS 주의할위험,
       coalesce(ac.companionRequired,'UNKNOWN') AS 동행필요;


// ══════════════════════════════════════════════════
//  선택지 3 — 유아차·아이 동반
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE r.risk_id STARTS WITH 'RP_CROWD' OR r.risk_id STARTS WITH 'RP_HEAT'
RETURN '유아차·아이 동반' AS 선택지,
       CASE coalesce(ac.strollerAccess,'UNKNOWN')
            WHEN 'FULL' THEN '이용 가능' WHEN 'PARTIAL' THEN '부분 이용 가능'
            WHEN 'NONE' THEN '이용 어려움' ELSE '정보 미확보' END AS 유아차,
       coalesce(ac.routeCondition,'-') AS 경로상태,
       collect(DISTINCT r.name) AS 주의할위험,
       coalesce(p.publicFacilities,'-') AS 편의시설;
//  ※ 유아차와 휠체어는 제약이 다릅니다. 계단은 유아차를 들어 넘을 수 있습니다.


// ══════════════════════════════════════════════════
//  선택지 4 — 화장실·주차
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN '화장실·주차' AS 선택지,
       CASE coalesce(ac.disabledToilet,'UNKNOWN')
            WHEN 'FULL' THEN '장애인 화장실 있음' WHEN 'PARTIAL' THEN '일부 이용 가능'
            WHEN 'NONE' THEN '없음' ELSE '미확인 — 방문 전 문의' END AS 장애인화장실,
       coalesce(p.parkingCapacity,'-') AS 주차면수,
       coalesce(p.publicFacilities,'-') AS 편의시설,
       coalesce(p.openHours,'-') AS 운영시간,
       coalesce(p.closedDays,'-') AS 휴무일;


// ══════════════════════════════════════════════════
//  선택지 5 — 날씨 주의사항  (날짜 + 실시간 기상)
// ══════════════════════════════════════════════════
//  5-A. 계절 위험 — 날짜만으로 판정되는 것
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place {name:$placeName})
WHERE (($visitMonth IN [6,7,8,9]   AND r.risk_id STARTS WITH 'RP_HEAT')
    OR ($visitMonth IN [7,8,9,10]  AND r.risk_id STARTS WITH 'RP_TYPHOON')
    OR ($visitMonth IN [12,1,2]    AND (r.risk_id STARTS WITH 'RP_SNOW'
                                     OR r.risk_id STARTS WITH 'RP_ICE'
                                     OR r.risk_id STARTS WITH 'RP_COLD'))
    OR ($visitMonth IN [3,4,5,9,10,11] AND r.risk_id STARTS WITH 'RP_AIR'))
RETURN '날씨 — 계절 위험' AS 선택지, $visitMonth AS 방문월,
       r.risk_id AS 코드, r.name AS 위험, r.riskLevel AS 등급,
       r.conditionExpr AS 발동조건, r.targetScope AS 대상범위
ORDER BY 등급 DESC;

//  5-B. 실시간 기상 위험 — 파라미터를 넣었을 때만 발동
//       기상 API 값이 없으면 결과가 비는 것이 정상입니다.
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place {name:$placeName})
WHERE (r.risk_id STARTS WITH 'RP_WIND' AND $windSpeed   >= toFloat(coalesce(r.thresholdMin,'9999')))
   OR (r.risk_id STARTS WITH 'RP_RAIN' AND $rainMmH     >= toFloat(coalesce(r.thresholdMin,'9999')))
   OR (r.risk_id STARTS WITH 'RP_WAVE' AND $waveHeight  >= toFloat(coalesce(r.thresholdMin,'9999')))
   OR (r.risk_id STARTS WITH 'RP_HEAT' AND $apparentTemp>= toFloat(coalesce(r.thresholdMin,'9999')))
   OR (r.risk_id STARTS WITH 'RP_FOG'  AND $visibility  <  toFloat(coalesce(r.thresholdMax,'0')))
OPTIONAL MATCH (r)-[:RECOMMENDS]->(act)
RETURN '날씨 — 실시간' AS 선택지, r.risk_id AS 코드, r.name AS 위험,
       r.riskLevel AS 등급, r.conditionExpr AS 발동조건,
       collect(DISTINCT act.decisionLevel) AS 권고
ORDER BY 등급 DESC;

//  5-C. 안내 문구 — 발동한 위험에 대응하는 행동 지침
//       ※ [비관광] 은 도민 생활안전 메시지이므로 제외합니다.
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place {name:$placeName})
MATCH (sa:SafetyAdvisory)-[:BASED_ON]->(r)
MATCH (sa)-[:CARRIES]->(msg:AdvisoryMessage)
WHERE NOT coalesce(msg.targetUser,'') STARTS WITH '[비관광]'
  AND NOT coalesce(sa.targetRegion,'') STARTS WITH '[비관광]'
RETURN DISTINCT '안내 문구' AS 선택지, r.name AS 위험, msg.template AS 문구,
       coalesce(msg.requiredItems,'-') AS 준비물
LIMIT 10;


// ══════════════════════════════════════════════════
//  선택지 6 — 체험·활동 가능 여부
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (p)-[:HAS_ACTIVITY]->(a:Activity)
RETURN '체험·활동' AS 선택지,
       CASE coalesce(ac.facilityAccess,'UNKNOWN')
            WHEN 'AVAILABLE' THEN '시설 접근 가능' WHEN 'CONDITIONAL' THEN '조건부'
            WHEN 'UNAVAILABLE' THEN '접근 어려움' ELSE '미확인' END AS 시설접근,
       CASE coalesce(ac.activityAccess,'UNKNOWN')
            WHEN 'AVAILABLE' THEN '체험 참여 가능' WHEN 'CONDITIONAL' THEN '조건부 참여'
            WHEN 'UNAVAILABLE' THEN '체험 참여 어려움' ELSE '미확인' END AS 활동참여,
       coalesce(ac.accessVerdictReason,'-') AS 판정근거,
       collect(DISTINCT a.nameKr) AS 활동유형,
       coalesce(ac.recommendForMobility,'Y') AS 이동축추천;
//  ★ 시설접근과 활동참여는 다릅니다. 매표소는 가도 잠수함 선내는 계단인 경우가 있습니다.


// ══════════════════════════════════════════════════
//  선택지 7 — 물놀이 안전  (해당 장소에서만 노출)
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.waterEntryNote,'') <> '' OR coalesce(ac.beachEntryNote,'') <> ''
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE r.risk_id STARTS WITH 'RP_WAVE' OR r.risk_id STARTS WITH 'RP_DROWN'
RETURN '물놀이 안전' AS 선택지,
       coalesce(ac.waterEntryNote,'') AS 입수안내,
       coalesce(ac.beachAccessRoute,'-') AS 해변접근로,
       coalesce(ac.beachEntryNote,'-') AS 해변안내,
       collect(DISTINCT r.name) AS 수난위험;
//  0행이면 물놀이 장소가 아닙니다. 선택지를 띄우지 마십시오.


// ══════════════════════════════════════════════════
//  선택지 8 — 섬 방문 준비  (해당 장소에서만 노출)
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(p.isIsland,'N') = 'Y'
RETURN '섬 방문 준비' AS 선택지,
       coalesce(p.islandName,'-') AS 섬,
       coalesce(p.ferryPort,'-') AS 출발항,
       coalesce(p.ferryMinutes,0) AS 소요분,
       coalesce(p.ferryTrips,'-') AS 운항횟수,
       coalesce(p.islandAccessNote,'-') AS 도달안내,
       coalesce(ac.mobilityCaveat,'') AS 승하선안내,
       coalesce(ac.companionRequired,'UNKNOWN') AS 동행필요;
//  0행이면 섬이 아닙니다. 선택지를 띄우지 마십시오.
//  ★ 승하선 조건은 요약하면 안 됩니다. 이용자가 현장에서 막힙니다.


// ══════════════════════════════════════════════════
//  조건부 노출 판정 — 어떤 선택지를 띄울지
// ══════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN p.name AS 장소,
       true AS 보행이동, true AS 화장실주차, true AS 날씨,
       CASE WHEN coalesce(ac.elderlyAccess,'UNKNOWN')<>'UNKNOWN'  THEN true ELSE false END AS 어르신,
       CASE WHEN coalesce(ac.strollerAccess,'UNKNOWN')<>'UNKNOWN' THEN true ELSE false END AS 유아차,
       CASE WHEN coalesce(ac.activityAccess,'UNKNOWN')<>'UNKNOWN' THEN true ELSE false END AS 체험활동,
       CASE WHEN coalesce(ac.waterEntryNote,'')<>'' THEN true ELSE false END AS 물놀이,
       CASE WHEN coalesce(p.isIsland,'N')='Y' THEN true ELSE false END AS 섬방문,
       CASE WHEN ac.visualAccess IN ['FULL','PARTIAL'] THEN true ELSE false END AS 시각편의,
       CASE WHEN ac.hearingAccess IN ['FULL','PARTIAL'] THEN true ELSE false END AS 청각편의;


// ══════════════════════════════════════════════════
//  검증 — 대표 장소 5곳이 모두 답을 내는가
//  성산일출봉(일반) · 가파도(섬) · 함덕해수욕장(물놀이)
//  세리월드(체험불가) · 제주올레 10-1코스(무장애구간)
// ══════════════════════════════════════════════════
UNWIND ['성산일출봉','가파도','함덕해수욕장','세리월드','제주올레 10-1코스'] AS nm
MATCH (p:Place {name:nm})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(p)
RETURN nm AS 장소,
       coalesce(ac.mobilityAccess,'UNKNOWN') AS 이동,
       coalesce(ac.activityAccess,'UNKNOWN') AS 활동,
       coalesce(ac.recommendForMobility,'Y') AS 게이트,
       CASE WHEN coalesce(ac.mobilityCaveat,'')<>'' THEN 'O' ELSE '★없음★' END AS 안내문구,
       CASE WHEN coalesce(ac.wheelchairSection,'')<>'' THEN ac.wheelchairSection ELSE '-' END AS 무장애구간,
       count(DISTINCT r) AS 연결위험;
//  안내문구가 '★없음★' 이면 그 장소는 답변이 빈약해집니다.
