// ════════════════════════════════════════════════════════════════════════
//  08_QA_DEFECT_TESTS.cypher      오류 잡기용 20종      (schema v3 / FIX56)
//
//  07 번이 "답이 나오는가" 를 본다면, 이 파일은 "틀린 답이 나오지 않는가" 를 봅니다.
//  각 테스트에 기대값을 적어 두었습니다. 대부분 0행이 정상입니다.
//
//  주의: 희소 속성은 반드시 coalesce 로 감쌉니다.
//        RiskPattern 속성명은 CSV 와 다릅니다 — risk_name→name, threshold_min→thresholdMin
//        Region 노드 라벨은 RegionSafetyStat 입니다.
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
  AND NOT coalesce(r.target_scope,'') STARTS WITH '[장소 무관]'
RETURN '★연결 없는 패턴★' AS 결함, r.risk_id AS 코드, r.risk_name AS 패턴,
       r.risk_level AS 등급, r.target_scope AS 대상 ORDER BY 코드;

// Q7-B. 장소 무관 패턴 목록 — 4행. 설계상 정상이며 시기·활동 조건으로만 발동합니다.
MATCH (r:RiskPattern) WHERE coalesce(r.target_scope,'') STARTS WITH '[장소 무관]'
RETURN r.risk_id AS 코드, r.risk_name AS 패턴, r.condition_expr AS 조건, r.target_scope AS 대상
ORDER BY 코드;

// Q8. 안개 근거는 있는데 RP_FOG 패턴이 연결 안 된 곳  (기대 0행)
//     FIX58~59 에서 RP_FOG 3단계를 정의하고 관광지 29곳·도로 4개에 연결했습니다.
MATCH (p:Place) WHERE p.fogBasis IS NOT NULL
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(p) WHERE r.risk_id STARTS WITH 'RP_FOG'
WITH p, count(r) AS n WHERE n = 0
RETURN '★안개 패턴 없음★' AS 결함, p.placeId AS 코드, p.name AS 장소,
       p.fogBasis AS 근거유형, p.fogEvidence AS 근거 ORDER BY 근거유형, 코드;

// Q9. 실내인데 야외 날씨 위험이 걸린 곳
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p:Place)
WHERE p.indoorOutdoor = '실내'
  AND (r.risk_id STARTS WITH 'RP_HEAT' OR r.risk_id STARTS WITH 'RP_RAIN'
    OR r.risk_id STARTS WITH 'RP_WIND' OR r.risk_id STARTS WITH 'RP_WAVE')
RETURN '★실내에 야외위험★' AS 결함, p.name AS 장소, collect(r.risk_id) AS 패턴 ORDER BY 장소 LIMIT 20;

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
WHERE r.distance_m IS NOT NULL AND toFloat(r.distance_m) > 1000
RETURN '★반경 초과★' AS 결함, e.accidentId AS 사고, p.name AS 장소, r.distance_m AS 거리 LIMIT 20;

// Q14. ambient 등급이 임계값 규칙과 어긋나는 곳  (기대 0행)
//      규칙(역산): LOW ≤3.5 / MEDIUM ≤12.0 / HIGH >12.0 — 문서에 없으니 함께 인계하십시오.
MATCH (p:Place) WHERE p.ambientAnnualAvg IS NOT NULL AND p.ambientBasis = 'NEARBY_1KM'
WITH p, CASE WHEN p.ambientAnnualAvg <= 3.5 THEN 'LOW'
             WHEN p.ambientAnnualAvg <= 12.0 THEN 'MEDIUM' ELSE 'HIGH' END AS 계산값
WHERE 계산값 <> p.ambientRiskLevel
RETURN '★등급-수치 불일치★' AS 결함, p.name AS 장소, p.ambientAnnualAvg AS 연평균,
       p.ambientRiskLevel AS 등급, 계산값 AS 규칙상;

// Q14-B. 사고가 났는데 위험패턴이 안 걸린 곳 — 0행이어야 함
//     AccidentEvent 에 risk_id·placeId 가 함께 있으면 그 장소에 해당 패턴이 걸려야 합니다.
//     '실제로 그 유형 사고가 났다' 는 가장 강한 연결 근거입니다.
//     ※ target_scope 가 '[장소 무관]' 인 5개는 제외합니다.
MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p:Place)
MATCH (r:RiskPattern) WHERE r.risk_id = e.risk_id
  AND NOT coalesce(r.target_scope,'') STARTS WITH '[장소 무관]'
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

// Q18. 이름이 겹치고 좌표가 가까운 중복 후보
//      양쪽 다 recommendable='Y' 인 쌍이 없어야 합니다.
MATCH (a:Place), (b:Place)
WHERE a.placeId < b.placeId
  AND point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                     point({latitude:b.latitude, longitude:b.longitude})) < 500
  AND (a.name CONTAINS b.name OR b.name CONTAINS a.name)
RETURN a.placeId AS 코드1, a.name AS 장소1, a.recommendable AS 추천1,
       b.placeId AS 코드2, b.name AS 장소2, b.recommendable AS 추천2,
       round(point.distance(point({latitude:a.latitude, longitude:a.longitude}),
                            point({latitude:b.latitude, longitude:b.longitude}))) AS 거리m
ORDER BY 거리m;

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
//        AND NOT coalesce(msg.target_user,'') STARTS WITH '[비관광]'
MATCH (msg:AdvisoryMessage)
WHERE coalesce(msg.target_user,'') STARTS WITH '[비관광]'
RETURN msg.message_id AS 코드, msg.target_user AS 대상,
       left(msg.message_template, 50) AS 문구 ORDER BY 코드;

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
          WHERE r.distance_m IS NOT NULL AND toFloat(r.distance_m)>1000
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
