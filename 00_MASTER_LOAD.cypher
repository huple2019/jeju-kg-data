// ════════════════════════════════════════════════════════════════
//  제주 안전관광 지식그래프 — 마스터 적재 스크립트
//  중간보고 최종 스키마(노드 10종) 기준 · 판단 경로까지 동작
//  실행 순서를 반드시 지킬 것 (노드 → 관계, 상위 zip → 브리지)
//  데이터 출처: GitHub raw URL (Neo4j Aura는 file:/// 를 지원하지 않음)
//  ⚠ 저장소 경로가 다르면 아래 URL 을 일괄 치환하십시오.
//     https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/
// ════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════
//  STAGE -1. 기존 데이터 전체 삭제 (v2 → v3 전환 시 필수)
//
//  ⚠ 반드시 먼저 실행하십시오.
//     MERGE 는 기존 노드를 재사용하므로, 삭제 없이 적재하면
//     ① v2 의 구 속성(barrierFree, riskScore 등)이 그대로 남고
//     ② 이번에 제거한 관계(안개 229곳 → 29곳 등)가 삭제되지 않으며
//     ③ 사고 ID 재채번으로 잘못된 OCCURRED_AT 관계가 중복 생성됩니다.
//
//  Aura 콘솔의 "Clear database" 를 쓰거나, 아래를 배치로 실행하십시오.
// ════════════════════════════════════════════════════════════════

// 관계·노드 일괄 삭제 (대용량이므로 배치 처리)
CALL { MATCH (n) DETACH DELETE n } IN TRANSACTIONS OF 10000 ROWS;

// 삭제 확인 — 0 이어야 함
MATCH (n) RETURN count(n) AS 잔여노드;

// 구 제약조건·인덱스도 정리하려면 (선택)
// SHOW CONSTRAINTS YIELD name RETURN 'DROP CONSTRAINT '+name+';' AS cmd;
// SHOW INDEXES     YIELD name, type WHERE type<>'LOOKUP'
//   RETURN 'DROP INDEX '+name+';' AS cmd;


// ─────────────────────────────────────────────
// STAGE 0. 제약조건 (모든 노드 키 유니크)
// ─────────────────────────────────────────────
CREATE CONSTRAINT place_id       IF NOT EXISTS FOR (p:Place)                REQUIRE p.placeId IS UNIQUE;
CREATE CONSTRAINT tour_act_id    IF NOT EXISTS FOR (a:TourActivity)         REQUIRE a.activityId IS UNIQUE;
CREATE CONSTRAINT activity_id    IF NOT EXISTS FOR (a:Activity)             REQUIRE a.activity_id IS UNIQUE;
CREATE CONSTRAINT acc_id         IF NOT EXISTS FOR (ac:Accessibility)       REQUIRE ac.accessibilityId IS UNIQUE;
CREATE CONSTRAINT accident_id    IF NOT EXISTS FOR (e:AccidentEvent)        REQUIRE e.accidentId IS UNIQUE;
CREATE CONSTRAINT env_id         IF NOT EXISTS FOR (v:Environment)          REQUIRE v.envId IS UNIQUE;
CREATE CONSTRAINT vprofile_id    IF NOT EXISTS FOR (v:VisitorProfile)       REQUIRE v.profile_id IS UNIQUE;
CREATE CONSTRAINT risk_id        IF NOT EXISTS FOR (r:RiskPattern)          REQUIRE r.risk_id IS UNIQUE;
CREATE CONSTRAINT advisory_id    IF NOT EXISTS FOR (s:SafetyAdvisory)       REQUIRE s.advisory_id IS UNIQUE;
CREATE CONSTRAINT place_advisory  IF NOT EXISTS FOR (s:PlaceAdvisory)        REQUIRE s.advisory_id IS UNIQUE;
CREATE CONSTRAINT message_id     IF NOT EXISTS FOR (m:AdvisoryMessage)      REQUIRE m.message_id IS UNIQUE;
CREATE CONSTRAINT action_id      IF NOT EXISTS FOR (a:RecommendationAction) REQUIRE a.action_id IS UNIQUE;
CREATE CONSTRAINT region_id      IF NOT EXISTS FOR (g:RegionSafetyStat)     REQUIRE g.region_id IS UNIQUE;

