// ════════════════════════════════════════════════════════════════
//  RELOAD_ACCESSIBILITY.cypher
//  nodes_accessibility.csv 만 다시 적재합니다.
//
//  전제: GitHub 에 새 nodes_accessibility.csv 를 먼저 업로드하십시오.
//  안전성: MERGE 이므로 기존 노드를 찾아 속성만 갱신합니다.
//         노드가 새로 생기거나 관계가 끊기지 않습니다. 여러 번 실행해도 무방합니다.
//  소요: 1,029행 · 수 초
// ════════════════════════════════════════════════════════════════

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_accessibility.csv' AS row
MERGE (ac:Accessibility {accessibilityId: row.accessibilityId})
SET ac.placeId=row.placeId,
    // ── 4축 접근성 (전 필드 FULL/PARTIAL/NONE/UNKNOWN 통일) ──
    ac.mobilityAccess=row.mobilityAccess,
    ac.visualAccess=row.visualAccess,
    ac.hearingAccess=row.hearingAccess,
    ac.cognitiveAccess=row.cognitiveAccess,
    // ── 세부 등급 (동일 4등급) ──────────────────────
    ac.wheelchairAccess=row.wheelchairAccess,
    ac.strollerAccess=row.strollerAccess,
    ac.elderlyAccess=row.elderlyAccess,
    ac.disabledToilet=row.disabledToilet,
    ac.transitAccess500m=row.transitAccess500m,
    // ── 시설접근 / 활동참여 분리 ────────────────────
    ac.facilityAccess=row.facilityAccess,      // AVAILABLE/CONDITIONAL/UNAVAILABLE/UNKNOWN
    ac.activityAccess=row.activityAccess,
    ac.accessVerdictReason=row.accessVerdictReason,
    // ── 서술 근거 ───────────────────────────────────
    ac.slopeInfo=row.slopeInfo, ac.routeCondition=row.routeCondition,
    ac.barrierFreeDetail=row.barrierFreeDetail,
    ac.partialReason=row.partialReason, ac.mobilityCaveat=row.mobilityCaveat,
    ac.mobilityEvidence=row.mobilityEvidence,
    ac.visualEvidence=row.visualEvidence, ac.hearingEvidence=row.hearingEvidence,
    ac.visualAid=row.visualAid, ac.hearingAid=row.hearingAid,
    ac.activityEvidence=row.activityEvidence,
    ac.toiletScope=row.toiletScope, ac.toiletScopeDesc=row.toiletScopeDesc,
    ac.moveType=row.moveType,
    // ── 지원 수준·보조 설비 ─────────────────────────
    ac.assistLevel=row.assistLevel,
    ac.wheelchairRental=row.wheelchairRental,
    ac.ticketOfficeAccess=row.ticketOfficeAccess,
    ac.wheelchairSeating=row.wheelchairSeating,
    ac.assistAvailable=row.assistAvailable,
    ac.reservationRequired=row.reservationRequired,
    ac.sensoryLoad=row.sensoryLoad,
    ac.surveySource=row.surveySource,
    ac.multiTypeSourceDate=row.multiTypeSourceDate,
    ac.dynamicObstacle=row.dynamicObstacle, ac.dynamicObstacleDesc=row.dynamicObstacleDesc,
    // ── 올레·구간 실측 ──────────────────────────────
    ac.wheelchairSection=row.wheelchairSection,
    ac.wheelchairSectionDist=row.wheelchairSectionDist,
    ac.wheelchairDifficulty=row.wheelchairDifficulty,   // LOW/MEDIUM/HIGH
    ac.wheelchairCaveat=row.wheelchairCaveat,
    ac.companionRequired=row.companionRequired,
    ac.vehicleAccessible=row.vehicleAccessible,
    ac.disabledToiletOnRoute=row.disabledToiletOnRoute,
    // ── 숙박 ────────────────────────────────────────
    ac.accessibleRoomCount=CASE WHEN row.accessibleRoomCount<>'' THEN toInteger(row.accessibleRoomCount) ELSE NULL END,
    ac.accessibleRoomNote=row.accessibleRoomNote,
    // ── 출처·검증 ───────────────────────────────────
    ac.openTourismSite=row.openTourismSite,
    ac.source=row.source, ac.sourceDate=row.sourceDate, ac.sourceCheckUrl=row.sourceCheckUrl,
    ac.multiTypeSource=row.multiTypeSource, ac.multiTypeNote=row.multiTypeNote,
    ac.verifyStatus=row.verifyStatus,          // VERIFIED/SURVEYED/PARTIAL/PENDING/EXCLUDED
    ac.verifyNote=row.verifyNote,
    ac.evidenceType=row.evidenceType,          // FIELD_SURVEY/OFFICIAL_DOC/PUBLICATION/...
    ac.correctionHistory=row.correctionHistory,
    ac.schemaVersion=row.schemaVersion;

// ── 확인 ────────────────────────────────────────────
MATCH (ac:Accessibility)
RETURN ac.evidenceType AS 근거유형, count(*) AS 건수 ORDER BY 건수 DESC;
// 기대: ROUTE_SURVEY 692 · FACILITY_SURVEY 251 · FIELD_SURVEY 49
//       LEGAL_PRESUMPTION 18 · PUBLICATION 15 · OFFICIAL_DOC 3 · NOT_APPLICABLE 1

MATCH (ac:Accessibility)
RETURN ac.verifyStatus AS 검증상태, count(*) AS 건수 ORDER BY 건수 DESC;
// 기대: SURVEYED 891 · VERIFIED 110 · PENDING 17 · PARTIAL 10 · EXCLUDED 1

// 산방산탄산온천 — 이번 정정 반영 확인
MATCH (p:Place {name:'산방산탄산온천'})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN ac.mobilityAccess, ac.activityAccess, ac.companionRequired,
       ac.evidenceType, ac.mobilityCaveat;
// 기대: PARTIAL / CONDITIONAL / Y / OFFICIAL_DOC / 탕 내부에 계단이…
