# 제주 안전관광 지식그래프 — 최종 통합 적재 패키지

중간보고(2026.07.16) 최종 스키마(노드 10종)를 기준으로, **질의→탐색→판단→행동안내**
경로가 Neo4j Aura에서 실제 동작하도록 세 zip을 통합하고 끊긴 고리 4개를 이었습니다.

## 업로드 방법
기존 세 zip의 CSV + 이 패키지의 bridge CSV를 **모두 같은 Aura Import 폴더**에 넣고,
`00_MASTER_LOAD.cypher`를 위에서 아래로 실행하면 됩니다. (파일명이 겹치지 않으므로 병합 OK)
이후 `01_QUERY_TEMPLATES.cypher`로 4유형 판단 쿼리 실행.

## 이번에 이은 끊긴 고리 4개 (이게 저번 "부족"의 실체)
중간보고 판단 경로(슬라이드14·15·19)에 필수인데 세 zip엔 없던 것들:

| # | 끊긴 고리 | 신규 파일 | 결과 |
|---|---|---|---|
| 1 | **RecommendationAction 노드 + RESULTS_IN** (Risk→행동안내) 자체가 없었음 | nodes_recommendation_action.csv, rel_risk_RESULTS_IN_action.csv | 9노드 / 36관계, 전 RiskPattern이 행동안내에 도달 |
| 2 | **Activity 두 체계 단절** (KG주활동 ACT_### ↔ 위험연결 ACTV_##) | rel_activity_MAPS_TO_v3.csv | KG 128개 중 20개→v3 위험활동 연결 |
| 3 | **RiskPattern→Place 실엣지 없음** (scope 매핑표만 존재) | rel_risk_APPLIES_TO_place.csv | 28 RP→1,025 Place, 11,354 APPLIES_TO 엣지 |
| 4 | **VisitorProfile 판단축 + SENSITIVE_TO 없음** (기존 3개는 사고피해자용) | nodes_visitor_profile_v3.csv, rel_profile_SENSITIVE_TO_risk.csv | 8노드 / 16 취약성 관계 |

## 라벨 정리 (혼선 방지)
- KG 주활동(이동·쇼핑 등 128개) → `:TourActivity` (검색·분류용)
- v3 행동유형(Trekking·Diving 등 15개) → `:Activity` (위험 판단용, 중간보고 ★신설 축)
- 둘은 `MAPS_TO`로 연결 → "관광지가 가진 활동"에서 "그 활동의 위험"으로 도달 가능
- VisitorProfile은 kind 속성으로 구분: 'accident_victim'(3, 사고통계) / 'recommendation_target'(8, 판단용)

## 판단 경로 동작 검증 (실측)
활동 → CARRIES → RiskPattern → RESULTS_IN → Action 체인이 근거까지 붙어 나옴:
- Diving → 익수위험 → **시간조정권고** | 적용관광지 20 · 사고근거 209 · 주의보근거 2
- Trekking → 길잃음/산악/동물 위험 → 시간조정·주의 | 근거 다수
- Driving → 교통위험 → 주의안내 | 사고근거 126
무결성: RESULTS_IN 없는 RiskPattern 0개. APPLIES_TO 없는 8개는 활동·제도기반(교통·화재·CO 등)
으로 CARRIES 경로로 도달하므로 정상.

## 4유형 판단 쿼리 (01_QUERY_TEMPLATES.cypher)
슬라이드 21·24·25의 4유형을 실제 Cypher로 구현:
- **일정형**: 하드필터(통제·6개월내 사망중상 제외) → 소프트랭킹(대표성+riskScore) → 카테고리 다양성
- **앵커근접형**: point.distance 반경탐색 → 앵커 위험선점검 → 후보 판정(회피/시간조정/주의/GO)
- **상황확인형**: 단일 관광지 종합판정만 반환(추천 없음)
- **조건탐색형**: 접근성 역방향 진입 → 프로필 민감위험 태깅 → 지원시설순

## 스키마 대비 남은 항목 (데이터 없음 — 향후)
- **RouteSegment**: 동선/세월교/우회 — ETRI Geometry 도메인(내년 연동) 대기. 현재 원천데이터 없음.
- **EnvironmentCondition(실시간)**: 현재 Environment는 사고시점 기상만. 실시간 판정은
  ETRI weather_grid 연동 시 TRIGGERS 엣지 활성화 예정(조건식은 rels_environment_risk.csv에 준비됨).
- 이 두 가지는 중간보고에서도 "내년 연동/구상" 단계로 명시된 부분이라 현 적재 범위 밖.