// ─────────────────────────────────────────────
// STAGE 1. 관광 KG 노드 (zip: jeju_kg_neo4j_csv)
//   Place / TourActivity / Accessibility / 뉴스 AccidentEvent / Environment / VisitorProfile(사고피해자)
//   ※ KG Activity는 위험판단용 Activity와 구분 위해 :TourActivity 라벨로 적재
// ─────────────────────────────────────────────
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_place.csv' AS row
MERGE (p:Place {placeId: row.placeId})
SET p.name=row.name, p.categoryMain=row.categoryMain, p.categoryMid=row.categoryMid,
    p.categorySub=row.categorySub, p.placeType=row.placeType, p.placeRank=row.placeRank,
    p.mainActivity=row.mainActivity, p.functionTags=row.functionTags,
    p.indoorOutdoor=row.indoorOutdoor,
    p.latitude=toFloat(row.latitude), p.longitude=toFloat(row.longitude),
    p.location=CASE WHEN row.latitude<>'' AND row.longitude<>''
      THEN point({latitude:toFloat(row.latitude),longitude:toFloat(row.longitude)}) ELSE NULL END,
    p.capacity=toInteger(row.capacity), p.parkingCapacity=toInteger(row.parkingCapacity),
    p.publicFacilities=row.publicFacilities,
    p.accidentSummary1km=row.accidentSummary1km, p.accidentSummaryNews=row.accidentSummaryNews,
    p.roadAddress=row.roadAddress, p.jibunAddress=row.jibunAddress,
    // ── v3 정규화 코드 ──────────────────────────────
    p.placeKind=row.placeKind,                 // SPOT / VENUE / AREA / EVENT
    p.indoorOutdoorCode=row.indoorOutdoorCode, // INDOOR / OUTDOOR / MIXED / UNKNOWN
    // ── 도서(섬) ────────────────────────────────────
    p.isIsland=row.isIsland, p.islandName=row.islandName,
    p.ferryPort=row.ferryPort,
    p.ferryMinutes=CASE WHEN row.ferryMinutes<>'' THEN toInteger(row.ferryMinutes) ELSE NULL END,
    p.halfDayRequired=row.halfDayRequired,
    // ── 이용 정보 ───────────────────────────────────
    p.feeGeneral=row.feeGeneral, p.feeDisabled=row.feeDisabled,
    p.openHours=row.openHours, p.closedDays=row.closedDays,
    p.durationMin=row.durationMin, p.homepage=row.homepage,
    // ── 행사 개최 시기 ──────────────────────────────
    p.event2026Status=row.eventStatus2026,
    p.eventMonthStart=CASE WHEN row.eventMonthStart<>'' THEN toInteger(row.eventMonthStart) ELSE NULL END,
    p.eventMonthEnd  =CASE WHEN row.eventMonthEnd  <>'' THEN toInteger(row.eventMonthEnd)   ELSE NULL END,
    p.eventDate2026=row.eventDate2026,
    p.eventScheduleConfidence=row.eventScheduleConfidence,
    p.eventPeriodNote=row.eventPeriodNote,
    // ── 추천 게이트 ─────────────────────────────────
    p.recommendable=row.recommendable,
    p.recommendExcludeReason=row.recommendExcludeReason,
    // ── 도서 접근·시설 성격 ─────────────────────────
    p.ferryTrips=row.ferryTrips, p.islandAccessNote=row.islandAccessNote,
    p.facilityNature=row.facilityNature,
    p.note=row.note;

// 보조 라벨 — 기간·구역 필터를 라벨로 강제할 수 있게 함
MATCH (p:Place) WHERE p.placeKind='EVENT' SET p:Event;
MATCH (p:Place) WHERE p.placeKind='AREA'  SET p:Area;
MATCH (p:Place) WHERE p.placeKind='VENUE' SET p:ExperienceVenue;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_activity.csv' AS row
MERGE (a:TourActivity {activityId: row.activityId}) SET a.name=row.name;

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
    ac.recommendForMobility=row.recommendForMobility,  // Y/N — 이동축 추천 대상
    ac.recommendForVisual=row.recommendForVisual,      // Y/N/UNKNOWN
    ac.recommendForHearing=row.recommendForHearing,
    ac.sensoryAccessNote=row.sensoryAccessNote,        // 감각축 확인 안내
    ac.beachAccessRoute=row.beachAccessRoute,   // 있음/미확인 — 백사장 진입로
    ac.beachEntryNote=row.beachEntryNote,       // 모래사장 이동 안내
    ac.waterEntryNote=row.waterEntryNote,       // 입수 시 동행 안내
    ac.evidenceType=row.evidenceType,          // FIELD_SURVEY/OFFICIAL_DOC/PUBLICATION/...
    ac.correctionHistory=row.correctionHistory,
    ac.schemaVersion=row.schemaVersion;

