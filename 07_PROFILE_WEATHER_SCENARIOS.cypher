// ════════════════════════════════════════════════════════════════════════
//  07_PROFILE_WEATHER_SCENARIOS.cypher
//  사람별 · 날씨별 · 상황별 시나리오 테스트         (schema v3 / FIX50 기준)
//
//  06_TEST_SCENARIOS.cypher 는 데이터 무결성 검증이 목적입니다.
//  이 파일은 "실제 이용자가 물어볼 법한 질문"이 그래프에서 답이 나오는지 봅니다.
//
//  실행법: 각 블록의 :param 을 먼저 실행한 뒤 쿼리를 실행하십시오.
//  주의:   희소 속성은 반드시 coalesce 로 감쌉니다. NULL 이 행을 조용히 탈락시킵니다.
//
//  참고 — CSV 에 없고 그래프에만 있는 속성 두 개를 씁니다.
//    ac.unknownAxisNote  00_MASTER_LOAD 174행이 UNKNOWN 축에 생성
//    p.directRiskScore   place_risk_score.csv 에서 별도 적재 (404행)
//  RiskPattern 속성명은 CSV 와 다릅니다 — risk_name→name, risk_level→riskLevel,
//  threshold_min→thresholdMin. 로더가 카멜케이스로 바꿔 넣습니다.
// ════════════════════════════════════════════════════════════════════════


// ╔══════════════════════════════════════════════════════════════════════╗
// ║  A. 사람별 (프로필 축)                                                 ║
// ╚══════════════════════════════════════════════════════════════════════╝

// ─────────────────────────────────────────────────────────────────────
// S1. 고령 부모님 모시고 — 계단 없고 쉴 곳 있는 곳
//     기대: elderlyAccess FULL 위주, disabledToilet 있는 곳 상위
//     확인점: 화장실 UNKNOWN 이 '없음'으로 안내되지 않는가
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.elderlyAccess IN ['FULL','PARTIAL']
  AND coalesce(ac.mobilityAccess,'UNKNOWN') <> 'NONE'
RETURN p.name AS 관광지,
       ac.elderlyAccess AS 고령접근,
       CASE coalesce(ac.disabledToilet,'UNKNOWN')
            WHEN 'UNKNOWN' THEN '미확인 — 방문 전 문의'
            WHEN 'NONE'    THEN '없음'
            ELSE '있음' END AS 장애인화장실,
       coalesce(ac.slopeInfo,'정보 없음') AS 경사,
       coalesce(p.directRiskScore,0.0) AS 위험도
ORDER BY 위험도 ASC, 고령접근 DESC, 관광지
LIMIT 20;


// ─────────────────────────────────────────────────────────────────────
// S2. 고령 + 여름 — 폭염에 취약한 프로필이 피해야 할 곳
//     VP_OLDER 는 RP_HEAT_02·RP_SLIP_TERRAIN·RP_MOUNTAIN_01·RP_FALL_CLIFF 에 민감
//     기대: 실외 + 해당 위험패턴이 걸린 곳
// ─────────────────────────────────────────────────────────────────────
MATCH (vp:VisitorProfile {profile_id:'VP_OLDER'})-[:SENSITIVE_TO]->(r:RiskPattern)
MATCH (r)-[:APPLIES_TO]->(p:Place)
WHERE p.indoorOutdoor STARTS WITH '실외'
OPTIONAL MATCH (p)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN p.name AS 관광지,
       collect(DISTINCT r.name) AS 해당위험,
       p.indoorOutdoor AS 실내외,
       coalesce(ac.elderlyAccess,'UNKNOWN') AS 고령접근
ORDER BY size(해당위험) DESC, 관광지
LIMIT 20;


// ─────────────────────────────────────────────────────────────────────
// S3. 유아 동반 (유모차) — 휠체어와 제약이 어떻게 다른가
//     확인점: strollerAccess 와 wheelchairAccess 가 갈리는 지점이 보이는가
//     예) 미로공원처럼 둘 다 불가 / 계단은 유모차는 들고 넘을 수 있는 곳
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.strollerAccess,'UNKNOWN') <> coalesce(ac.wheelchairAccess,'UNKNOWN')
  AND ac.strollerAccess IN ['FULL','PARTIAL','NONE']
  AND ac.wheelchairAccess IN ['FULL','PARTIAL','NONE']
