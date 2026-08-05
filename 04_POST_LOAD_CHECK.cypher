// ════════════════════════════════════════════════════════════════
//  04_POST_LOAD_CHECK.cypher — 적재 후 일괄 검증
//
//  왜 필요한가:
//    Cypher 의 LOAD CSV + MATCH 는 대상 노드가 없어도 에러를 내지 않고
//    조용히 0건을 만듭니다. 관계가 누락돼도 적재가 "성공"으로 보입니다.
//    아래 쿼리 하나로 실제 생성 건수를 기대값과 한 번에 대조하십시오.
//
//  사용법: 00_MASTER_LOAD.cypher 를 끝까지 실행한 뒤 이 파일을 실행합니다.
// ════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────
// [1] 노드 — 기대값 대조 (diff 가 0 이어야 정상)
// ─────────────────────────────────────────────
WITH [
  ['Place',1029],['Accessibility',1029],['AccidentEvent',12353],
  ['RiskPattern',39],['EnvironmentAxis',11],['RoadSegment',15],
  ['SafetyAdvisory',20],['PlaceAdvisory',17],['DesignatedHarbor',70],
  ['TourActivity',128],['Activity',15],['VisitorProfile',14],
  ['RegionSafetyStat',73],['AdvisoryMessage',20],['RecommendationAction',9],
  ['Environment',38]
] AS spec
UNWIND spec AS row
CALL (row) {
  WITH row
  MATCH (n) WHERE row[0] IN labels(n)
  RETURN count(n) AS actual
}
RETURN row[0] AS 라벨, row[1] AS 기대, actual AS 실제,
       actual - row[1] AS diff,
       CASE WHEN actual = row[1] THEN 'OK' ELSE '*** 확인필요 ***' END AS 판정
ORDER BY diff <> 0 DESC, 라벨;

// ─────────────────────────────────────────────
// [2] 관계 — 기대값 대조
// ─────────────────────────────────────────────
WITH [
  ['HAS_ACCESSIBILITY',1029],['HAS_TOUR_ACTIVITY',1688],['LOCATED_IN',1022],
  ['APPLIES_TO',11584],['TRIGGERS',26],['EVIDENCES',535],
  ['OCCURRED_ON',19],['OCCURRED_IN_REGION',7770],
  ['SENSITIVE_TO',29],['BASED_ON',20],['TARGETS',23],['RECOMMENDS',20],
  ['MAPS_TO',20],['CARRIES',21],['RESULTS_IN',36],
  ['IS_DESIGNATED_HARBOR',24],['HAS_ADVISORY',17]
] AS spec
UNWIND spec AS row
CALL (row) {
  WITH row
  MATCH ()-[r]->() WHERE type(r) = row[0]
  RETURN count(r) AS actual
}
RETURN row[0] AS 관계, row[1] AS 기대, actual AS 실제,
       actual - row[1] AS diff,
       CASE WHEN actual = row[1] THEN 'OK' ELSE '*** 확인필요 ***' END AS 판정
ORDER BY diff <> 0 DESC, 관계;

// OCCURRED_AT 은 뉴스(571) + 소방(3499) 이 합쳐집니다
MATCH ()-[r:OCCURRED_AT]->()
RETURN count(r) AS OCCURRED_AT_실제, 4070 AS 기대,
       CASE WHEN count(r)=4070 THEN 'OK' ELSE '*** 확인필요 ***' END AS 판정;

// ─────────────────────────────────────────────
// [3] 고아 노드 — 관계가 하나도 없는 노드
//     대량으로 나오면 관계 적재가 통째로 빠진 것입니다.
// ─────────────────────────────────────────────
MATCH (n) WHERE NOT (n)--()
RETURN labels(n)[0] AS 라벨, count(*) AS 고아수
ORDER BY 고아수 DESC;
// DesignatedHarbor 46 (KG 미매칭분) 외에 큰 수가 나오면 점검 대상

// ─────────────────────────────────────────────
// [4] 핵심 경로 동작 확인 — 판단 체인이 이어지는지
// ─────────────────────────────────────────────

// 환경 임계 → 위험 → 장소
MATCH (e:EnvironmentAxis)-[:TRIGGERS]->(r:RiskPattern)-[:APPLIES_TO]->(p:Place)
RETURN e.name AS 관측축, r.name AS 위험, count(DISTINCT p) AS 장소수
ORDER BY 장소수 DESC LIMIT 10;

// 방문객 유형 → 민감 위험 → 장소
MATCH (v:VisitorProfile)-[:SENSITIVE_TO]->(r:RiskPattern)-[:APPLIES_TO]->(p:Place)
RETURN v.profile_id AS 유형, count(DISTINCT p) AS 주의장소수
ORDER BY 주의장소수 DESC;

// 사고 → 위험패턴 (근거 연결)
MATCH (a:AccidentEvent)-[:EVIDENCES]->(r:RiskPattern)
RETURN r.name AS 위험, count(a) AS 사고건수 ORDER BY 사고건수 DESC LIMIT 10;

// ─────────────────────────────────────────────
// [5] 데이터 품질 — 값 체계 준수
// ─────────────────────────────────────────────

// 접근성 4등급 외 값이 있으면 안 됨
MATCH (ac:Accessibility)
WHERE NOT ac.mobilityAccess IN ['FULL','PARTIAL','NONE','UNKNOWN']
RETURN count(*) AS 잘못된_접근등급;
// 기대: 0

// 안내 문구에 수치·사망 표현이 섞이면 안 됨
MATCH (a:PlaceAdvisory)
WHERE coalesce(a.advisoryMessage,'') =~ '.*(사망|숨진|사상자|[0-9]+명).*'
RETURN a.advisory_id, a.advisoryMessage;
// 기대: 0건

// 시행 전인데 '금지되어 있습니다'로 단정하면 안 됨
MATCH (a:PlaceAdvisory) WHERE coalesce(a.advisoryMessage,'') CONTAINS '금지되어 있습니다'
RETURN count(*) AS 단정표현;
// 기대: 0

// 개최 일정 없이 추천 가능한 행사가 있으면 안 됨
MATCH (e:Event) WHERE e.recommendable='Y' AND coalesce(e.eventDate2026,'')=''
RETURN count(*) AS 일정없이_추천가능;
// 기대: 0

// 휠체어 등급이 이동 등급을 초과하면 안 됨
MATCH (ac:Accessibility)
WHERE ac.mobilityAccess='PARTIAL' AND ac.wheelchairAccess='FULL'
   OR ac.mobilityAccess='NONE' AND ac.wheelchairAccess IN ['FULL','PARTIAL']
RETURN count(*) AS 등급모순;
// 기대: 0