// 미확보 축 오안내 차단
MATCH (ac:Accessibility)
WHERE ac.visualAccess='UNKNOWN' OR ac.hearingAccess='UNKNOWN' OR ac.cognitiveAccess='UNKNOWN'
SET ac.unknownAxisNote='해당 장애 유형 정보는 미확보 상태입니다. '
  + '열린관광 모두의여행(access.visitkorea.or.kr) 또는 이지제주(easyjeju.net)에서 확인하시기 바랍니다.';

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_accident_event.csv' AS row
MERGE (e:AccidentEvent {accidentId: row.accidentId})
SET e.source='news', e.attribution='PLACE_CONFIRMED_NEWS',
    e.articleText=row.articleText,
    e.date=CASE WHEN row.date<>'' THEN date(row.date) ELSE NULL END,
    e.season=row.season,
    e.visitMonth=CASE WHEN row.visitMonth<>'' THEN row.visitMonth ELSE NULL END,
    e.timeSlot=row.timeSlot, e.weather=row.weather, e.crowdLevel=row.crowdLevel,
    e.hazardType=row.hazardType, e.victimType=row.victimType,
    e.severity=row.severity, e.accessibility=row.accessibility,
    // 위치 — 관광지/도로/주소 3계층. 어디에 걸리든 좌표는 보존됩니다.
    e.locationType=row.locationType,          // PLACE / ROAD / ADDRESS / UNRESOLVED
    e.locationText=row.locationText,
    e.latitude =CASE WHEN row.latitude <>'' THEN toFloat(row.latitude)  ELSE NULL END,
    e.longitude=CASE WHEN row.longitude<>'' THEN toFloat(row.longitude) ELSE NULL END,
    e.location =CASE WHEN row.latitude<>'' AND row.longitude<>''
      THEN point({latitude:toFloat(row.latitude),longitude:toFloat(row.longitude)}) ELSE NULL END,
    // 기상 관측값 — 기사에 수치가 명시된 건만 보유 (폭염 19 / 강풍 44 / 호우 17)
    e.tempMax   =CASE WHEN row.tempMax   <>'' THEN toFloat(row.tempMax)   ELSE NULL END,
    e.tempMin   =CASE WHEN row.tempMin   <>'' THEN toFloat(row.tempMin)   ELSE NULL END,
    e.windSpeed =CASE WHEN row.windSpeed <>'' THEN toFloat(row.windSpeed) ELSE NULL END,
    e.rainfall  =CASE WHEN row.rainfall  <>'' THEN toFloat(row.rainfall)  ELSE NULL END,
    e.airTemp   =CASE WHEN row.airTemp   <>'' THEN toFloat(row.airTemp)   ELSE NULL END,
    e.humidity  =CASE WHEN row.humidity  <>'' THEN toFloat(row.humidity)  ELSE NULL END,
    e.newsPlaceCode=row.newsPlaceCode, e.matchType=row.matchType,
    e.sourceDetail=row.sourceDetail;

// ① 기사 추출 기상 키워드 어휘 (ENV_001~038) — 사고 기록의 날씨 표현 정규화용
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_environment.csv' AS row
MERGE (v:Environment {envId: row.envId}) SET v.type=row.type, v.name=row.name;

// ② 임계값 판단 축 (ENV_WIND_SPEED 계열) — RiskPattern 발동 조건의 관측 변수
//    ⚠ 이 노드가 없으면 rels_environment_risk 의 MATCH 가 조용히 실패해
//       TRIGGERS 관계가 0건 생성됩니다. 반드시 함께 적재하십시오.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_environment_axis.csv' AS row
MERGE (v:EnvironmentAxis {envId: row.envId})
SET v.type=row.type, v.name=row.name, v.unit=row.unit, v.source=row.source;

// ③ 임계축 → 위험패턴 발동 규칙은 STAGE 4(관계)로 이동했습니다.
//    RiskPattern 노드가 먼저 적재되어야 MATCH 가 성립합니다.

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_visitor_profile.csv' AS row
MERGE (v:VisitorProfile {profile_id: row.profileId}) SET v.name=row.name, v.kind='accident_victim';

// ─────────────────────────────────────────────
// STAGE 2. RiskPattern 카탈로그 노드 (zip: jeju_rule_catalog)
//   RiskPattern / Activity(v3) / SafetyAdvisory / AdvisoryMessage
// ─────────────────────────────────────────────
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_riskpattern.csv' AS row
MERGE (r:RiskPattern {risk_id: row.risk_id})
SET r.name=row.risk_name, r.nameEn=row.risk_name_en, r.riskType=row.risk_type,
    r.conditionExpr=row.condition_expr, r.thresholdMin=row.threshold_min,
    r.thresholdMax=row.threshold_max, r.thresholdUnit=row.threshold_unit,
    r.riskLevel=row.risk_level, r.targetScope=row.target_scope, r.evidenceSource=row.evidence_source;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_activity_v3.csv' AS row
MERGE (a:Activity {activity_id: row.activity_id})
SET a.nameEn=row.activity_name_en, a.nameKr=row.activity_name_kr;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_safety_advisory.csv' AS row
MERGE (s:SafetyAdvisory {advisory_id: row.advisory_id})
SET s.name=row.advisory_name, s.issueMonths=row.issue_months, s.season=row.season,
    s.targetActivity=row.target_activity, s.targetRegion=row.target_region,
    s.riskPattern=row.risk_pattern, s.verification=row.verification;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_advisory_warning_message.csv' AS row
MERGE (m:AdvisoryMessage {message_id: row.message_id})
SET m.level=row.message_level, m.tone=row.message_tone,
    m.template=row.message_template, m.requiredItems=row.required_items, m.targetUser=row.target_user;

