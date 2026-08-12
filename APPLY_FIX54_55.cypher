// ════════════════════════════════════════════════════════════════
//  APPLY_FIX54_55_56.cypher   — 좌표·병합·재매칭 반영
//
//  전제: 아래 CSV 를 GitHub 에 푸시한 뒤 실행하십시오.
//    nodes_place.csv · nodes_accessibility.csv · place_risk_score.csv
//    rel_firevent_OCCURRED_AT_place.csv · rel_risk_APPLIES_TO_place.csv
//    rel_place_LOCATED_IN_region.csv
//
//  ⚠ 00_MASTER_LOAD.cypher 를 그대로 재실행하면 안 됩니다.
//    STAGE -1 이 DB 를 통째로 지웁니다. 지우지 않고 돌리면 MERGE 특성상
//    이번에 바뀐 관계(화재 매칭 39건·행정구역 1건)의 옛 것이 남습니다.
//    → 바뀐 관계만 먼저 지우고 다시 넣습니다.
//
//  블록 단위로 순서대로 실행하십시오.
// ════════════════════════════════════════════════════════════════

// ─── [1] Place 속성 갱신 (MATCH+SET — 노드가 새로 생기지 않습니다) ───
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_place.csv' AS row
MATCH (p:Place {placeId: row.placeId})
SET p.name              = row.name,
    p.latitude          = toFloat(row.latitude),
    p.longitude         = toFloat(row.longitude),
    p.roadAddress       = row.roadAddress,
    p.jibunAddress      = row.jibunAddress,
    p.feeGeneral        = row.feeGeneral,
    p.indoorOutdoor     = row.indoorOutdoor,
    p.indoorOutdoorCode = row.indoorOutdoorCode,
    p.recommendable     = row.recommendable,
    p.isIsland          = row.isIsland,
    p.islandName        = row.islandName,
    p.ferryPort         = row.ferryPort,
    p.islandAccessNote  = row.islandAccessNote,
    p.note              = row.note;

// P114 는 우도 입도 시설이 아닙니다. CSV 의 빈 값은 속성을 지우지 않으므로 REMOVE 합니다.
MATCH (p:Place {placeId:'P114'}) REMOVE p.islandName;


// ─── [2] 접근성 — RELOAD_ACCESSIBILITY.cypher 를 실행하십시오 ───


// ─── [3] 위험도 갱신 ───
//  ambient 임계값: LOW ≤3.5 / MEDIUM ≤12.0 / HIGH >12.0 (연평균 사고 건수, 반경 1km)
//  ※ 이 규칙은 문서에 없어 기존 933행에서 역산했습니다. 좌표가 바뀌면 재계산해야 합니다.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/place_risk_score.csv' AS row
MATCH (p:Place {placeId: row.placeId})
SET p.ambientRiskLevel = row.ambientRiskLevel,
    p.ambientAnnualAvg = toFloat(row.ambientAnnualAvg),
    p.ambientNote      = row.ambientNote;


// ─── [4] 화재 OCCURRED_AT 재매칭 — ★ 삭제 후 재생성 ★ ───
//  좌표 정정으로 최근접 장소가 바뀌었습니다. MERGE 만 하면 옛 관계가 남아
//  한 사고가 두 장소에 붙습니다. 소방 사고만 지우고 뉴스 사고는 건드리지 않습니다.
MATCH (e:AccidentEvent)-[r:OCCURRED_AT]->(:Place)
WHERE e.accidentId STARTS WITH 'AE_FIRE_'
CALL (r) { DELETE r } IN TRANSACTIONS OF 5000 ROWS;

// 삭제 확인 — 0 이어야 합니다
MATCH (e:AccidentEvent)-[r:OCCURRED_AT]->(:Place)
WHERE e.accidentId STARTS WITH 'AE_FIRE_'
RETURN count(r) AS 잔여_0이어야_함;

// 재생성
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_firevent_OCCURRED_AT_place.csv' AS row
MATCH (e:AccidentEvent {accidentId: row.accidentId}), (p:Place {placeId: row.placeId})
MERGE (e)-[:OCCURRED_AT]->(p);


// ─── [5] 행정구역 정정 (P529) ───
//  잘못된 지번주소에서 파생된 값이었습니다. 옛 관계를 지워야 합니다.
MATCH (:Place {placeId:'P529'})-[r:LOCATED_IN]->(:RegionSafetyStat)
DELETE r;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_place_LOCATED_IN_region.csv' AS row
MATCH (p:Place {placeId: row.placeId}), (rg:RegionSafetyStat {region_id: row.region_id})
MERGE (p)-[:LOCATED_IN]->(rg);


// ─── [6] 위험패턴 이관 (추가만 하므로 삭제 불필요) ───
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_risk_APPLIES_TO_place.csv' AS row
MATCH (r:RiskPattern {risk_id: row.risk_id}), (p:Place {placeId: row.placeId})
MERGE (r)-[:APPLIES_TO]->(p);


// ═══════════════════ 사후 검증 ═══════════════════

// [V1] 중복 노드 4쌍 — 8행. 대표만 recommendable='Y'
MATCH (p:Place)
WHERE p.placeId IN ['P795','P554','P625','P1027','P291','P1029','P529','P1028']
RETURN p.placeId AS 코드, p.name AS 장소, p.recommendable AS 추천,
       p.latitude AS 위도, p.longitude AS 경도
ORDER BY 추천 DESC, 코드;

// [V2] 화재 관계 수 — 관계 수와 사고 수가 같아야 합니다
MATCH (e:AccidentEvent)-[r:OCCURRED_AT]->(:Place)
WHERE e.accidentId STARTS WITH 'AE_FIRE_'
RETURN count(r) AS 화재관계, count(DISTINCT e) AS 사고수;

// [V3] 한 사고가 두 장소에 붙어 있지 않은가 — 0행
MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p:Place)
WHERE e.accidentId STARTS WITH 'AE_FIRE_'
WITH e, count(p) AS n WHERE n > 1
RETURN e.accidentId AS 사고, n AS 연결장소수;

// [V4] P529 행정구역 — REG_제주시_삼양일동 1행
MATCH (:Place {placeId:'P529'})-[:LOCATED_IN]->(rg:RegionSafetyStat)
RETURN rg.region_id AS 행정구역;

// [V5] ambient 등급 — 도립미술관 LOW / 현애원 HIGH
MATCH (p:Place) WHERE p.placeId IN ['P625','P291','P529','P841']
RETURN p.name AS 장소, p.ambientRiskLevel AS 인근위험, p.ambientAnnualAvg AS 연평균;

// [V6] 좌표 근사 보정된 곳 — 7행. 정밀 좌표 확인 대상입니다.
MATCH (p:Place) WHERE p.note CONTAINS 'APPROX'
RETURN p.placeId AS 코드, p.name AS 장소, p.latitude AS 위도, p.longitude AS 경도;
