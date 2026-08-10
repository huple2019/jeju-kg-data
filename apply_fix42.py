# -*- coding: utf-8 -*-
"""
FIX42 — 제주올레 공식 휠체어 코스 10개 체계 완성 (10-1코스 등재)

제주올레 공식 사이트 기준 휠체어 관련 코스는 10개다.
  01 · 04 · 05 · 06 · 08 · 10 · 10-1 · 12 · 14 · 17

이 중 09개는 '구간 한정'(코스 일부만 통행 가능)이고,
10-1코스만 '전 구간' 통행 가능이다. 가파도 4.2km 순환로로 완만한 경사이며
잘라낼 구간이 없어서 2022.07 개정판의 '휠체어구간' 목록에 실리지 않았던 것이다.

적용:
  · P884 를 wheelchairSection 에 등재하되 값에 '전 구간'을 명시한다.
    → 구간 보유 = 10개 = 공식 목록과 일치
    → 서비스는 값이 '전 구간' 으로 시작하면 [구간한정] 이 아니라 [전구간] 으로 분기한다.
      (그대로 두면 '코스 전체가 아니라 X 구간에 한해' 라는 정반대 안내가 나간다)

주의 — 재현하지 않는 것:
  wheelchairAccess IN ['FULL','PARTIAL'] 로는 공식 10개를 재현할 수 없다.
  1-1코스(P227)·7코스(P358)가 자체 현장조사(2026-06) 기반 PARTIAL 로 잡혀 12개가 된다.
  공식 목록('제주올레가 무장애 안내를 제공하는 코스')과
  KG 등급('우리 조사 결과 부분 접근 가능')은 서로 다른 개념이므로 통합하지 않는다.
"""
import csv, io

P884 = {
    "wheelchairSection":     "전 구간 (상동포구~가파포구)",
    "wheelchairSectionDist": "4.2km",
    "wheelchairDifficulty":  "LOW",
    "slopeInfo":             "완만한 경사",
    "wheelchairCaveat":      "코스 자체는 전 구간 통행 가능. 제약은 가파도행 여객선 승하선 — 전동휠체어 선적 불가",
    "verifyNote": (
        "제주올레 공식 코스정보로 확인(2026-08) — 4.2km · 1~2시간 · 난이도 하 · 완만한 경사로 "
        "전 구간 휠체어 이용 가능. 제주올레 공식 휠체어 코스 10개 중 유일한 '전 구간' 코스이며, "
        "나머지 9개(01·04·05·06·08·10·12·14·17)는 구간 한정. "
        "이지제주올레 개정판(2022.07)의 '휠체어구간' 목록에 없는 이유는 잘라낼 구간이 없기 때문. "
        "※ 여객선 휠체어 선적 조건은 2차 안내자료 기준 — 운영사 공식 FAQ 원문 미확보"
    ),
    "sourceCheckUrl": (
        "https://easyjeju.net · https://www.jejuolle.org/trail#/road/10_1 (공식 코스정보) · "
        "https://wonderfulis.co.kr (마라도가파도정기여객선)"
    ),
    "correctionHistory": (
        "nan | FIX28: Activity 축 모순 해소 | FIX37: 난이도 오기재 정정, UNAVAILABLE→CONDITIONAL | "
        "FIX42: 공식 휠체어 코스 10개 체계 등재 — 전 구간 코스"
    ),
}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
tgt = [r for r in rows[1:] if r[ix["placeId"]] == "P884"]
if len(tgt) != 1:
    raise SystemExit(f"[FATAL] P884 행 {len(tgt)}개 — 중단")
r = tgt[0]
if r[ix["wheelchairSection"]].strip():
    raise SystemExit("[FATAL] P884 wheelchairSection 이미 값 존재 — 덮어쓰기 금지, 중단")

log = []
for col, val in P884.items():
    before = r[ix[col]]
    if before == val:
        continue
    r[ix[col]] = val
    log.append(["P884", "FIX42", col, before or "(공백)", val,
                "제주올레 공식 휠체어 코스 10개 체계 — 전 구간 코스로 등재"])

# mobilityCaveat 은 여객선 안내가 이미 들어 있으므로 앞에 전 구간 사실만 덧붙인다
cav = r[ix["mobilityCaveat"]].strip()
if not cav.startswith("가파도 4.2km"):
    newcav = ("가파도 4.2km 순환 코스는 완만한 경사로 전 구간 휠체어 통행이 가능합니다. " + cav)
    log.append(["P884", "FIX42", "mobilityCaveat", cav[:40], newcav[:60],
                "전 구간 가능 사실을 앞에 명시 — 여객선 안내는 유지"])
    r[ix["mobilityCaveat"]] = newcav

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix42_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX42 적용 완료 — {len(log)}건")
for l in log:
    print(f"  {l[2]:22s} {l[3][:26]} → {l[4][:58]}")