// ─────────────────────────────────────────────
// STAGE 3. 브리지 노드 (zip: bridge)  ★판단 경로 완성용 신규
//   RecommendationAction / VisitorProfile(판단축) / RegionSafetyStat
// ─────────────────────────────────────────────
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_recommendation_action.csv' AS row
MERGE (a:RecommendationAction {action_id: row.action_id})
SET a.type=row.action_type, a.nameKr=row.action_kr, a.decisionLevel=row.decision_level;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_visitor_profile_v3.csv' AS row
MERGE (v:VisitorProfile {profile_id: row.profile_id})
SET v.type=row.profile_type, v.nameKr=row.profile_kr, v.kind='recommendation_target';

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_region_safety_stat.csv' AS row
MERGE (g:RegionSafetyStat {region_id: row.region_id})
SET g.sigungu=row.sigungu, g.emd=row.emd, g.total=toInteger(row.regionAccidentTotal),
    g.riskScore=toFloat(row.regionRiskScore);

// 소방 경내확정 AccidentEvent (source='fire')
// 소방 119 구급활동 기록 (2020-2023, 2025 / 2024년은 주소 미확보로 제외)
//  locationPrecision: POINT = 좌표 보유(2020-2021) / EMD = 읍면동만(2022-2023,2025)
//  질병(내과) 건과 세부유형 공란 건은 집계에서 제외된 상태입니다.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_accident_event_fire.csv' AS row
MERGE (e:AccidentEvent {accidentId: row.accidentId})
SET e.source='fire_119', e.attribution='FIRE_119_RECORD',
    // 기상 관측값 (2020-2021 POINT 계층만 보유, 그 외는 NULL)
    e.airTemp   =CASE WHEN row.airTemp   <>'' THEN toFloat(row.airTemp)   ELSE NULL END,
    e.windSpeed =CASE WHEN row.windSpeed <>'' THEN toFloat(row.windSpeed) ELSE NULL END,
    e.rainfall  =CASE WHEN row.rainfall  <>'' THEN toFloat(row.rainfall)  ELSE NULL END,
    e.humidity  =CASE WHEN row.humidity  <>'' THEN toFloat(row.humidity)  ELSE NULL END,
    e.windDir   =CASE WHEN row.windDir   <>'' THEN toFloat(row.windDir)   ELSE NULL END,
    e.snowfall  =CASE WHEN row.snowfall  <>'' THEN toFloat(row.snowfall)  ELSE NULL END,
    e.date=row.date, e.year=toInteger(row.year),
    e.accidentType=row.accidentTypeKr, e.occurType=row.occurType,
    e.placeTypeRaw=row.placeTypeRaw, e.sigungu=row.sigungu, e.emd=row.emd,
    e.locationPrecision=row.locationPrecision,
    e.latitude =CASE WHEN row.latitude <>'' THEN toFloat(row.latitude)  ELSE NULL END,
    e.longitude=CASE WHEN row.longitude<>'' THEN toFloat(row.longitude) ELSE NULL END,
    e.location =CASE WHEN row.latitude<>'' AND row.longitude<>''
      THEN point({latitude:toFloat(row.latitude),longitude:toFloat(row.longitude)}) ELSE NULL END;

// 정밀도별 보조 라벨 — 질의 시 계층 구분용
MATCH (e:AccidentEvent) WHERE e.locationPrecision='POINT' SET e:PointAccident;
MATCH (e:AccidentEvent) WHERE e.locationPrecision='EMD'   SET e:RegionAccident;

// ─────────────────────────────────────────────
// STAGE 4. 관계 — KG 내부
// ─────────────────────────────────────────────

// 읍면동 단위 사고 → 지역 (좌표가 없어 장소에 직접 연결할 수 없는 건)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_firevent_OCCURRED_IN_region.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}), (g:RegionSafetyStat {region_id:row.region_id})
MERGE (e)-[:OCCURRED_IN_REGION]->(g);
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_place_HAS_ACCESSIBILITY.csv' AS row
MATCH (p:Place {placeId:row.placeId}),(ac:Accessibility {accessibilityId:row.accessibilityId})
MERGE (p)-[:HAS_ACCESSIBILITY]->(ac);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_place_HAS_ACTIVITY_activity.csv' AS row
MATCH (p:Place {placeId:row.placeId}),(a:TourActivity {activityId:row.activityId})
MERGE (p)-[:HAS_TOUR_ACTIVITY]->(a);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_OCCURRED_AT_place.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}),(p:Place {placeId:row.placeId})
MERGE (e)-[:OCCURRED_AT]->(p);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_HAPPENED_UNDER_env.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}),(v:Environment {envId:row.envId})
MERGE (e)-[:HAPPENED_UNDER]->(v);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_INVOLVED_PROFILE.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}),(v:VisitorProfile {profile_id:row.profileId})
MERGE (e)-[:INVOLVED_PROFILE]->(v);