RETURN p.name AS 관광지,
       ac.strollerAccess AS 유모차,
       ac.wheelchairAccess AS 휠체어,
       coalesce(ac.routeCondition,'-') AS 경로상태
ORDER BY 관광지
LIMIT 25;


// ─────────────────────────────────────────────────────────────────────
// S4. 휠체어 이용 — 올레 무장애 구간 (공식 10개 + 가파도 순환)
//     기대: 11행. 구간명·거리·난이도가 모두 채워져 있어야 함
//     확인점: 구간 정보 없이 "접근 가능"만 나오는 곳이 없는가
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.wheelchairSection,'') <> ''
RETURN p.name AS 코스,
       CASE WHEN ac.wheelchairSection STARTS WITH '전 구간' THEN '전구간' ELSE '구간한정' END AS 유형,
       ac.wheelchairSection AS 구간,
       coalesce(ac.wheelchairSectionDist,'(거리 미표기)') AS 거리,
       ac.wheelchairDifficulty AS 휠체어난이도,
       CASE WHEN coalesce(ac.mobilityCaveat,'') CONTAINS '시작점은' THEN 'OK' ELSE '★시작점 누락★' END AS 시작점안내
ORDER BY 유형, 코스;


// ─────────────────────────────────────────────────────────────────────
// S5. 시각장애 — 점자 안내판이 있는 곳
//     기대: recommendForVisual='Y' 인 곳. 미확인은 '불가'로 안내하면 안 됨
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.recommendForVisual,'UNKNOWN') = 'Y'
RETURN p.name AS 관광지,
       ac.visualAccess AS 시각접근,
       coalesce(ac.sensoryAccessNote,'-') AS 안내
ORDER BY 관광지;


// ─────────────────────────────────────────────────────────────────────
// S6. 발달장애 — 확보된 곳이 9개뿐. 나머지는 '미조사'로 안내되는가
//     확인점: UNKNOWN 을 '불가'로 읽으면 안 됨
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN CASE coalesce(ac.cognitiveAccess,'UNKNOWN')
            WHEN 'UNKNOWN' THEN '미조사 (불가 아님)'
            ELSE ac.cognitiveAccess END AS 발달축,
       count(*) AS 건수,
       collect(p.name)[..5] AS 예시
ORDER BY 건수 DESC;


// ─────────────────────────────────────────────────────────────────────
// S7. 혼행 — 길 잃음·산악 위험에 민감. 동행자 필수인 곳은 걸러야 함
// ─────────────────────────────────────────────────────────────────────
MATCH (vp:VisitorProfile {profile_id:'VP_SOLO'})-[:SENSITIVE_TO]->(r:RiskPattern)-[:APPLIES_TO]->(p:Place)
OPTIONAL MATCH (p)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WITH p, collect(DISTINCT r.name) AS 위험, ac
RETURN p.name AS 관광지, 위험,
       CASE coalesce(ac.companionRequired,'UNKNOWN')
            WHEN 'Y' THEN '★동행자 필요 — 혼행 부적합★' ELSE '단독 가능' END AS 동행판정
ORDER BY 동행판정 DESC, 관광지
LIMIT 20;


// ╔══════════════════════════════════════════════════════════════════════╗
// ║  B. 날씨별                                                            ║
// ╚══════════════════════════════════════════════════════════════════════╝

// ─────────────────────────────────────────────────────────────────────
// S8. 비 오는 날 — 실내 대안
//     기대: indoorOutdoor='실내' 이면서 접근성 확보된 곳
// ─────────────────────────────────────────────────────────────────────
:param profile => 'VP_WHEEL';

MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE p.indoorOutdoor STARTS WITH '실내'
  AND ($profile IS NULL
       OR NOT $profile IN ['VP_WHEEL','VP_MOBILITY']
       OR (ac.wheelchairAccess IN ['FULL','PARTIAL']
           AND coalesce(ac.recommendForMobility,'Y') = 'Y'))
