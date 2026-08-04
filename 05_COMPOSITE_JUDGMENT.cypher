// ════════════════════════════════════════════════════════════════
//  05_COMPOSITE_JUDGMENT.cypher — 복합 질의 판정 시연
//
//  "휠체어 이용자가 8월 오후에 갈 만한 제주 해안 관광지"처럼
//  접근성 · 안전이력 · 실시간 기상 · 법적 제한 · 행사 시기를
//  한 번에 판정하는 경로를 보여줍니다.
//
//  ※ 모든 속성명은 00_MASTER_LOAD.cypher 의 실제 SET 기준입니다.
// ════════════════════════════════════════════════════════════════


// ════════════════════════════════════════════════════════════════
//  [Q1] 종합 판정 — 5개 축을 한 번에 적용
//
//  질의 예: "휠체어 이용 / 8월 오후 / 바다 보고 싶어요"
//  슬롯: $profile, $month, $timeSlot, $strict
// ════════════════════════════════════════════════════════════════
:param profile => 'VP_WHEEL';
:param month => 8;
:param timeSlot => '오후';
:param strict => false;

MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)

// ── 축 1. 추천 게이트 (행사 시기 미확정 등 제외) ──────────
WHERE p.recommendable = 'Y'
  AND (p.eventMonthStart IS NULL
       OR ($month >= p.eventMonthStart AND $month <= p.eventMonthEnd))

// ── 축 2. 접근성 — 프로필별 해당 축을 선택 ────────────────
WITH p, ac,
     CASE $profile
       WHEN 'VP_WHEEL'    THEN ac.wheelchairAccess
       WHEN 'VP_MOBILITY' THEN ac.mobilityAccess
       WHEN 'VP_INFANT'   THEN ac.strollerAccess
       WHEN 'VP_OLDER'    THEN ac.elderlyAccess
       WHEN 'VP_VISUAL'   THEN ac.visualAccess
       WHEN 'VP_HEARING'  THEN ac.hearingAccess
       WHEN 'VP_DEVELOP'  THEN ac.cognitiveAccess
       ELSE ac.mobilityAccess END AS 접근등급
WHERE 접근등급 IN CASE WHEN $strict THEN ['FULL'] ELSE ['FULL','PARTIAL'] END

// ── 축 3. 프로필이 민감한 위험이 이 장소에 적용되는가 ─────
OPTIONAL MATCH (v:VisitorProfile {profile_id:$profile})-[:SENSITIVE_TO]->(sr:RiskPattern)
               -[:APPLIES_TO]->(p)
WITH p, ac, 접근등급, collect(DISTINCT sr.name) AS 민감위험

// ── 축 4. 법적 제한 (어항구역 물놀이 금지) ────────────────
WITH p, ac, 접근등급, 민감위험,
     CASE WHEN p.swimmingRestriction = 'PROHIBITED_FROM_2027'
               AND p.designationConfidence = 'CONFIRMED'
          THEN p.harborType + ' — ' + toString(p.restrictionEffectiveDate) + '부터 물놀이 금지'
          ELSE '' END AS 법적제한

// ── 축 5. 안전 안내 (계절·시간 조건이 맞을 때만) ──────────
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
WHERE (adv.peakSeason = '' OR adv.peakSeason = CASE
          WHEN $month IN [3,4,5]   THEN '봄'
          WHEN $month IN [6,7,8]   THEN '여름'
          WHEN $month IN [9,10,11] THEN '가을' ELSE '겨울' END)
  AND (adv.peakTime = '' OR adv.peakTime = $timeSlot)

RETURN p.name AS 관광지,
       p.categoryMid AS 유형,
       접근등급,
       ac.facilityAccess AS 시설접근,
       ac.activityAccess AS 활동참여,
       ac.disabledToilet AS 장애인화장실,
       ac.mobilityCaveat AS 접근주의,
       coalesce(p.directRiskScore, 0) AS 직접위험,
       p.ambientRiskLevel AS 주변위험,
       민감위험,
       법적제한,
       adv.advisoryMessage AS 안전안내,
       ac.verifyStatus AS 검증상태,
       // ── 최종 판정 ──────────────────────────────────
       CASE
         WHEN 법적제한 <> ''              THEN '조건부 — 법적 제한 있음'
         WHEN ac.activityAccess = 'UNAVAILABLE' THEN '조건부 — 시설만 이용 가능'
         WHEN adv.advisoryLevel = 'ATTENTION'   THEN '주의 필요'
         WHEN size(민감위험) > 0           THEN '주의 — 해당 유형 민감 위험'
         WHEN 접근등급 = 'FULL' AND ac.verifyStatus = 'VERIFIED' THEN '추천 (검증완료)'
         WHEN 접근등급 = 'FULL'            THEN '추천'
         ELSE '조건부 추천' END AS 판정
ORDER BY (접근등급='FULL') DESC,
         (ac.verifyStatus='VERIFIED') DESC,
         coalesce(p.directRiskScore,0) ASC
LIMIT 15;


