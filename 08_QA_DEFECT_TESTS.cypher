// ════════════════════════════════════════════════════════════════════════
//  08_QA_DEFECT_TESTS.cypher      오류 잡기용 20종      (schema v3 / FIX56)
//
//  07 번이 "답이 나오는가" 를 본다면, 이 파일은 "틀린 답이 나오지 않는가" 를 봅니다.
//  각 테스트에 기대값을 적어 두었습니다. 대부분 0행이 정상입니다.
//
//  주의: 희소 속성은 반드시 coalesce 로 감쌉니다.
//        RiskPattern 속성명은 CSV 와 다릅니다 — risk_name→name, threshold_min→thresholdMin
//        Region 노드 라벨은 RegionSafetyStat 입니다.
//
//  ★ 속성명 규칙 — 로더가 CSV 컬럼을 카멜케이스로 바꿔 넣습니다.
//    MERGE 키만 스네이크케이스 그대로입니다: risk_id · message_id · region_id · advisory_id
//    나머지는 전부 바뀝니다:
//      condition_expr → conditionExpr    risk_name → name        risk_level → riskLevel
//      threshold_min  → thresholdMin     target_scope → targetScope
//      target_user    → targetUser       message_template → template
//      distance_m     → distanceM (관계 속성)
//    CSV 컬럼명을 그대로 쓰면 오류 없이 조용히 빈 결과가 나옵니다.
// ════════════════════════════════════════════════════════════════════════

// ══ A. 무장애 — 축 간 모순 ══

// Q1. 휠체어는 FULL 인데 유모차는 NONE  (기대 0행)
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.wheelchairAccess = 'FULL' AND coalesce(ac.strollerAccess,'UNKNOWN') = 'NONE'
RETURN '★모순★' AS 결함, p.placeId AS 코드, p.name AS 장소, coalesce(ac.routeCondition,'-') AS 경로;

// Q2. 안내문구는 불가인데 등급은 FULL  (기대 0행)
//     '대여 불가'·'일부 진입 불가' 같은 부분 제약은 제외했습니다. 그건 상세 안내입니다.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.wheelchairAccess = 'FULL'
  AND (coalesce(ac.mobilityCaveat,'') CONTAINS '휠체어로 이용하실 수 없'
    OR coalesce(ac.mobilityCaveat,'') CONTAINS '통행이 불가')
RETURN '★문구-값 불일치★' AS 결함, p.placeId AS 코드, p.name AS 장소, left(ac.mobilityCaveat,70) AS 안내;

// Q3. 활동 불가인데 추천 게이트가 Y  (기대 0행)
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.activityAccess = 'UNAVAILABLE' AND coalesce(ac.recommendForMobility,'Y') = 'Y'
RETURN '★불가인데 추천★' AS 결함, p.placeId AS 코드, p.name AS 장소, coalesce(ac.partialReason,'-') AS 근거;

// Q4. 구간 한정인데 거리·안내가 결측  (기대 0행)
//     '전 구간' 으로 시작하는 값은 안내 문구가 달라 예외 처리했습니다.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.wheelchairSection,'') <> ''
  AND (coalesce(ac.wheelchairSectionDist,'') = ''
    OR (NOT ac.wheelchairSection STARTS WITH '전 구간'
        AND NOT coalesce(ac.mobilityCaveat,'') CONTAINS ac.wheelchairSection))
RETURN '★구간 안내 결측★' AS 결함, p.name AS 코스, ac.wheelchairSection AS 구간,
       coalesce(ac.wheelchairSectionDist,'(없음)') AS 거리;

// Q5. 미조사(UNKNOWN)를 불가로 안내  (기대 0행)
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.mobilityAccess,'UNKNOWN') = 'UNKNOWN'
  AND coalesce(ac.mobilityCaveat,'') CONTAINS '이용하실 수 없'
RETURN '★미조사를 불가로★' AS 결함, p.placeId AS 코드, p.name AS 장소;


// ══ B. 날씨 — 임계값·연결 결함 ══

// Q6. 임계값 구간 연속성 — 앞 구간 max 와 뒤 구간 min 이 같아야 합니다
MATCH (r:RiskPattern) WHERE r.thresholdMin IS NOT NULL
WITH split(r.risk_id,'_')[1] AS 계열, r ORDER BY 계열, toFloat(r.thresholdMin)
WITH 계열, collect({id:r.risk_id, min:toFloat(r.thresholdMin),
     max:CASE WHEN r.thresholdMax IS NULL THEN 9999.0 ELSE toFloat(r.thresholdMax) END,
     lv:r.riskLevel}) AS xs
