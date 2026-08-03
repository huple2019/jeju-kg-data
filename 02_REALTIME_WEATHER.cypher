// ════════════════════════════════════════════════════════════════
//  실시간 기상 판정 — ETRI weather 직접접근 연동판
//  전제(2026): ETRI weather_forecasting_tb / weather_realtime_observation_tb 를
//              휴플 서비스 서버가 직접 조회 → 값을 Cypher 파라미터로 주입
//  원칙: 안전 판정은 Neo4j 규칙만 수행 (LLM 미개입)
//        환경 수치는 노드가 아니라 파라미터 (실시간이므로 그래프에 저장 안 함)
// ════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────
// [서비스 서버가 수행하는 사전 단계 — 참고용, Cypher 아님]
//   ① 앵커 관광지 좌표 확보 (KG Place.location)
//   ② ETRI PostgreSQL 조회 (좌표→격자→최신 예보):
//       SELECT f.wind_speed, f.precipitation, f.wave_height, f.temperature
//       FROM weather_forecasting_tb f
//       JOIN weather_grid_tb g ON f.weather_grid_id = g.weather_grid_id
//       ORDER BY g.geom <-> ST_SetSRID(ST_MakePoint($lon,$lat),4326)   -- 최근접 격자
//       , f.reported_at DESC LIMIT 1;
//   ③ 특보 판정용 순간최대풍속/12h강수는 weather_realtime_observation_tb에서:
//       wind_speed_max_instant_ms, rain_acc_12h_mm
//   ④ 위 값들을 아래 Cypher의 $파라미터로 전달
// ─────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════
//  [핵심] 특정 관광지 실시간 기상 위험 판정
//  파라미터(ETRI 조회값): $placeName, $wind_speed, $wind_gust, $rain_mmh,
//                        $rain_12h, $wave_height, $temperature, $humidity
// ═══════════════════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})
// 이 관광지에 적용되는 환경 트리거형 RiskPattern을 파라미터와 비교 판정
MATCH (r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE r.riskType IN ['강풍위험','강수위험','파고위험','폭염위험','한파위험']
WITH p, r,
  // factor별 현재값 매칭 (ETRI 필드 → 파라미터)
  CASE r.riskType
    WHEN '강풍위험' THEN coalesce($wind_gust, $wind_speed)   // 특보판정은 순간최대 우선
    WHEN '강수위험' THEN $rain_mmh
    WHEN '파고위험' THEN $wave_height
    WHEN '폭염위험' THEN $temperature
    ELSE null END AS currentVal,
  toFloat(r.thresholdMin) AS lo, toFloat(r.thresholdMax) AS hi
WHERE currentVal IS NOT NULL
  // 임계 구간 판정: [lo, hi) 또는 lo 이상
  AND ( (lo IS NOT NULL AND hi IS NOT NULL AND currentVal >= lo AND currentVal < hi)
     OR (lo IS NOT NULL AND hi IS NULL  AND currentVal >= lo)
     OR (lo IS NULL  AND hi IS NOT NULL AND currentVal <= hi) )
// 발동된 위험 → 행동안내(RESULTS_IN)
MATCH (r)-[:RESULTS_IN]->(act:RecommendationAction)
RETURN p.name AS 관광지,
       collect(DISTINCT {위험:r.name, 현재값:currentVal, 임계:r.thresholdMin+'~'+coalesce(r.thresholdMax,'∞'),
                         판정:act.decisionLevel, 안내:act.nameKr}) AS 발동위험,
       // 최종 판정: 회피>시간조정>주의>GO
       CASE
         WHEN any(x IN collect(act.decisionLevel) WHERE x='회피') THEN '회피'
         WHEN any(x IN collect(act.decisionLevel) WHERE x='시간조정') THEN '시간조정'
         WHEN size(collect(act.decisionLevel))>0 THEN '주의'
         ELSE 'GO' END AS 최종판정;

// ═══════════════════════════════════════════════════════════════
//  [특보 연동] 관측값이 기상청 특보 기준 초과 시 통제 강제
//  강풍경보(순간26)·풍랑경보(파고5) 등은 riskLevel='통제'로 즉시 회피
// ═══════════════════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})<-[:APPLIES_TO]-(r:RiskPattern)-[:RESULTS_IN]->(act)
WHERE (r.riskType='강풍위험' AND coalesce($wind_gust,$wind_speed) >= 21)   // 강풍경보
   OR (r.riskType='파고위험' AND $wave_height >= 3.0)                       // 풍랑주의보↑
   OR (r.riskType='강수위험' AND $rain_12h >= 110)                          // 호우주의보(12h)
RETURN p.name, '특보구간-통제' AS 판정, collect(DISTINCT r.name) AS 발동특보,
       '실외 활동 통제 권고' AS 안내;

// ═══════════════════════════════════════════════════════════════
//  [상류강수 → 하류범람] FlashFloodRisk (올레 인터뷰 반영)
//  앵커가 계곡/세월교면, 한라산권 격자 강수를 별도 조회해 판정
//  파라미터: $upstream_rain_mmh (한라산권 격자 예보값)
// ═══════════════════════════════════════════════════════════════
MATCH (p:Place {name:$placeName})<-[:APPLIES_TO]-(r:RiskPattern {risk_id:'RP_FLASHFLOOD_01'})
WHERE $upstream_rain_mmh >= 10
MATCH (r)-[:RESULTS_IN]->(act)
RETURN p.name, '상류강수-하류범람주의' AS 판정, $upstream_rain_mmh AS 상류강수, act.nameKr AS 안내;

// ═══════════════════════════════════════════════════════════════
//  [통합] 앵커근접형 + 실시간 기상 (01_QUERY 유형2의 실시간 확장)
//  주변 후보 각각에 대해 현재 기상으로 판정까지
//  파라미터: $anchor, $radius_km, $wind_speed, $rain_mmh, $wave_height
//  ※ 후보별 좌표가 달라 엄밀히는 후보별 격자 조회 필요 —
//    앵커 근방 5km는 동일 격자(5km) 가정으로 앵커 기상 공유 가능
// ═══════════════════════════════════════════════════════════════
MATCH (anchor:Place {name:$anchor})
MATCH (cand:Place)
WHERE cand<>anchor
  AND point.distance(anchor.location, cand.location) <= coalesce($radius_km,5)*1000
  AND cand.event2026Status <> 'CONTROLLED'
OPTIONAL MATCH (r:RiskPattern)-[:APPLIES_TO]->(cand)
WHERE (r.riskType='강풍위험' AND $wind_speed >= toFloat(r.thresholdMin))
   OR (r.riskType='강수위험' AND $rain_mmh >= toFloat(r.thresholdMin))
   OR (r.riskType='파고위험' AND $wave_height >= toFloat(r.thresholdMin))
OPTIONAL MATCH (r)-[:RESULTS_IN]->(act)
WITH cand, point.distance(anchor.location,cand.location) AS dist,
     collect(DISTINCT act.decisionLevel) AS decisions, coalesce(cand.riskScore,0) AS baseRisk
RETURN cand.name AS 관광지, round(dist) AS 거리m,
       CASE WHEN '회피' IN decisions THEN '회피'
            WHEN '시간조정' IN decisions THEN '시간조정'
            WHEN size(decisions)>0 THEN '주의' ELSE 'GO' END AS 실시간판정,
       cand.riskScore AS 사고이력점수
ORDER BY (size(decisions)=0) DESC, baseRisk ASC, dist ASC
LIMIT 8;