// ════════════════════════════════════════════════════════════════
//  [Q2] 실시간 기상 반영 — 관측값이 임계를 넘으면 회피 권고
//
//  질의 예: "지금 풍속 16m/s인데 성산일출봉 가도 되나요?"
//  슬롯: $placeName, $windSpeed, $rainMmH, $visibility
// ════════════════════════════════════════════════════════════════
:param placeName => '성산일출봉';
:param windSpeed => 16.0;
:param rainMmH => 0.0;
:param visibility => 3000;

MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (e:EnvironmentAxis)-[t:TRIGGERS]->(r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE (e.envId = 'ENV_WIND_SPEED'  AND $windSpeed  >= toFloat(r.thresholdMin))
   OR (e.envId = 'ENV_RAIN_AMOUNT' AND $rainMmH    >= toFloat(r.thresholdMin))
   OR (e.envId = 'ENV_VISIBILITY'  AND $visibility <  1000)
WITH p, ac, collect(DISTINCT {위험:r.name, 등급:r.riskLevel, 조건:t.conditionExpr}) AS 발동위험
OPTIONAL MATCH (r2:RiskPattern)-[:RESULTS_IN]->(act:RecommendationAction)
WHERE r2.name IN [x IN 발동위험 | x.위험]
RETURN p.name AS 관광지,
       p.indoorOutdoor AS 실내외,
       발동위험,
       collect(DISTINCT act.action_name) AS 권고행동,
       CASE WHEN size(발동위험) = 0 THEN '기상 조건 이상 없음'
            WHEN p.indoorOutdoorCode = 'INDOOR' THEN '실내 시설 — 영향 제한적'
            ELSE '기상 위험 발동 — 방문 재검토 권장' END AS 판정;


// ════════════════════════════════════════════════════════════════
//  [Q3] 판단 근거 추적 — 왜 이렇게 판정했는가
//
//  하나의 장소에 대해 4개 축의 근거를 전부 펼쳐 보여줍니다.
//  (설명가능성 시연용 — 발표 시 이 쿼리가 핵심)
// ════════════════════════════════════════════════════════════════
:param placeName => '월령포구';

MATCH (p:Place {name:$placeName})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (p)<-[:APPLIES_TO]-(r:RiskPattern)
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
OPTIONAL MATCH (p)-[:IS_DESIGNATED_HARBOR]->(h:DesignatedHarbor)
OPTIONAL MATCH (a:AccidentEvent)-[:OCCURRED_AT]->(p)
RETURN p.name AS 관광지,
       // 근거 ① 접근성
       {이동:ac.mobilityAccess, 시각:ac.visualAccess,
        청각:ac.hearingAccess, 발달:ac.cognitiveAccess,
        근거유형:ac.evidenceType, 출처:ac.source, 기준일:ac.sourceDate} AS 접근성근거,
       // 근거 ② 사고 이력
       {직접건수:p.directAccidentCount, 유형:p.directAccidentTypes,
        주변등급:p.ambientRiskLevel, 주변근거:p.ambientBasis,
        주변설명:p.ambientNote} AS 사고근거,
       // 근거 ③ 위험 패턴
       collect(DISTINCT r.name) AS 적용위험,
       // 근거 ④ 법적 지위
       {어항명:h.harborName, 어항종류:h.harborType,
        제한:p.swimmingRestriction, 근거법령:p.restrictionLegalBasis,
        시행일:p.restrictionEffectiveDate} AS 법적근거,
       // 최종 안내 문구
       adv.advisoryMessage AS 사용자안내,
       count(DISTINCT a) AS 뉴스사고건수;


// ════════════════════════════════════════════════════════════════
//  [Q4] 시설접근 ≠ 활동참여 — 분리 판정 사례
//
//  "시설은 갈 수 있으나 활동은 못 하는" 장소를 보여줍니다.
//  단일 등급으로는 표현할 수 없는 케이스입니다.
// ════════════════════════════════════════════════════════════════
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.facilityAccess = 'AVAILABLE' AND ac.activityAccess = 'UNAVAILABLE'
RETURN p.name AS 관광지, p.categoryMid AS 유형,
       ac.mobilityAccess AS 이동등급,
       ac.accessVerdictReason AS 판정사유,
       ac.mobilityCaveat AS 주의사항
ORDER BY p.name LIMIT 20;


// ════════════════════════════════════════════════════════════════
//  [Q5] 도로 축 판정 — 관광지가 아닌 곳의 사고
//
//  1100도로처럼 목적지가 아닌 '이동 경로'의 위험을 보여줍니다.
// ════════════════════════════════════════════════════════════════
MATCH (rs:RoadSegment)
OPTIONAL MATCH (a:AccidentEvent)-[:OCCURRED_ON]->(rs)
OPTIONAL MATCH (fog:RiskPattern)-[:APPLIES_TO_ROAD]->(rs)
RETURN rs.name AS 도로, rs.routeNo AS 노선, rs.section AS 구간,
       rs.trafficRiskLevel AS 교통위험,
       count(DISTINCT a) AS 사고건수,
       collect(DISTINCT fog.name) AS 기상위험,
       rs.riskNote AS 특성
ORDER BY 사고건수 DESC, rs.trafficRiskLevel;