// ─────────────────────────────────────────────
// STAGE 5. 관계 — 위험 판단 축 (핵심 경로)
// ─────────────────────────────────────────────
// 사고 → 위험패턴 (뉴스)
// ③ 임계축 → 위험패턴 발동 규칙 (condition_expr 에 임계식 보관)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rels_environment_risk.csv' AS row
MATCH (e:EnvironmentAxis {envId: row.from_id}), (r:RiskPattern {risk_id: row.to_id})
MERGE (e)-[t:TRIGGERS]->(r)
SET t.conditionExpr = row.condition_expr;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_EVIDENCES_riskpattern.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}),(r:RiskPattern {risk_id:row.risk_id})
MERGE (e)-[rel:EVIDENCES]->(r) SET rel.attribution=coalesce(row.attribution,'PLACE_CONFIRMED_NEWS');

// 사고 → 위험패턴 (소방 경내확정)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_firevent_EVIDENCES_riskpattern.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}),(r:RiskPattern {risk_id:row.risk_id})
MERGE (e)-[rel:EVIDENCES]->(r) SET rel.attribution='PLACE_CONFIRMED_FIRE';

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_firevent_OCCURRED_AT_place.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}),(p:Place {placeId:row.placeId})
MERGE (e)-[:OCCURRED_AT]->(p);

// 활동 → 위험패턴
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_activity_CARRIES_riskpattern.csv' AS row
MATCH (a:Activity {activity_id:row.activity_id}),(r:RiskPattern {risk_id:row.risk_id})
MERGE (a)-[:CARRIES]->(r);

// 주의보 → 위험패턴 / 활동 / 메시지
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_advisory_BASED_ON_riskpattern.csv' AS row
MATCH (s:SafetyAdvisory {advisory_id:row.advisory_id}),(r:RiskPattern {risk_id:row.risk_id})
MERGE (s)-[:BASED_ON]->(r);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_advisory_TARGETS_activity.csv' AS row
MATCH (s:SafetyAdvisory {advisory_id:row.advisory_id}), (a:Activity {activity_id:row.activity_id})
MERGE (s)-[:TARGETS]->(a);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_advisory_RECOMMENDS_message.csv' AS row
MATCH (s:SafetyAdvisory {advisory_id:row.advisory_id}),(m:AdvisoryMessage {message_id:row.message_id})
MERGE (s)-[:RECOMMENDS]->(m);

// ─────────────────────────────────────────────
// STAGE 6. 관계 — 브리지 (★판단 경로 완성)
// ─────────────────────────────────────────────
// 위험패턴 → 행동안내  (RESULTS_IN)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_risk_RESULTS_IN_action.csv' AS row
MATCH (r:RiskPattern {risk_id:row.risk_id}),(a:RecommendationAction {action_id:row.action_id})
MERGE (r)-[rel:RESULTS_IN]->(a) SET rel.decisionLevel=row.decision_level;

// 위험패턴 → 관광지  (APPLIES_TO, scope 전개 실엣지)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_risk_APPLIES_TO_place.csv' AS row
MATCH (r:RiskPattern {risk_id:row.risk_id}),(p:Place {placeId:row.placeId})
MERGE (r)-[:APPLIES_TO]->(p);

// 관광객 → 위험패턴  (SENSITIVE_TO, 취약성)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_profile_SENSITIVE_TO_risk.csv' AS row
MATCH (v:VisitorProfile {profile_id:row.profile_id}),(r:RiskPattern {risk_id:row.risk_id})
MERGE (v)-[:SENSITIVE_TO]->(r);

// KG주활동 → v3활동  (MAPS_TO, 두 체계 연결)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_activity_MAPS_TO_v3.csv' AS row
MATCH (k:TourActivity {activityId:row.kg_activity_id}),(a:Activity {activity_id:row.v3_activity_id})
MERGE (k)-[:MAPS_TO]->(a);

// 관광지 → 지역통계  (LOCATED_IN)
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_place_LOCATED_IN_region.csv' AS row
MATCH (p:Place {placeId:row.placeId}),(g:RegionSafetyStat {region_id:row.region_id})
MERGE (p)-[:LOCATED_IN]->(g);

// ─────────────────────────────────────────────
// STAGE 7. 위험 속성 — 직접/주변 2계층 분리
//
//  ① directRiskScore : 해당 관광지에서 실제 발생한 사고 (뉴스, 장소 확정)
//     → 소프트랭킹 Risk(p) 항에 사용. 근거가 확실한 감점.
//
//  ② ambientRiskLevel : 인근에서 잦았던 사고 (소방 119, 정확한 지점 미상)
//     → 랭킹에 반영하지 않음. "주변에 이런 사고가 잦으니 주의" 경고 문구용.
//     → 1km 계열과 읍면동 계열은 면적이 달라 수치 비교가 불가하므로,
//        각 계열 내부에서만 3분위로 LOW/MEDIUM/HIGH 구간화했습니다.
// ─────────────────────────────────────────────
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/place_risk_score.csv' AS row
MATCH (p:Place {placeId:row.placeId})
SET // ① 직접 위험 (랭킹용)
    p.directAccidentCount=toInteger(row.directAccidentCount),
    p.directAccidentTypes=row.directAccidentTypes,
    p.directRiskScore=toFloat(row.directRiskScore),
    p.directEvidence=row.directEvidence,          // NEWS_CONFIRMED / NONE
    // ② 주변 위험 (경고용 — 랭킹 금지)
    p.ambientRiskLevel=row.ambientRiskLevel,      // LOW / MEDIUM / HIGH
    p.ambientBasis=row.ambientBasis,              // NEARBY_1KM / REGION / NO_DATA
    p.ambientAnnualAvg=CASE WHEN row.ambientAnnualAvg<>'' THEN toFloat(row.ambientAnnualAvg) ELSE NULL END,
    p.ambientPeriod=row.ambientPeriod,
    p.ambientScope=row.ambientScope,
    p.ambientNote=row.ambientNote;

