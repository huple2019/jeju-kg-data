# -*- coding: utf-8 -*-
"""
FIX39 — P503 제주올레 9코스 게이트 원복 + 구간 귀속 확인 보류 처리

배경:
  FIX35 에서 '실측 구간 보유' 를 근거로 recommendForMobility 를 N→Y 로 올렸으나,
  9코스는 군산오름·안덕계곡 등 산악 구간과 계단·급경사를 포함해
  정규 코스를 휠체어로 이어 이용하기 어렵다는 판단이 확정됨.

  recommendForMobility 의 정의는 '핵심 체험 가능 여부' 게이트다.
  (코드 주석: "잠수함은 선내 계단, 짚라인은 출발대 계단 → 매표소 접근만으로 추천 불가")
  출발점 접근 가능은 Y 의 근거가 되지 않는다. → N 으로 되돌린다.

  변경하지 않는 것:
    · activityAccess = UNAVAILABLE 유지
    · wheelchairSection / Dist / Difficulty 원본값 보존
      → '논짓물~대평포구' 가 8코스 종점 구간일 가능성이 있으나
        이지제주올레 원본 확인 전까지 데이터를 건드리지 않는다.

  단, 귀속이 불확실한 접근성 정보를 사용자에게 단정형으로 내보내면 안 되므로
  mobilityCaveat 문구만 완화한다. (상태확인 조회에서는 계속 노출되는 필드)
"""
import csv, io

CAVEAT = (
    "제주올레 9코스는 오름과 계곡을 지나는 산악 구간이 있고 계단과 급한 경사가 포함되어 있어, "
    "휠체어로 정규 코스를 이어서 이용하시기는 어렵습니다. 출발점인 대평포구까지는 접근하실 수 있습니다. "
    "조사자료에 '논짓물~대평포구' 3.6km가 통행 가능 구간으로 기록되어 있으나 해당 구간이 어느 코스에 "
    "속하는지 확인이 필요한 상태이므로, 방문 전 제주올레(064-762-2190)에 문의해 주시기 바랍니다"
)

P503 = {
    "recommendForMobility": "N",
    "mobilityCaveat": CAVEAT,
    "partialReason": (
        "[FIX39] 산악 구간·계단·급경사 포함 — 휠체어 정규 코스 연속 이용 불가. "
        "출발점(대평포구) 접근 가능은 게이트 Y 의 근거가 되지 않음(핵심 체험 게이트 정의 유지)"
    ),
    "verifyNote": (
        "코스 난이도 '상'은 제주올레 공식 분류로 확인. "
        "※ 보류: wheelchairSection '논짓물~대평포구'는 8코스(월평 아왜낭목→대평포구) 종점 구간일 "
        "가능성이 있음 — 9코스는 대평포구에서 시작. 이지제주올레(2022.07) 원본 확인 필요. "
        "확인 전까지 구간 데이터는 보존하되 사용자 안내에서는 단정하지 않음"
    ),
    "correctionHistory": (
        "FIX24: 휠체어 구간 실측 적재 | FIX35: 구간 보유 근거로 게이트 Y | "
        "FIX39: 게이트 N 원복 — 구간 보유가 코스 활동 가능을 뜻하지 않음. 구간 귀속 확인 보류"
    ),
}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
tgt = [r for r in rows[1:] if r[ix["placeId"]] == "P503"]
if len(tgt) != 1:
    raise SystemExit(f"[FATAL] P503 행 {len(tgt)}개 — 중단")
r = tgt[0]

# 보존 확인 — 원본 구간값이 살아 있어야 한다
for col in ("wheelchairSection", "wheelchairSectionDist", "wheelchairDifficulty"):
    if not r[ix[col]].strip():
        raise SystemExit(f"[FATAL] P503 {col} 결측 — 보존 대상이 이미 비어 있음, 중단")

log = []
for col, val in P503.items():
    before = r[ix[col]]
    if before == val:
        continue
    r[ix[col]] = val
    log.append(["P503", "FIX39", col, before or "(공백)", val,
                "핵심 체험 게이트 정의 유지 — 출발점 접근은 Y 근거 아님"])

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix39_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX39 적용 완료 — {len(log)}건")
for l in log:
    print(f"  {l[2]:22s} {l[3][:34]} → {l[4][:56]}")
print("\n보존 확인:", r[ix['wheelchairSection']], "/", r[ix['wheelchairSectionDist']],
      "/", r[ix['wheelchairDifficulty']], "/ activityAccess =", r[ix['activityAccess']])
