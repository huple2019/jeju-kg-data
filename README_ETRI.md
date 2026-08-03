# ETRI weather 직접접근 실시간 판정 연동 (2026 올해분)

## 핵심 구조 — "LLM이 아니라 서비스 서버가 ETRI DB를 직접 읽는다"
중간보고 13p 그대로: **ETRI RDB(원천 저장) ↔ 휴플 KG(의미 관계·판단)**
실시간 기상 수치는 그래프에 저장하지 않고, 판정 순간 파라미터로 주입.

```
사용자 질의 → LLM(앵커·날짜 추출)
           → [서비스 서버] 앵커 좌표로 ETRI PostgreSQL 직접 조회
                weather_forecasting_tb JOIN weather_grid_tb (최근접 격자)
           → 조회값을 Cypher $파라미터로 Neo4j 주입
           → [Neo4j] 임계치 규칙으로 위험 판정 → RESULTS_IN → 행동안내
           → LLM(문장화)
```

## 받은 ETRI 문서 정리 (중요)
- **인터페이스 정의서(/v1/responses)는 "웹/SNS 검색 에이전트"** — web_search, fetch_page 2개 도구뿐.
  구조화 기상수치를 주는 API가 아님. 축제·SNS 등 DB미등록 보조정보용.
- **실제 기상 데이터는 샘플 DB 덤프의 weather 테이블에 있음** → 이걸 직접 조회하는 게 올해 방식.

## ETRI weather 필드 매핑 (etri_weather_factor_mapping.csv)
| RiskPattern factor | ETRI 예보 컬럼 | ETRI 관측 컬럼(특보판정) | ETRI 제공 |
|---|---|---|---|
| wind_speed | weather_forecasting_tb.wind_speed | weather_realtime_observation_tb.wind_speed_max_instant_ms | ✓ |
| rain_mm_h | .precipitation | .rain_acc_60m_mm / rain_acc_12h_mm | ✓ |
| wave_height | .wave_height | — | ✓ (예보만) |
| apparent_temp | .temperature (+humidity로 체감환산) | .temp_air_1m_avg_c | ✓ |
| min_temp | .temperature (시계열 min) | .temp_air_1m_avg_c | ✓ |
| lightning | .lightning_strike | — | ✓ (신규활용 가능) |
| snow_24h | — | — | ✗ ETRI밖(기상청 별도) |
| cai(대기질) | — | — | ✗ 에어코리아 |
| occupancy(혼잡) | — | — | ✗ 별도산출 |

→ **환경 트리거 23개 중 14개가 ETRI weather로 직접 판정 가능.** 나머지는 별도출처(우리 개발자 수집분 or 외부).

## 격자 매칭
weather_grid_tb에 grid_x/grid_y(기상청 nx/ny) + PostGIS geom(Point) 존재.
→ 관광지 좌표로 `ORDER BY geom <-> ST_MakePoint($lon,$lat) LIMIT 1` 최근접 격자 조회.

## 조건식 구조화 (riskpattern_conditions_structured.csv)
기존 문자열 조건("wind_speed >= 14")을 factor/operator/threshold_low/high로 분해 +
param_key(Cypher 파라미터명) + etri 컬럼명 + available_in_etri 플래그.
→ 서비스 서버가 이 표만 보면 "어떤 ETRI 필드를 읽어 어떤 파라미터로 넣을지" 자동 결정.

## 특보 2단계 반영 (수정사항)
초기엔 14m/s(주의보)도 '통제'로 나오는 과판정이 있었음. 수정:
- **주의보 구간**(풍속14~21, 파고3~5) → riskLevel '위험' → **시간조정**
- **경보 구간**(풍속21+, 파고5+, 12h강수110+) → 02_REALTIME_WEATHER.cypher의
  특보 전용 쿼리가 '통제(회피)'로 격상
→ nodes_riskpattern_v2.csv / rel_risk_RESULTS_IN_action_v2.csv 로 교체 적용

## 판정 검증 (시뮬레이션 실측)
| 입력(ETRI 예보값) | 발동 위험 | 판정 |
|---|---|---|
| 순간풍속 16 m/s | RP_WIND_03 | 시간조정 (주의보) |
| 순간풍속 23 m/s | +특보쿼리 | 통제 (경보) |
| 파고 3.2 m | RP_WAVE_03 | 시간조정 |
| 시간당 강수 12 mm | RP_RAIN_02 | 시간조정 |
| 기온 34°C | RP_HEAT_02 | 시간조정 |
| 풍속 5 m/s | 없음 | GO |

## 파일
- etri_weather_factor_mapping.csv : ETRI 필드 ↔ factor 매핑
- riskpattern_conditions_structured.csv : 조건식 구조화(파라미터 주입용)
- nodes_riskpattern_v2.csv : 특보 2단계 반영 RiskPattern (기존 교체)
- rel_risk_RESULTS_IN_action_v2.csv : 레벨 정합 RESULTS_IN (기존 교체)
- 02_REALTIME_WEATHER.cypher : 실시간 판정 4종 쿼리

## 남은 것 (우리 개발자 수집분과 연결 시)
- snow_24h, cai(대기질), occupancy는 ETRI 밖 → 수집 데이터를 같은 파라미터 규격($snow_24h 등)으로
  넣으면 동일 판정 로직 재사용 가능 (조건식 이미 구조화됨)
- 체감온도: ETRI는 기온만 → 서버에서 습도 결합해 체감온도 환산 후 $apparent_temp로 주입

## 전처리 함수 (etri_weather_preprocess.py)
서버가 ETRI 조회값 → Neo4j 파라미터로 변환하는 모듈. 의존성 없음(표준 라이브러리).

### 계산하는 파생값 (기상청 공식 산식)
- **체감온도**: 여름철(5~9월) 2022.6.2 개정식(습구온도 Stull 추정), 겨울철(11~3월)
  풍속냉각식(기온≤10℃·풍속≥1.3m/s 조건). 계절 자동 분기.
- **특보 판정용 순간최대풍속**: 관측 wind_speed_max_instant_ms 우선 선택
- **12h 누적강수**: 호우특보 판정용 rain_acc_12h_mm
- **일몰까지 남은 분**: astral(있으면) 또는 NOAA 근사식

### 사용법
```python
from etri_weather_preprocess import build_params
f  = query_etri_forecast(lat, lon)       # weather_forecasting_tb 최근접격자 최신
o  = query_etri_observation(lat, lon)    # weather_realtime_observation_tb 최근접관측소
up = query_etri_forecast(HALLA_LAT, HALLA_LON)  # 상류(한라산권) 격자
params = build_params("산방산", lat, lon, f, o, up,
                      external={"snow_24h": 3, "cai": 45})  # 수집분 있으면
session.run(REALTIME_CYPHER, **params)   # 02_REALTIME_WEATHER.cypher
```

### 검증 (전처리→판정 전체 체인)
| 관광지 | ETRI 입력 | 전처리 결과 | 최종판정 |
|---|---|---|---|
| 산방산(여름) | 기온32·습도70·순간풍속16·파고3.2 | 체감33.3℃ | 시간조정 |
| 용머리(태풍) | 순간풍속24·파고5.5·12h강수130 | 경보3종 | 회피(통제) |
| 협재(맑음) | 풍속4·파고0.8 | 발동없음 | GO |

### ETRI 밖 데이터 주입 지점
snow_24h·cai·occupancy는 build_params(external=...)로 넣으면 동일 판정 로직 재사용.
개발자 수집 기상예보가 ETRI 예보를 대체/보완할 경우, ETRIForecast 형태로만 맞추면 됨.