// ⚠ 구 riskScore 는 폐지되었습니다.
//   랭킹에는 directRiskScore 를, 경고 문구에는 ambientRiskLevel 을 쓰십시오.
//   ambientRiskLevel 을 점수로 환산해 랭킹에 넣으면 면적 차이 때문에
//   넓은 읍면동에 속한 한적한 관광지가 부당하게 감점됩니다.

// ═══════════════════════════════════════════════════════════
// STAGE 8. 안전 안내 (SafetyAdvisory) — 뉴스 중대사고 근거
//
//  원칙: 사용자에게는 "사망 N건" 같은 수치를 노출하지 않습니다.
//        공포를 조성하지 않고 행동 지침만 전달합니다.
//        근거 수치(_fatalCount 등)는 내부 판단용으로만 보관합니다.
// ═══════════════════════════════════════════════════════════
// ⚠ 라벨 분리: 소방 계절 주의보(:SafetyAdvisory, advisory_id=SA_xx)와
//    장소별 사고이력 안내(:PlaceAdvisory, advisory_id=ADV_Pxxx)는 성격이 다릅니다.
//    같은 라벨을 쓰면 advisory_id 유니크 제약과 충돌합니다.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/place_safety_advisory.csv' AS row
MERGE (a:PlaceAdvisory {advisory_id:'ADV_'+row.placeId})
SET a.advisoryLevel   = row.advisoryLevel,      // ATTENTION / CAUTION / NOTICE
    a.advisoryMessage = row.advisoryMessage,    // ← 사용자 노출 문구
    a.placeContext    = row.placeContext,       // HARBOR/BEACH/COAST/...
    a.peakSeason      = row.peakSeason,
    a.peakTime        = row.peakTime,
    a.seasonShare     = toFloat(row.seasonShare),
    a.timeShare       = toFloat(row.timeShare),
    a.evidenceSource  = 'NEWS_REPORT',
    a.evidencePeriod  = row._evidencePeriod,
    // 내부 근거 — 응답에 직접 노출 금지
    a.internalSevereCount = toInteger(row._severeCount),
    a.internalFatalCount  = toInteger(row._fatalCount);

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/place_safety_advisory.csv' AS row
MATCH (p:Place {placeId:row.placeId}), (a:PlaceAdvisory {advisory_id:'ADV_'+row.placeId})
MERGE (p)-[:HAS_ADVISORY]->(a);

// ─────────────────────────────────────────────
// 조건부 노출 예시 — 계절/시간이 맞을 때만 안내
//   $month(1~12), $timeSlot('오전'/'오후'/'야간')
// ─────────────────────────────────────────────
// MATCH (p:Place)-[:HAS_ADVISORY]->(a:PlaceAdvisory)
// WHERE p.placeId=$placeId
//   AND (a.peakSeason='' OR a.peakSeason = CASE
//         WHEN $month IN [3,4,5] THEN '봄'   WHEN $month IN [6,7,8]  THEN '여름'
//         WHEN $month IN [9,10,11] THEN '가을' ELSE '겨울' END)
//   AND (a.peakTime='' OR a.peakTime=$timeSlot)
// RETURN a.advisoryMessage;

// 검증 — 안내 문구에 수치 표현이 섞이지 않았는지
MATCH (a:SafetyAdvisory)
WHERE coalesce(a.advisoryMessage,'') =~ '.*(사망|숨진|사상자|[0-9]+명).*'
RETURN a.advisory_id, a.advisoryMessage;
// 기대: 0건

// ═══════════════════════════════════════════════════════════
// STAGE 9. 항·포구 물놀이 제한 (어촌·어항법)
//
//  배경: SNS 확산으로 포구 다이빙이 늘며 안전사고가 급증하자,
//        어촌·어항법 개정으로 어항구역 내 물놀이·다이빙·취사·야영이 금지됨.
//        위반 시 50만원 이하 과태료.
//
//  ⚠ 시행일 2027-04-22 — 현재는 시행 전(계도 단계)입니다.
//     "금지되어 있습니다"가 아니라 "○○부터 금지됩니다"로 안내해야 합니다.
//
//  ⚠ 대상은 '어항구역으로 공식 지정된 곳'에 한합니다. 모든 포구가 아닙니다.
//     제주 법정 지정어항은 70곳(국가 5·지방 19·어촌정주 46)이며,
//     그중 KG 관광지와 확정 매칭된 23곳에만 금지 안내를 적용합니다.
//     NOT_DESIGNATED 24곳은 비법정 소규모 항·포구일 수 있어 금지로 단정하지 않습니다.
//     ※ 제주도는 어항 기능을 상실한 포구의 구역 제외를 검토 중이므로 재확인이 필요합니다.