WHERE size(xs) > 1
RETURN 계열, xs AS 구간;

// Q7. 어떤 장소·도로에도 연결 안 된 위험패턴  (기대 0행)
//     target_scope 가 '[장소 무관]' 으로 시작하는 4개는 설계상 연결하지 않습니다.
//       RP_MACHINE_01 · RP_FALL_01  도민 생활안전(벌초·감귤 수확) — 관광객 대상 아님
//       RP_FIRE_01                  시설 관리자 안전수칙
//       RP_OUTDOOR_01               대상이 도 전역 — 7~9월 시기 배너로 운영
//     이 4개를 장소에 붙이면 변별력이 사라지므로 예외 처리합니다.
MATCH (r:RiskPattern)
WHERE NOT (r)-[:APPLIES_TO]->(:Place)
  AND NOT (r)-[:APPLIES_TO_ROAD]->(:RoadSegment)
  AND NOT coalesce(r.targetScope,'') STARTS WITH '[장소 무관]'
RETURN '★연결 없는 패턴★' AS 결함, r.risk_id AS 코드, r.name AS 패턴,
       r.riskLevel AS 등급, r.targetScope AS 대상 ORDER BY 코드;

// Q7-B. 장소 무관 패턴 목록 — 4행. 설계상 정상이며 시기·활동 조건으로만 발동합니다.
MATCH (r:RiskPattern) WHERE coalesce(r.targetScope,'') STARTS WITH '[장소 무관]'
RETURN r.risk_id AS 코드, r.name AS 패턴, r.conditionExpr AS 조건, r.targetScope AS 대상
ORDER BY 코드;

// Q8. 안개 근거는 있는데 RP_FOG 패턴이 연결 안 된 곳  (기대 0행)
//     FIX58~59 에서 RP_FOG 3단계를 정의하고 관광지 29곳·도로 4개에 연결했습니다.
MATCH (p:Place) WHERE p.fogBasis IS NOT NULL
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(p) WHERE r.risk_id STARTS WITH 'RP_FOG'
WITH p, count(r) AS n WHERE n = 0
RETURN '★안개 패턴 없음★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       p.fogBasis AS 근거유형, p.fogEvidence AS 근거 ORDER BY 근거유형, 코드;

// Q9. 실내인데 야외 전용 위험이 걸린 곳  (기대: 소수 — 아래 예외 확인)
//     ※ 전역 대상 패턴은 실내에 붙어도 정상입니다.
//        RP_WIND_03 (풍속 14m/s↑, scope=전반)      강풍경보 시 휴관·이동 위험
//        RP_TYPHOON_01 (태풍특보, scope=전역)        전 시설 영향
//        → 175곳 × 2 = 350건이 여기 해당하며 결함이 아닙니다.
//     target_scope 가 특정 지형을 한정한 패턴만 걸러냅니다.
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place)
WHERE p.indoorOutdoor = '실내'
  AND (r.risk_id STARTS WITH 'RP_HEAT' OR r.risk_id STARTS WITH 'RP_RAIN'
    OR r.risk_id STARTS WITH 'RP_WIND' OR r.risk_id STARTS WITH 'RP_WAVE'
    OR r.risk_id STARTS WITH 'RP_SNOW' OR r.risk_id STARTS WITH 'RP_ICE')
  AND NOT coalesce(r.targetScope,'') CONTAINS '전반'
  AND NOT coalesce(r.targetScope,'') CONTAINS '전역'
  // 동굴은 실내로 분류되나 우천 시 내부 미끄럼·낙석 위험이 실재합니다
  AND NOT p.categoryMid = '지질·특수자원'
  // 공항은 결항이 핵심 위험이므로 기상 패턴이 붙는 것이 맞습니다
  AND NOT p.categoryMid = '공항'
  // 실제 사고 기록이 있으면 target_scope 와 달라도 연결이 맞습니다.
  // 설계상 대상 범위보다 실측 사고가 강한 근거입니다.
  AND NOT EXISTS { MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p)
                   WHERE (e)-[:EVIDENCES]->(r) }
RETURN '★실내에 야외전용 위험★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       p.categoryMid AS 분류, collect(r.risk_id) AS 패턴, r.targetScope AS 대상범위
ORDER BY 장소 LIMIT 20;