RETURN p.name AS 관광지, p.indoorOutdoor AS 실내외,
       coalesce(ac.wheelchairAccess,'UNKNOWN') AS 휠체어,
       coalesce(ac.disabledToilet,'UNKNOWN') AS 장애인화장실,
       coalesce(ac.mobilityCaveat,'-') AS 주의
ORDER BY 관광지
LIMIT 20;


// ─────────────────────────────────────────────────────────────────────
// S9. 강풍 — 풍속별 판정이 단계적으로 갈리는가
//     RP_WIND_01 주의(7~10) / 02 위험(10~14) / 03 위험(14~)
//     wind_speed 를 7 → 11 → 15 로 바꿔가며 3회 실행하십시오.
// ─────────────────────────────────────────────────────────────────────
:param wind_speed => 11.0;

MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place)
WHERE r.risk_id STARTS WITH 'RP_WIND'
  AND toFloat(coalesce(r.thresholdMin, '0')) <= $wind_speed
  AND (r.thresholdMax IS NULL OR $wind_speed < toFloat(r.thresholdMax))
OPTIONAL MATCH (r)-[:RESULTS_IN]->(act)
RETURN $wind_speed AS 풍속, r.name AS 발동패턴, r.riskLevel AS 위험도,
       count(DISTINCT p) AS 해당관광지수,
       collect(DISTINCT act.decisionLevel)[..3] AS 권고,
       collect(DISTINCT p.name)[..5] AS 예시
ORDER BY 위험도;


// ─────────────────────────────────────────────────────────────────────
// S10. 폭염 + 고령 — 날씨와 프로필이 겹칠 때
//      확인점: 두 조건이 AND 로 좁혀지는가, 한쪽만 걸려도 나오는가
// ─────────────────────────────────────────────────────────────────────
:param apparent_temp => 34.0;

MATCH (vp:VisitorProfile {profile_id:'VP_OLDER'})-[:SENSITIVE_TO]->(r:RiskPattern)
WHERE r.risk_id STARTS WITH 'RP_HEAT'
  AND toFloat(coalesce(r.thresholdMin,'0')) <= $apparent_temp
MATCH (r)-[:APPLIES_TO]->(p:Place)
WHERE p.indoorOutdoor STARTS WITH '실외'
OPTIONAL MATCH (p)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
RETURN p.name AS 관광지, r.name AS 위험패턴, r.riskLevel AS 등급,
       coalesce(ac.elderlyAccess,'UNKNOWN') AS 고령접근,
       coalesce(ac.slopeInfo,'-') AS 경사정보
ORDER BY 등급 DESC, 관광지
LIMIT 20;


// ╔══════════════════════════════════════════════════════════════════════╗
// ║  C. 상황별                                                            ║
// ╚══════════════════════════════════════════════════════════════════════╝

// ─────────────────────────────────────────────────────────────────────
// S11. 섬에 가고 싶다 — 도달 수단이 막혀 있지 않은가
//      ★ 이 쿼리가 지금 KG 의 최대 약점을 드러냅니다.
//      우도·추자 계열은 섬 안 시설만 보고 등급이 매겨졌고
//      도항선 제약이 mobilityCaveat 에 없습니다.
//      기대: '★도달제약 미반영★' 9행 (미해결항목_위치표 A1)
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(p.isIsland,'UNKNOWN') = 'Y'
   OR p.name CONTAINS '우도' OR p.name CONTAINS '추자'
   OR p.name CONTAINS '가파도' OR p.name CONTAINS '마라도'
RETURN p.name AS 관광지,
       coalesce(p.islandName,'-') AS 섬,
       coalesce(p.ferryPort,'★결측★') AS 항구,
       coalesce(ac.wheelchairAccess,'UNKNOWN') AS 휠체어,
       coalesce(ac.recommendForMobility,'Y') AS 게이트,
       CASE WHEN coalesce(ac.mobilityCaveat,'') CONTAINS '승선'
             OR coalesce(ac.mobilityCaveat,'') CONTAINS '여객선'
            THEN '반영됨' ELSE '★도달제약 미반영★' END AS 도달안내
ORDER BY 도달안내 DESC, 관광지;