// 지정어항 원장 (70곳) — 참조·검증용
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/jeju_designated_harbor.csv' AS row
MERGE (h:DesignatedHarbor {harborName: row.harborName, harborType: row.harborType})
SET h.address=row.address, h.validity=row.validity,
    h.matchConfidence=row.harborConfidence, h.reviewFlag=row.reviewFlag;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/jeju_designated_harbor.csv' AS row
WITH row WHERE row.placeId <> ''
MATCH (p:Place {placeId:row.placeId}),
      (h:DesignatedHarbor {harborName:row.harborName, harborType:row.harborType})
MERGE (p)-[:IS_DESIGNATED_HARBOR]->(h);
// ═══════════════════════════════════════════════════════════
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/place_swimming_restriction.csv' AS row
MATCH (p:Place {placeId:row.placeId})
SET p.swimmingRestriction     = row.swimmingRestriction,   // PROHIBITED_FROM_2027 / NOT_DESIGNATED
    p.harborName              = row.harborName,
    p.harborType              = row.harborType,              // 국가어항/지방어항/어촌정주어항
    p.restrictionLegalBasis   = row.legalBasis,
    p.restrictionPenalty      = row.penalty,
    p.restrictionEffectiveDate= CASE WHEN row.effectiveDate<>'' THEN date(row.effectiveDate) ELSE NULL END,
    p.restrictionCurrentStatus= row.currentStatus,
    p.designationConfidence   = row.designationConfidence,  // CONFIRMED / PENDING
    p.restrictionNote         = row.note,
    p.restrictionSourceUrl    = row.source;

MATCH (p:Place) WHERE p.swimmingRestriction IS NOT NULL SET p:WaterRestrictedPlace;

// ─────────────────────────────────────────────
// 물놀이 활동 추천 시 하드 필터
//   어항구역 확정분은 물놀이·다이빙 목적 추천에서 제외합니다.
// ─────────────────────────────────────────────
// MATCH (p:Place)-[:HAS_TOUR_ACTIVITY]->(a:TourActivity)
// WHERE a.name IN ['해수욕','물놀이','해양체험','해양레저','스쿠버다이빙','수상레저체험']
//   AND NOT (p.swimmingRestriction='PROHIBITED_FROM_2027'
//            AND p.designationConfidence='CONFIRMED')
// RETURN p;

// 검증 1 — 제한 대상 분포
MATCH (p:WaterRestrictedPlace)
RETURN p.swimmingRestriction AS 상태, p.designationConfidence AS 확정도, count(*) AS 건수;
// 기대: PROHIBITED_FROM_2027/CONFIRMED 23 · NOT_DESIGNATED/NOT_LISTED 24 (합 47)

// 검증 2 — 시행 전인데 '금지되어 있습니다'로 단정한 문구가 없는지
MATCH (p:Place)-[:HAS_ADVISORY]->(a:PlaceAdvisory)
WHERE coalesce(a.advisoryMessage,'') CONTAINS '금지되어 있습니다'
   OR coalesce(a.advisoryMessage,'') CONTAINS '금지됩니다.'
RETURN p.placeId, a.advisoryMessage;
// 기대: 0건 (시행일 명시 형태만 허용)

// ═══════════════════════════════════════════════════════════
// STAGE 10. 안개 위험 (인터뷰 반영)
//
//  근거: 제주소방 인터뷰 — "제주시에서 서귀포시로 이동 시 갑작스러운 짙은 안개가
//        발생해 운전자 시야 확보가 곤란하며, 관광객은 지역 환경에 익숙하지 않아
//        위험이 증가한다". 렌터카 의존도가 높은 제주 관광의 특성과 결합됨.
//
//  RP_FOG_01 시정 200~1000m  — 시야 주의
//  RP_FOG_02 시정 100~200m   — 운전 주의 (렌터카 프로필 연계)
//  RP_FOG_03 시정 100m 미만  — 이동 자제
// ═══════════════════════════════════════════════════════════

// 안개 위험 적용 근거 — 뉴스 확인분과 대표 다발지역 구분
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/place_fog_risk_basis.csv' AS row
MATCH (p:Place {placeId:row.placeId})
SET p.fogBasis=row.fogBasis,        // NEWS_CONFIRMED / REPRESENTATIVE
    p.fogEvidence=row.fogEvidence;