// Q10. 파고 위험이 내륙에 붙은 곳
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place)
WHERE r.risk_id STARTS WITH 'RP_WAVE'
  AND NOT (p.categoryMid CONTAINS '해' OR p.name CONTAINS '해' OR p.name CONTAINS '포구'
        OR p.name CONTAINS '항' OR p.name CONTAINS '섬')
RETURN '★내륙에 파고위험★' AS 결함, p.name AS 장소, p.categoryMid AS 분류 LIMIT 20;

// Q11. 계절 위험 편중 — 겨울(COLD·ICE·SNOW)이 비어 있지 않은지
MATCH (r:RiskPattern) OPTIONAL MATCH (r)-[:APPLIES_TO]->(p:Place)
WITH split(r.risk_id,'_')[1] AS 계열, count(DISTINCT p) AS n
RETURN 계열, sum(n) AS 연결장소수 ORDER BY 연결장소수 DESC;


// ══ C. 안전사고 — 위치·집계 결함 ══

// Q12. 사고 1건이 두 장소에 붙어 있는가  (기대 0행)
MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p:Place)
WITH e, count(p) AS n WHERE n > 1
RETURN '★중복 매칭★' AS 결함, e.accidentId AS 사고, n AS 연결장소수 LIMIT 20;

// Q13. 반경 1km 를 넘는 매칭  (기대 0행)
MATCH (e:AccidentEvent)-[r:OCCURRED_AT]->(p:Place)
WHERE r.distanceM IS NOT NULL AND toFloat(r.distanceM) > 1000
RETURN '★반경 초과★' AS 결함, e.accidentId AS 사고, p.name AS 장소, r.distanceM AS 거리 LIMIT 20;

// Q14. ambient 등급이 임계값 규칙과 어긋나는 곳  (기대 0행)
//      규칙(역산): LOW ≤3.5 / MEDIUM ≤12.0 / HIGH >12.0 — 문서에 없으니 함께 인계하십시오.
MATCH (p:Place) WHERE p.ambientAnnualAvg IS NOT NULL AND p.ambientBasis = 'NEARBY_1KM'
WITH p, CASE WHEN p.ambientAnnualAvg <= 3.5 THEN 'LOW'
             WHEN p.ambientAnnualAvg <= 12.0 THEN 'MEDIUM' ELSE 'HIGH' END AS 계산값
WHERE 계산값 <> p.ambientRiskLevel
RETURN '★등급-수치 불일치★' AS 결함, p.name AS 장소, p.ambientAnnualAvg AS 연평균,
       p.ambientRiskLevel AS 등급, 계산값 AS 규칙상;

// Q14-B. 사고가 났는데 위험패턴이 안 걸린 곳 — 0행이어야 함
//     사고와 위험패턴은 EVIDENCES 관계로 이어집니다.
//     같은 장소에서 그 유형 사고가 실제로 났다면 APPLIES_TO 도 있어야 합니다.
//     ※ AccidentEvent 에 risk_id 속성은 없습니다. 관계를 타야 합니다.
//     ※ targetScope 가 '[장소 무관]' 인 5개는 제외합니다.
MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p:Place)
MATCH (e)-[:EVIDENCES]->(r:RiskPattern)
WHERE NOT coalesce(r.targetScope,'') STARTS WITH '[장소 무관]'
  AND NOT (r)-[:APPLIES_TO]->(p)
RETURN '★사고 있는데 패턴 미연결★' AS 결함, p.name AS 장소,
       r.risk_id AS 패턴, count(e) AS 사고건수
ORDER BY 사고건수 DESC LIMIT 20;

// Q15. 사고는 많은데 directRiskScore 가 0  (정의 차이 확인용)
MATCH (p:Place)<-[:OCCURRED_AT]-(e:AccidentEvent)
WITH p, count(e) AS 사고수 WHERE 사고수 >= 5 AND coalesce(p.directRiskScore,0.0) = 0.0
RETURN p.name AS 장소, 사고수, coalesce(p.ambientRiskLevel,'-') AS 인근위험
ORDER BY 사고수 DESC LIMIT 15;


// ══ D. 위치·구조 — 정합성 ══

// Q16. 제주 범위를 벗어난 좌표  (기대 0행)
MATCH (p:Place)
WHERE NOT ((p.latitude >= 33.10 AND p.latitude <= 33.60 AND p.longitude >= 126.10 AND p.longitude <= 126.99)
        OR (p.latitude >= 33.90 AND p.latitude <= 34.00 AND p.longitude >= 126.25 AND p.longitude <= 126.40))
