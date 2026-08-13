# 현재 기준값 (2026-08 · FIX65 반영 후)

적재가 정상인지 확인할 때 이 표와 대조하십시오.
**옛 문서에 남아 있는 숫자와 다르면 이 표가 맞습니다.**

---

## 검증 쿼리와 기대값

```cypher
MATCH (ac:Accessibility)
RETURN ac.verifyStatus AS 검증상태, count(*) AS 건수 ORDER BY 건수 DESC;
```
| 검증상태 | 건수 |
|---|---|
| SURVEYED | **889** |
| VERIFIED | **107** |
| PENDING | **17** |
| PARTIAL | **15** |
| EXCLUDED | **1** |

```cypher
MATCH (ac:Accessibility)
RETURN coalesce(ac.recommendForMobility,'Y') AS 게이트, count(*) AS 건수;
```
| 게이트 | 건수 |
|---|---|
| Y | **840** |
| N | **189** |

```cypher
MATCH (ac:Accessibility)
RETURN ac.visualAccess AS 시각축, count(*) AS 건수 ORDER BY 건수 DESC;
```
| 시각축 | 건수 |
|---|---|
| UNKNOWN | **944** |
| PARTIAL | **70** |
| FULL | **15** |

---

## 주요 지표

| 항목 | 값 |
|---|---|
| Place · Accessibility | 각 **1,029** |
| RiskPattern | **39** (장소 무관 5 포함) |
| 무장애 구간 보유 | **11곳** (올레 공식 10 + 가파도 순환로 1) |
| 시각축 확보 | **85곳** (FIX65 이전 24곳) |
| 청각축 확보 | **25곳** — 데이터 부재, 더 늘릴 수 없음 |
| 발달축 확보 | **9곳** — 동일 |
| APPLIES_TO | **11,871건** |
| APPLIES_TO_ROAD | **52건** |
| 보정이력 | **1,360행** |

---

## 옛 문서의 낡은 숫자

아래 값이 보이면 **이 문서 이전 시점**의 것입니다.

| 낡은 값 | 현재 | 바뀐 이유 |
|---|---|---|
| SURVEYED 891 / VERIFIED 110 / PARTIAL 10 | 889 / 107 / 15 | FIX36·38에서 구조 추론 판정을 VERIFIED → PARTIAL 로 하향 |
| 게이트 Y 851 / N 178 | Y 840 / N 189 | FIX51 부속섬 접근사슬 반영 |
| 게이트 Y 849 / N 180 | Y 840 / N 189 | 〃 |
| 구간 보유 9개 코스 | 11곳 | FIX42 가파도 10-1 등재, FIX47 순환로 추가 |
| 시각축 UNKNOWN 1,005 | 944 | FIX65 한국관광공사 API 반영 |

**VERIFIED 감소는 데이터 품질 저하가 아닙니다.** 운영사 명시 문구가 있는 건과 시설 구조에서 추론한 건을 같은 등급으로 두지 않기 위해 근거 강도를 구분한 결과입니다.