// 렌터카 이용자는 안개 위험에 특히 민감 (초행길 + 시야 불량)
MATCH (v:VisitorProfile {profile_id:'VP_RENTAL'}), (r:RiskPattern)
WHERE r.risk_id IN ['RP_FOG_02','RP_FOG_03']
MERGE (v)-[:SENSITIVE_TO]->(r);

// ─────────────────────────────────────────────
// 검증
// ─────────────────────────────────────────────
MATCH (e:EnvironmentAxis)-[t:TRIGGERS]->(r:RiskPattern)
RETURN count(*) AS 임계규칙수;
// 기대: 26건 (기존 23 + 안개 3)

MATCH (r:RiskPattern) WHERE r.risk_id STARTS WITH 'RP_FOG'
MATCH (r)-[:APPLIES_TO]->(p:Place)
RETURN r.name AS 위험, count(p) AS 적용장소;
// 기대: 각 29곳 (뉴스 확인 3 + 대표 다발지역 26)

// 산방산 계열 — 상류 강수 시 하류 범람 위험
MATCH (r:RiskPattern {risk_id:'RP_FLASHFLOOD_01'})-[:APPLIES_TO]->(p:Place)
RETURN p.placeId, p.name ORDER BY p.placeId;
// 기대: 11곳 (폭포·계곡 8 + 산방산 계열 3)
// ═══════════════════════════════════════════════════════════
// STAGE 11. RoadSegment — 도로 구간 축
//
//  배경: 교통사고는 '관광지'가 아니라 '도로'에서 발생합니다.
//        1100도로·평화로처럼 관광지 노드로 표현되지 않는 구간의 사고를
//        보존하기 위해 도로를 별도 노드로 둡니다.
//        (해안도로 26곳은 관광 목적지이므로 Place 로 유지됩니다)
// ═══════════════════════════════════════════════════════════
CREATE CONSTRAINT road_id IF NOT EXISTS FOR (r:RoadSegment) REQUIRE r.roadId IS UNIQUE;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/nodes_road_segment.csv' AS row
MERGE (r:RoadSegment {roadId: row.roadId})
SET r.name=row.roadName, r.routeNo=row.routeNo, r.section=row.section,
    r.roadType=row.roadType, r.riskNote=row.riskNote,
    r.trafficRiskLevel=row.trafficRiskLevel;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/huple2019/jeju-kg-data/refs/heads/main/rel_accident_OCCURRED_ON_road.csv' AS row
MATCH (e:AccidentEvent {accidentId:row.accidentId}), (r:RoadSegment {roadId:row.roadId})
MERGE (e)-[:OCCURRED_ON]->(r);

// 중산간 횡단 도로는 안개 위험 보유 (인터뷰: 제주시→서귀포 이동 중 급변)
MATCH (r:RoadSegment), (rp:RiskPattern)
WHERE r.roadType IN ['중산간 횡단','중산간 간선'] AND rp.risk_id STARTS WITH 'RP_FOG'
MERGE (rp)-[:APPLIES_TO_ROAD]->(r);

// ─────────────────────────────────────────────
// 검증
// ─────────────────────────────────────────────
MATCH (e:AccidentEvent)-[:OCCURRED_ON]->(r:RoadSegment)
RETURN r.name AS 도로, count(*) AS 사고수 ORDER BY 사고수 DESC;
// 기대: 평화로 6 · 1100도로 6 · 비자림로 3 등 총 19건

// 장소·도로 어디에도 연결되지 않은 사고 (주소만 있는 건)
MATCH (e:AccidentEvent) WHERE e.source='news'
  AND NOT (e)-[:OCCURRED_AT]->(:Place) AND NOT (e)-[:OCCURRED_ON]->(:RoadSegment)
RETURN e.locationType AS 유형, count(*) AS 건수;
// 기대: ADDRESS 46 · UNRESOLVED 28 — 좌표는 보유하므로 공간질의는 가능

// 기상 관측값 보유 현황
MATCH (e:AccidentEvent)
RETURN e.source AS 출처,
       count(CASE WHEN e.airTemp IS NOT NULL OR e.tempMax IS NOT NULL THEN 1 END) AS 기온,
       count(CASE WHEN e.windSpeed IS NOT NULL THEN 1 END) AS 풍속,
       count(CASE WHEN e.rainfall  IS NOT NULL THEN 1 END) AS 강수량;
// 기대: fire_119 기온 3931·풍속 3932·강수 422 / news 기온 19·풍속 44·강수 17

// 폭염 사고의 기온 분포 — 온열질환 임계 도출용
MATCH (e:AccidentEvent) WHERE e.tempMax IS NOT NULL
RETURN e.weather AS 기상, count(*) AS 건수,
       round(avg(e.tempMax),1) AS 평균최고기온, round(avg(e.tempMin),1) AS 평균최저기온;

// ════════════════════════════════════════════════════════════════
//  검증: 노드/관계 카운트
// ════════════════════════════════════════════════════════════════
// MATCH (n) RETURN labels(n)[0] AS label, count(*) ORDER BY label;
// MATCH ()-[r]->() RETURN type(r) AS rel, count(*) ORDER BY rel;


