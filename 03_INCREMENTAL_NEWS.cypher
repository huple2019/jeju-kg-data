// ═══════════════════════════════════════════════════════════════
//  뉴스 안전사고 증분 적재 — 03_INCREMENTAL_NEWS.cypher
//  용도: 최초 전체 적재(00_MASTER_LOAD) 이후, 추가 수집한 뉴스 사고를
//        그래프를 다시 만들지 않고 덧붙일 때 사용합니다.
//
//  전제
//   - 모든 문장이 MERGE 기반이므로 여러 번 실행해도 중복이 생기지 않습니다.
//   - 신규 파일명은 nodes_accident_event_ADD.csv 등 _ADD 접미사를 사용합니다.
//     (원본을 덮어쓰지 않아야 롤백이 가능합니다)
//
//  ⚠ ID 규칙: accidentId 는 AE_NEWS_0574 부터 이어서 발번하십시오.
//     현재 AE_NEWS_0001~0573 사용 중이며 결번은 없습니다.
//     기존 ID를 재사용하면 MERGE 가 기존 노드를 덮어씁니다.
// ═══════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────
// STEP 1. 적재 전 스냅샷 (실행 후 숫자를 기록해 두십시오)
// ─────────────────────────────────────────────
MATCH (e:AccidentEvent) WHERE e.source='news'
RETURN count(*) AS 적재전_뉴스사고;

// ─────────────────────────────────────────────
// STEP 2. 신규 뉴스 사고 노드
// ─────────────────────────────────────────────
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_accident_event_ADD.csv' AS row
MERGE (e:AccidentEvent {accidentId: row.accidentId})
SET e.articleText=row.articleText, e.date=row.date,
    e.visitMonth=row.visitMonth, e.season=row.season, e.timeSlot=row.timeSlot,
    e.weather=row.weather, e.crowdLevel=row.crowdLevel,
    e.hazardType=row.hazardType, e.accidentType=row.accidentType,
    e.severity=row.severity,
    e.victimTypeRaw=row.victimTypeRaw, e.victimGroup=row.victimGroup,
    e.cause=row.cause, e.source='news', e.sourceDetail=row.sourceDetail,
    e.latitude =CASE WHEN row.latitude <>'' THEN toFloat(row.latitude)  ELSE NULL END,
    e.longitude=CASE WHEN row.longitude<>'' THEN toFloat(row.longitude) ELSE NULL END,
    e.location =CASE WHEN row.latitude<>'' AND row.longitude<>''
      THEN point({latitude:toFloat(row.latitude),longitude:toFloat(row.longitude)}) ELSE NULL END,
    e.ingestBatch=$batchId;   // 예: '2026-08-NEWS' — 롤백/추적용

// ─────────────────────────────────────────────
// STEP 3. 관계 4종
//   placeId 가 비어 있으면 MATCH 가 실패해 조용히 건너뜁니다.
//   → STEP 5 의 검증으로 반드시 확인하십시오.
// ─────────────────────────────────────────────
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_OCCURRED_AT_place_ADD.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}), (p:Place {placeId:row.placeId})
MERGE (e)-[:OCCURRED_AT]->(p);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_EVIDENCES_riskpattern_ADD.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}), (r:RiskPattern {risk_id:row.risk_id})
MERGE (e)-[rel:EVIDENCES]->(r)
SET rel.attribution=coalesce(row.attribution,'PLACE_CONFIRMED_NEWS');

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_INVOLVED_PROFILE_ADD.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}), (v:VisitorProfile {profile_id:row.profileId})
MERGE (e)-[:INVOLVED_PROFILE]->(v);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_HAPPENED_UNDER_env_ADD.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}), (v:Environment {envId:row.envId})
MERGE (e)-[:HAPPENED_UNDER]->(v);

// ─────────────────────────────────────────────
// STEP 4. Place.accidentSummaryNews 재계산
//   이 속성은 뉴스 사고의 파생값이므로 CSV 갱신 없이 그래프에서 직접 다시 만듭니다.
//   (기존 값을 신규 포함 전체로 덮어씁니다)
// ─────────────────────────────────────────────
MATCH (p:Place)<-[:OCCURRED_AT]-(e:AccidentEvent)
WHERE e.source='news'
WITH p, e.victimGroup AS grp, e.accidentType AS typ, count(*) AS c
WITH p, grp, collect(typ+'('+toString(c)+')') AS types, sum(c) AS total
WITH p, collect(grp+'('+toString(total)+'): '+reduce(s='',t IN types | CASE WHEN s='' THEN t ELSE s+', '+t END)) AS parts
SET p.accidentSummaryNews = reduce(s='', x IN parts | CASE WHEN s='' THEN x ELSE s+' / '+x END);

// ─────────────────────────────────────────────
// STEP 5. 검증 — 반드시 확인하십시오
// ─────────────────────────────────────────────

// 5-1. 적재 건수 (STEP 1 값 + 신규 CSV 행수 와 일치해야 함)
MATCH (e:AccidentEvent) WHERE e.source='news' RETURN count(*) AS 적재후_뉴스사고;

// 5-2. 이번 배치만
MATCH (e:AccidentEvent) WHERE e.ingestBatch=$batchId RETURN count(*) AS 이번배치;

// 5-3. ⚠ 장소에 연결되지 않은 사고 — MATCH 실패로 조용히 누락된 건
MATCH (e:AccidentEvent)
WHERE e.ingestBatch=$batchId AND NOT (e)-[:OCCURRED_AT]->(:Place)
RETURN e.accidentId, e.date, left(e.articleText,40) AS 기사
ORDER BY e.accidentId;
// 기대: 0건. 건이 나오면 placeId 미매칭이므로 UnmatchedAccident 큐로 보내십시오.

// 5-4. 위험패턴 미연결 사고
MATCH (e:AccidentEvent)
WHERE e.ingestBatch=$batchId AND NOT (e)-[:EVIDENCES]->(:RiskPattern)
RETURN count(*) AS 위험패턴_미연결;

// 5-5. accidentId 중복 발번 여부 (기존 ID 재사용 시 감지)
MATCH (e:AccidentEvent) WHERE e.source='news'
WITH e.accidentId AS id, count(*) AS c WHERE c>1
RETURN id, c;
// 기대: 0건

// ─────────────────────────────────────────────
// STEP 6. 롤백 (문제 발생 시)
// ─────────────────────────────────────────────
// MATCH (e:AccidentEvent {ingestBatch:$batchId}) DETACH DELETE e;
// 이후 STEP 4 를 다시 실행해 accidentSummaryNews 를 되돌리십시오.
