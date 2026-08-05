// ════════════════════════════════════════════════════════════════
//  질의 4유형 판단 Cypher 템플릿 (중간보고 슬라이드 20·21·24·25 구현)
//  공통 판단 블록: Environment × Activity × Profile → RiskPattern → RESULTS_IN → Action
//  $파라미터는 STEP1(LLM 질의이해)에서 추출한 슬롯
//  안전 판정은 이 그래프 규칙이 전부 수행 — LLM 미개입
// ════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────
// [유형 1] 일정형 ITINERARY  "3박4일 갈 만한 곳 추천"
//   전체 관광지 → 하드필터(제외) → 소프트랭킹 → 카테고리 다양성
//   슬롯: $days, $profile(선택), $month
// ─────────────────────────────────────────────────────────────
// LAYER1 하드필터
MATCH (p:Place)
WHERE p.event2026Status <> 'CONTROLLED'                    // 통제 관광지 제외
  AND NOT EXISTS {                                          // 최근 6개월 사망/중상 발생지 제외
    MATCH (p)<-[:OCCURRED_AT]-(e:AccidentEvent)
    WHERE e.severity IN ['사망','중상']
      AND e.date >= date() - duration({months:6})
  }
// LAYER2 소프트랭킹: 대표성 + 안전이력(directRiskScore 낮을수록 우선)
// ※ directRiskScore = 해당 장소에서 실제 발생한 사고(뉴스 확정)만 반영
WITH p,
     CASE p.placeRank WHEN 'POPULAR' THEN 3 WHEN 'CENTRAL' THEN 2 ELSE 1 END AS pop,
     coalesce(p.directRiskScore,0.0) AS risk
ORDER BY pop DESC, risk ASC
// LAYER3 카테고리 다양성: 동일 categoryMid 최대 2개
WITH p.categoryMid AS cat, collect(p)[0..2] AS picks
UNWIND picks AS place
RETURN place.name, place.categoryMid, place.placeRank, place.directRiskScore,
       CASE WHEN coalesce(place.ambientRiskLevel,'')='HIGH' THEN place.ambientNote ELSE '' END AS 주변사고
LIMIT 12;

// ─────────────────────────────────────────────────────────────
// [유형 2] 앵커근접형 ANCHOR  "산방산 근처 가볼 만한 곳"
//   앵커 위험 선점검 → 거리기반 주변후보 → 후보 위험판정
//   슬롯: $anchor(관광지명), $radius_km(기본5), $profile(선택)
// ─────────────────────────────────────────────────────────────
MATCH (anchor:Place {name:$anchor})
// ⓐ 앵커 자체 위험 선점검 (통제/위험패턴 적용 여부)
OPTIONAL MATCH (anchor)<-[:APPLIES_TO]-(ar:RiskPattern)-[:RESULTS_IN]->(aa:RecommendationAction)
WITH anchor, collect(DISTINCT {risk:ar.name, action:aa.nameKr, level:aa.decisionLevel}) AS anchorRisk
// ⓑ 거리기반 주변후보 (Aura point.distance)
MATCH (cand:Place)
WHERE cand <> anchor
  AND point.distance(anchor.location, cand.location) <= coalesce($radius_km,5)*1000
  AND cand.event2026Status <> 'CONTROLLED'
// ⓒ 후보별 위험체인 + 프로필 취약성 결합
OPTIONAL MATCH (cand)<-[:APPLIES_TO]-(r:RiskPattern)-[:RESULTS_IN]->(act:RecommendationAction)
OPTIONAL MATCH (vp:VisitorProfile {type:$profile})-[:SENSITIVE_TO]->(r)
WITH anchor, anchorRisk, cand,
     point.distance(anchor.location, cand.location) AS dist,
     collect(DISTINCT act.decisionLevel) AS decisions,
     count(vp) AS profileSensitive,
     coalesce(cand.directRiskScore,0) AS risk
// ⓓ 판정 도출: 회피>시간조정>주의>GO
WITH anchor, anchorRisk, cand, dist, risk,
     CASE WHEN '회피' IN decisions THEN '회피'
          WHEN '시간조정' IN decisions THEN '시간조정'
          WHEN '주의' IN decisions OR profileSensitive>0 THEN '주의'
          ELSE 'GO' END AS decision
RETURN cand.name, round(dist) AS 거리m, decision, cand.directRiskScore,
       CASE WHEN coalesce(cand.ambientRiskLevel,'')='HIGH' THEN cand.ambientNote ELSE '' END AS 주변사고
ORDER BY (decision='GO') DESC, risk ASC, dist ASC
LIMIT 8;