RETURN '★좌표 범위 이탈★' AS 결함, p.placeId AS 코드, p.name AS 장소, p.latitude AS 위도, p.longitude AS 경도;

// Q17. 도로명주소와 행정구역이 어긋난 곳  (기대 0행 — FIX56 이전에는 8건)
//      region 은 좌표 기반이라 맞고 roadAddress 가 틀린 쪽이었습니다.
MATCH (p:Place)-[:LOCATED_IN]->(rg:RegionSafetyStat)
WHERE p.roadAddress IS NOT NULL AND p.roadAddress <> '' AND p.roadAddress <> 'UNKNOWN'
  AND ((p.roadAddress CONTAINS '제주시' AND rg.region_id STARTS WITH 'REG_서귀포시')
    OR (p.roadAddress CONTAINS '서귀포시' AND rg.region_id STARTS WITH 'REG_제주시'))
RETURN '★주소-행정구역 불일치★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       left(p.roadAddress,30) AS 도로명, rg.region_id AS 행정구역;

// Q18. 중복 노드 후보 — 이름이 '같고' 좌표가 가까운 곳  (기대 0행)
//     ※ 포함 관계(a.name CONTAINS b.name)로 잡으면 오탐이 많습니다.
//        한림공원 ⊃ 황금굴(한림공원), 제주민속촌 ⊃ 대장금촬영지 처럼
//        상위 시설과 그 안의 개별 시설은 서로 다른 장소입니다.
//     → 괄호를 걷어낸 이름이 '완전히 같을' 때만 중복으로 봅니다.
MATCH (a:Place), (b:Place)
WHERE a.placeId < b.placeId
  AND a.recommendable = 'Y' AND b.recommendable = 'Y'
  AND replace(split(a.name,'(')[0],' ','') = replace(split(b.name,'(')[0],' ','')
  AND point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                     point({latitude:b.latitude, longitude:b.longitude})) < 500
RETURN '★중복 노드★' AS 결함,
       a.placeId AS 코드1, a.name AS 장소1, b.placeId AS 코드2, b.name AS 장소2,
       round(point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                            point({latitude:b.latitude, longitude:b.longitude}))) AS 거리m
ORDER BY 거리m;

// Q18-C. 좌표가 사실상 같은데 이름이 달라 안 걸린 중복 — 0행이어야 함
//     이호테우해변 / 이호테우해수욕장 이 이 방식으로 발견됐습니다.
//     ※ 좌표만 보면 오탐이 많습니다. 성산항 일대처럼 여러 시설이 대표좌표를 공유합니다.
//       이름의 한쪽이 다른 쪽을 포함할 때만 중복으로 봅니다.
//     ※ 상위 시설과 그 안의 개별 시설(붉은오름 / 붉은오름자연휴양림,
//       한림공원 / 황금굴)은 다른 장소이므로 categoryMid 가 같을 때만 봅니다.
MATCH (a:Place), (b:Place)
WHERE a.placeId < b.placeId
  AND a.recommendable = 'Y' AND b.recommendable = 'Y'
  AND a.categoryMid = b.categoryMid
  AND point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                     point({latitude:b.latitude, longitude:b.longitude})) < 100
  // 이름 길이 차가 크면 상위/하위 시설입니다. (관음사 / 관음사 군 주둔지 옛터)
  AND (replace(a.name,' ','') CONTAINS replace(b.name,' ','')
    OR replace(b.name,' ','') CONTAINS replace(a.name,' ',''))
  AND abs(size(replace(a.name,' ','')) - size(replace(b.name,' ',''))) <= 4
RETURN '★좌표 동일 중복★' AS 결함, a.placeId AS 코드1, a.name AS 장소1,
       b.placeId AS 코드2, b.name AS 장소2, a.categoryMid AS 분류,
       round(point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                            point({latitude:b.latitude, longitude:b.longitude}))) AS 거리m
ORDER BY 거리m;

// Q18-B. 같은 장소인데 판정이 엇갈리는가 — 서비스가 모순된 답을 냅니다
MATCH (a:Place)-[:HAS_ACCESSIBILITY]->(ca:Accessibility),
      (b:Place)-[:HAS_ACCESSIBILITY]->(cb:Accessibility)