// ─────────────────────────────────────────────────────────────────────
// S12. 시설은 되는데 활동은 안 되는 곳 — 오해가 가장 잘 생기는 지점
//      예) 잠수함 매표소는 접근 가능하나 선내 계단
//      기대: facilityAccess=AVAILABLE 인데 activityAccess=UNAVAILABLE
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.facilityAccess = 'AVAILABLE' AND ac.activityAccess = 'UNAVAILABLE'
RETURN p.name AS 관광지,
       coalesce(ac.accessVerdictReason,'-') AS 판정근거,
       coalesce(ac.recommendForMobility,'Y') AS 게이트
ORDER BY 관광지;


// ─────────────────────────────────────────────────────────────────────
// S13. 복합시설 — 체험별로 조건이 다른 곳
//      v3 는 Place 단위 판정이라 체험별 구분이 텍스트로만 들어 있습니다.
//      확인점: caveat 에 체험 이름이 실제로 등장하는가
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.mobilityCaveat,'') CONTAINS '체험별'
   OR coalesce(ac.accessVerdictReason,'') CONTAINS '복합'
RETURN p.name AS 관광지, ac.activityAccess AS 활동참여,
       coalesce(ac.recommendForMobility,'Y') AS 게이트,
       ac.mobilityCaveat AS 안내문구;


// ─────────────────────────────────────────────────────────────────────
// S14. 동행자가 꼭 필요한 곳 — 혼자 가면 안 되는 곳
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.companionRequired,'UNKNOWN') = 'Y'
RETURN p.name AS 관광지,
       coalesce(ac.assistLevel,'-') AS 도움수준,
       coalesce(ac.mobilityCaveat,'-') AS 안내
ORDER BY 관광지;


// ─────────────────────────────────────────────────────────────────────
// S15. 미조사(UNKNOWN)를 '불가'로 안내하고 있지 않은가
//      ★ 안전 문구 원칙 점검. UNKNOWN 은 "확인처 안내"가 나가야 합니다.
//      기대: 확인 안내가 있는 곳 위주. 없으면 서비스에서 침묵하게 됩니다.
// ─────────────────────────────────────────────────────────────────────
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.mobilityAccess,'UNKNOWN') = 'UNKNOWN'
RETURN CASE WHEN coalesce(ac.unknownAxisNote, ac.sensoryAccessNote, '') <> ''
            THEN '확인처 안내 있음' ELSE '★안내 없음★' END AS 상태,
       count(*) AS 건수,
       collect(p.name)[..8] AS 예시
ORDER BY 건수 DESC;


// ╔══════════════════════════════════════════════════════════════════════╗
// ║  D. 종합 요약 — 한 번에 훑기                                           ║
// ╚══════════════════════════════════════════════════════════════════════╝

CALL () { MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
          WHERE ac.elderlyAccess IN ['FULL','PARTIAL']
          RETURN 'S1  고령 이용 가능' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
          WHERE coalesce(ac.strollerAccess,'') <> coalesce(ac.wheelchairAccess,'')
            AND ac.strollerAccess IN ['FULL','PARTIAL','NONE']
            AND ac.wheelchairAccess IN ['FULL','PARTIAL','NONE']
          RETURN 'S3  유모차≠휠체어' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility) WHERE coalesce(ac.wheelchairSection,'')<>''
          RETURN 'S4  무장애 구간 (기대 11)' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility) WHERE coalesce(ac.recommendForVisual,'')='Y'
          RETURN 'S5  시각축 확보' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (p:Place) WHERE p.indoorOutdoor STARTS WITH '실내'
          RETURN 'S8  실내 대안' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
          WHERE (coalesce(p.isIsland,'')='Y' OR p.name CONTAINS '우도' OR p.name CONTAINS '추자')
            AND NOT (coalesce(ac.mobilityCaveat,'') CONTAINS '승선'
                  OR coalesce(ac.mobilityCaveat,'') CONTAINS '여객선')
            AND ac.wheelchairAccess IN ['FULL','PARTIAL']
          RETURN 'S11 ★도달제약 미반영★' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility)
          WHERE ac.facilityAccess='AVAILABLE' AND ac.activityAccess='UNAVAILABLE'
          RETURN 'S12 시설≠활동' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility) WHERE coalesce(ac.companionRequired,'')='Y'
          RETURN 'S14 동행 필수' AS 시나리오, count(*) AS 건수 }
RETURN 시나리오, 건수;
