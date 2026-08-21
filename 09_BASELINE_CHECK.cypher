// ════════════════════════════════════════════════════════════════════════
//  09_BASELINE_CHECK.cypher     적재 후 기준값 대조     (2026-08 · FIX65 기준)
//
//  ⚠ 다른 파일의 '// 기대:' 주석은 시점에 따라 낡아 있을 수 있습니다.
//    적재가 정상인지 확인할 때는 이 파일을 쓰십시오.
//    여기 값이 CURRENT_BASELINE.md 와 일치하면 정상입니다.
//
//  ※ 숫자가 다르다고 곧바로 오류는 아닙니다. 데이터를 고치면 당연히 바뀝니다.
//    중요한 것은 '내가 푸시한 CSV 와 그래프가 같은가' 입니다.
//
//  ※ 속성명 주의 — 로더가 CSV 컬럼을 카멜케이스로 바꿔 넣습니다.
//    condition_expr → conditionExpr,  risk_name → name,  risk_level → riskLevel
//    threshold_min → thresholdMin,    target_scope → targetScope
//    CSV 컬럼명을 그대로 쓰면 조용히 빈 결과가 나옵니다.
// ════════════════════════════════════════════════════════════════════════

// ─── [1] 한눈에 보기 — 현재 값 ───
//  ※ 기준 숫자를 여기 적어두지 않습니다. 데이터를 고치면 당연히 바뀌기 때문입니다.
//    "숫자가 주석과 다르다" 로 혼란이 반복돼 실측값만 출력하도록 바꿨습니다.
//    비교가 필요하면 CURRENT_BASELINE.md 를 보십시오. 그 문서만 갱신합니다.
//    ★ 정상 여부 판단은 아래 [5]번으로 하십시오.
MATCH (ac:Accessibility)
RETURN 'Accessibility 노드' AS 항목, count(*) AS 값
UNION ALL
MATCH (p:Place) RETURN 'Place 노드' AS 항목, count(*) AS 값
UNION ALL
MATCH (r:RiskPattern) RETURN 'RiskPattern' AS 항목, count(*) AS 값
UNION ALL
MATCH (ac:Accessibility) WHERE coalesce(ac.recommendForMobility,'Y')='Y'
RETURN '이동축 게이트 Y' AS 항목, count(*) AS 값
UNION ALL
MATCH (ac:Accessibility) WHERE ac.recommendForMobility='N'
RETURN '이동축 게이트 N' AS 항목, count(*) AS 값
UNION ALL
MATCH (ac:Accessibility) WHERE coalesce(ac.wheelchairSection,'')<>''
RETURN '무장애 구간 보유' AS 항목, count(*) AS 값
UNION ALL
MATCH (ac:Accessibility) WHERE ac.visualAccess IN ['FULL','PARTIAL']
RETURN '시각축 확보' AS 항목, count(*) AS 값
UNION ALL
MATCH (ac:Accessibility) WHERE ac.hearingAccess IN ['FULL','PARTIAL']
RETURN '청각축 확보(데이터 부재)' AS 항목, count(*) AS 값
UNION ALL
MATCH (ac:Accessibility) WHERE ac.cognitiveAccess IN ['FULL','PARTIAL']
RETURN '발달축 확보(데이터 부재)' AS 항목, count(*) AS 값
UNION ALL
MATCH ()-[r:APPLIES_TO]->(:Place) RETURN 'APPLIES_TO' AS 항목, count(r) AS 값
UNION ALL
MATCH ()-[r:APPLIES_TO_ROAD]->(:RoadSegment) RETURN 'APPLIES_TO_ROAD' AS 항목, count(r) AS 값;


// ─── [2] verifyStatus 분포 ───
//  분포만 확인하십시오. 기준값은 CURRENT_BASELINE.md 참조.
MATCH (ac:Accessibility)
RETURN ac.verifyStatus AS 검증상태, count(*) AS 건수 ORDER BY 건수 DESC;

// ─── [3] evidenceType 분포 ───
//  분포만 확인하십시오. 기준값은 CURRENT_BASELINE.md 참조.
MATCH (ac:Accessibility)
RETURN ac.evidenceType AS 근거유형, count(*) AS 건수 ORDER BY 건수 DESC;

// ─── [4] 4축 확보 현황 ───
//  청각·발달이 낮은 것은 정상입니다. 공식 출처에 데이터가 없습니다.
MATCH (ac:Accessibility)
RETURN
  sum(CASE WHEN ac.mobilityAccess  IN ['FULL','PARTIAL'] THEN 1 ELSE 0 END) AS 이동,
  sum(CASE WHEN ac.visualAccess    IN ['FULL','PARTIAL'] THEN 1 ELSE 0 END) AS 시각,
  sum(CASE WHEN ac.hearingAccess   IN ['FULL','PARTIAL'] THEN 1 ELSE 0 END) AS 청각,
  sum(CASE WHEN ac.cognitiveAccess IN ['FULL','PARTIAL'] THEN 1 ELSE 0 END) AS 발달,
  count(*) AS 전체;


// ─── [5] ★ 진짜 오류 점검 — 전부 0이어야 합니다 ───
//  위 숫자들은 데이터를 고치면 바뀝니다. 아래는 바뀌면 안 되는 것들입니다.
CALL () { MATCH (p:Place) WHERE NOT (p)-[:HAS_ACCESSIBILITY]->(:Accessibility)
          RETURN '접근성 노드 없는 Place' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility) WHERE ac.recommendForMobility IS NULL
          RETURN '게이트 속성 누락' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (r:RiskPattern) WHERE coalesce(r.conditionExpr,'')=''
          RETURN '판정조건 없는 위험패턴' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (e:AccidentEvent)-[:OCCURRED_AT]->(p:Place)
          WITH e, count(p) AS n WHERE n>1
          RETURN '사고 중복 매칭' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility)
          WHERE ac.activityAccess='UNAVAILABLE' AND coalesce(ac.recommendForMobility,'Y')='Y'
          RETURN '불가인데 추천' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수
UNION ALL
CALL () { MATCH (ac:Accessibility)
          WHERE coalesce(ac.wheelchairSection,'')<>'' AND coalesce(ac.wheelchairSectionDist,'')=''
          RETURN '구간거리 결측' AS 점검, count(*) AS 건수 }
RETURN 점검, 건수;