WHERE a.placeId < b.placeId
  AND replace(split(a.name,'(')[0],' ','') = replace(split(b.name,'(')[0],' ','')
  AND point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                     point({latitude:b.latitude, longitude:b.longitude})) < 500
  AND (ca.activityAccess <> cb.activityAccess
    OR coalesce(ca.recommendForMobility,'Y') <> coalesce(cb.recommendForMobility,'Y'))
RETURN '★판정 충돌★' AS 결함, a.placeId AS 코드1, a.name AS 장소1,
       ca.activityAccess AS 활동1, ca.recommendForMobility AS 게이트1,
       b.placeId AS 코드2, cb.activityAccess AS 활동2, cb.recommendForMobility AS 게이트2;

// Q19. 섬인데 여객선 정보가 없는 곳  (기대 0행)
MATCH (p:Place) WHERE p.isIsland = 'Y'
  AND (coalesce(p.ferryPort,'') = '' OR coalesce(p.islandAccessNote,'') = '')
RETURN '★섬 여객선 결측★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       coalesce(p.islandName,'-') AS 섬, coalesce(p.ferryPort,'★없음★') AS 항구;

// Q20. 접근성 노드가 없는 Place  (기대 0행)
MATCH (p:Place) WHERE NOT (p)-[:HAS_ACCESSIBILITY]->(:Accessibility)
RETURN '★접근성 노드 없음★' AS 결함, p.placeId AS 코드, p.name AS 장소, p.categoryMain AS 분류;

// Q20-B. 관광객 대상이 아닌 안전 메시지 — 5행. 서비스 응답에서 걸러야 합니다.
//     target_user 가 '[비관광]' 으로 시작하면 도민 생활안전(농기계·벌초) 메시지입니다.
//     대응 패턴 RP_MACHINE_01 · RP_FALL_01 도 [장소 무관] 으로 분류돼 있습니다.
//     서비스 쿼리에서 안내 문구를 조회할 때 다음 조건을 넣으십시오.
//        AND NOT coalesce(msg.targetUser,'') STARTS WITH '[비관광]'
MATCH (msg:AdvisoryMessage)
WHERE coalesce(msg.targetUser,'') STARTS WITH '[비관광]'
RETURN msg.message_id AS 코드, msg.targetUser AS 대상,
       left(msg.template, 50) AS 문구 ORDER BY 코드;

// Q5-B. 자동 생성 안내문의 과잉 단정 — 0행이어야 함
//     routeCondition 태그에서 만든 문장이 태그에 없는 범위를 단정하면 안 됩니다.
//     예: '휠체어 접근 가능' 태그 하나로 "그 외 구간은 모두 이동 가능" 이라 쓰면
//        근거 없는 단정입니다. 성산일출봉에서 실제로 발생했습니다.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.verifyNote,'') CONTAINS 'FIX74'
  AND (ac.mobilityCaveat CONTAINS '그 외 구간은 휠체어로 이동하실 수 있습니다'
    OR ac.mobilityCaveat CONTAINS '모든 구간'
    OR ac.mobilityCaveat CONTAINS '전 구간 이동 가능')
RETURN '★근거 없는 단정★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       left(ac.mobilityCaveat, 70) AS 문구;

// Q5-C. 자동 생성 안내문이 남아 있는 곳 — 수동 보강 대상 목록
//     0행일 필요는 없습니다. 방문객이 많은 곳부터 구체화하십시오.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.verifyNote,'') CONTAINS 'FIX74'
RETURN '수동 보강 대상' AS 상태, count(*) AS 건수;

// Q5-E. routeCondition 에 있는 제약이 안내문에서 누락됐는가 — 0행이어야 함
//     자동 생성문이 긍정 태그만 보고 제약을 빠뜨린 사례가 있었습니다.
//     섭지코지는 '동행보조 필요+휠체어 접근 가능' 인데 "이동하실 수 있습니다" 로만 나갔고,
//     실제로는 국가인권위원회가 접근 제한을 인정해 개선을 권고한 곳이었습니다.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE (ac.routeCondition CONTAINS '동행보조' OR ac.routeCondition CONTAINS '이동 보조'
    OR ac.routeCondition CONTAINS '보조 필요')
  AND NOT coalesce(ac.mobilityCaveat,'') CONTAINS '동행'
  AND NOT coalesce(ac.mobilityCaveat,'') CONTAINS '도움'
  AND NOT coalesce(ac.mobilityCaveat,'') CONTAINS '보조'
RETURN '★제약 누락★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       ac.routeCondition AS 경로조건, left(ac.mobilityCaveat,50) AS 안내;