// ─────────────────────────────────────────────────────────────
// [유형 3] 상황확인형 STATUS  "내일 우도 가도 될까?"  (추천 없이 판정만)
//   슬롯: $place, $profile(선택), $activity(선택)
// ─────────────────────────────────────────────────────────────
MATCH (p:Place {name:$place})
// 연결된 통제·위험·사고이력 수집
OPTIONAL MATCH (p)<-[:APPLIES_TO]-(r:RiskPattern)-[:RESULTS_IN]->(act:RecommendationAction)
OPTIONAL MATCH (p)<-[:OCCURRED_AT]-(e:AccidentEvent)
OPTIONAL MATCH (a:Activity {nameEn:$activity})-[:CARRIES]->(r)         // 활동 위험 결합
OPTIONAL MATCH (vp:VisitorProfile {type:$profile})-[:SENSITIVE_TO]->(r) // 프로필 위험 결합
WITH p,
     collect(DISTINCT r.name) AS risks,
     collect(DISTINCT act.decisionLevel) AS decisions,
     count(DISTINCT e) AS accidentCount,
     count(DISTINCT vp) AS profileSensitive
RETURN p.name,
       CASE WHEN '회피' IN decisions THEN '회피'
            WHEN '시간조정' IN decisions THEN '시간조정'
            WHEN size(risks)>0 OR profileSensitive>0 THEN '주의'
            ELSE 'GO' END AS 판정,
       risks AS 위험요인, accidentCount AS 사고이력건수;

// ─────────────────────────────────────────────────────────────
// [유형 4] 조건탐색형 CONDITION  "휠체어로 갈 수 있는 해안 산책로"
//   접근성 조건에서 역방향 진입 → 프로필 민감위험 제외 → 지원시설순
//   슬롯: $accessNeed(wheelchair|stroller|elderly|visual|hearing|cognitive),
//         $placeType, $strict(bool), $month(1~12)
// ─────────────────────────────────────────────────────────────
// ※ v3 값 체계: 접근성 전 필드는 FULL / PARTIAL / NONE / UNKNOWN (Y/N 폐지)
//    $strict=true 이면 FULL 만, false 이면 FULL+PARTIAL 허용
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE p.recommendable='Y'                                   // 행사 등 추천 제외 대상 차단
  AND ( (p.eventMonthStart IS NULL)                          // 상시 운영
     OR ($month >= p.eventMonthStart AND $month <= p.eventMonthEnd) )
WITH p, ac,
     CASE $accessNeed
       WHEN 'wheelchair' THEN ac.wheelchairAccess
       WHEN 'stroller'   THEN ac.strollerAccess
       WHEN 'elderly'    THEN ac.elderlyAccess
       WHEN 'visual'     THEN ac.visualAccess
       WHEN 'hearing'    THEN ac.hearingAccess
       WHEN 'cognitive'  THEN ac.cognitiveAccess
       ELSE ac.mobilityAccess END AS grade
WHERE grade IN CASE WHEN $strict THEN ['FULL'] ELSE ['FULL','PARTIAL'] END
  AND ($placeType IS NULL OR p.categorySub CONTAINS $placeType OR p.categoryMid CONTAINS $placeType)
// 시설은 되나 활동참여가 불가한 곳은 명시 (등산·수상레저 등)
WITH p, ac, grade
OPTIONAL MATCH (p)<-[:APPLIES_TO]-(r:RiskPattern)
WITH p, ac, grade, collect(DISTINCT r.name) AS risks,
     coalesce(p.directRiskScore,0) AS risk
RETURN p.name, p.categorySub, grade AS 접근등급,
       ac.disabledToilet AS 장애인화장실, ac.slopeInfo AS 경사정보,
       ac.facilityAccess AS 시설접근, ac.activityAccess AS 활동참여,
       ac.mobilityCaveat AS 주의사항, ac.verifyStatus AS 검증상태,
       // 주변 사고 경고 — 랭킹이 아닌 안내 문구
       CASE WHEN coalesce(p.ambientRiskLevel,'')='HIGH' THEN '⚠ '+p.ambientNote ELSE '' END AS 주변사고경고,
       CASE
         WHEN ac.activityAccess='UNAVAILABLE' THEN '시설만 이용 가능 (활동 참여 불가)'
         WHEN size(risks)>0 THEN '주의: '+risks[0]
         ELSE '추천' END AS 판정
ORDER BY (grade='FULL') DESC, (ac.verifyStatus='VERIFIED') DESC, risk ASC
LIMIT 8;

// ════════════════════════════════════════════════════════════════
//  전체 판단 체인 1건 검증 (경로가 실제로 이어지는지 확인)
//  Activity → CARRIES → RiskPattern → RESULTS_IN → Action, 그리고
//  RiskPattern → APPLIES_TO → Place 까지 한 번에
// ════════════════════════════════════════════════════════════════
// MATCH path = (a:Activity {nameEn:'Diving'})-[:CARRIES]->(r:RiskPattern)
//   -[:RESULTS_IN]->(act:RecommendationAction)
// OPTIONAL MATCH (r)-[:APPLIES_TO]->(p:Place)
// OPTIONAL MATCH (e:AccidentEvent)-[:EVIDENCES]->(r)
// OPTIONAL MATCH (s:SafetyAdvisory)-[:BASED_ON]->(r)
// RETURN a.nameKr AS 활동, r.name AS 위험, act.nameKr AS 행동안내,
//        count(DISTINCT p) AS 적용관광지, count(DISTINCT e) AS 사고근거, count(DISTINCT s) AS 주의보근거;