// Q5-F. 개선 권고·공사 예정 시설의 재확인 대상
//     0행일 필요는 없습니다. 정기적으로 상태를 다시 확인하십시오.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE coalesce(ac.verifyNote,'') CONTAINS '개선'
  AND (coalesce(ac.verifyNote,'') CONTAINS '권고' OR coalesce(ac.verifyNote,'') CONTAINS '예정')
RETURN '재확인 대상' AS 상태, p.placeId AS 코드, p.name AS 장소,
       ac.mobilityAccess AS 이동축, left(ac.verifyNote,80) AS 근거;

// Q5-D. 구체 수치가 든 안내문에 근거 시점이 없는가 — 0행이어야 함
//     "5~7도 오르막" 같은 수치는 조사 시점에 따라 달라집니다.
//     verifyNote 에 연도가 없으면 현재 사실처럼 읽혀 위험합니다.
//     실제로 함덕해수욕장에서 2023년 조사값을 시점 없이 쓴 사례가 있었습니다.
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE ac.mobilityCaveat =~ '.*[0-9]+\\s*(도|cm|m|미터|%).*'
  AND NOT coalesce(ac.verifyNote,'') =~ '.*20[0-9][0-9].*'
RETURN '★근거 시점 없음★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       left(ac.mobilityCaveat, 60) AS 문구;

// Q21(보너스). 좌표가 근사 보정된 곳 — 정밀 좌표 확인 대상
MATCH (p:Place) WHERE p.note CONTAINS 'APPROX'
RETURN '확인 필요' AS 상태, p.placeId AS 코드, p.name AS 장소,
       p.latitude AS 위도, p.longitude AS 경도, left(p.note,90) AS 비고;


// ══ E. 종합 — 한 번에 훑기 (전부 0 이어야 정상) ══
CALL () { MATCH (ac:Accessibility) WHERE ac.wheelchairAccess='FULL' AND coalesce(ac.strollerAccess,'UNKNOWN')='NONE'
          RETURN 'Q1  휠체어FULL+유모차NONE' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility) WHERE ac.activityAccess='UNAVAILABLE' AND coalesce(ac.recommendForMobility,'Y')='Y'
          RETURN 'Q3  불가인데 추천' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility) WHERE coalesce(ac.wheelchairSection,'')<>'' AND coalesce(ac.wheelchairSectionDist,'')=''
          RETURN 'Q4  구간거리 결측' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p:Place) WITH e, count(p) AS n WHERE n>1
          RETURN 'Q12 사고 중복매칭' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (:AccidentEvent)-[r:OCCURRED_AT]->(:Place)
          WHERE r.distanceM IS NOT NULL AND toFloat(r.distanceM)>1000
          RETURN 'Q13 반경 1km 초과' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (p:Place) WHERE p.ambientAnnualAvg IS NOT NULL AND p.ambientBasis='NEARBY_1KM'
          WITH p, CASE WHEN p.ambientAnnualAvg<=3.5 THEN 'LOW'
                       WHEN p.ambientAnnualAvg<=12.0 THEN 'MEDIUM' ELSE 'HIGH' END AS c
          WHERE c <> p.ambientRiskLevel
          RETURN 'Q14 ambient 등급 불일치' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (p:Place)
          WHERE NOT ((p.latitude>=33.10 AND p.latitude<=33.60 AND p.longitude>=126.10 AND p.longitude<=126.99)
                  OR (p.latitude>=33.90 AND p.latitude<=34.00 AND p.longitude>=126.25 AND p.longitude<=126.40))
          RETURN 'Q16 좌표 범위 이탈' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (p:Place)-[:LOCATED_IN]->(rg:RegionSafetyStat)
          WHERE p.roadAddress IS NOT NULL AND p.roadAddress<>'' AND p.roadAddress<>'UNKNOWN'
            AND ((p.roadAddress CONTAINS '제주시' AND rg.region_id STARTS WITH 'REG_서귀포시')
              OR (p.roadAddress CONTAINS '서귀포시' AND rg.region_id STARTS WITH 'REG_제주시'))
          RETURN 'Q17 주소-행정구역 불일치' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (p:Place) WHERE p.isIsland='Y'
            AND (coalesce(p.ferryPort,'')='' OR coalesce(p.islandAccessNote,'')='')
          RETURN 'Q19 섬 여객선 결측' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (p:Place) WHERE NOT (p)-[:HAS_ACCESSIBILITY]->(:Accessibility)
          RETURN 'Q20 접근성 노드 없음' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수;
