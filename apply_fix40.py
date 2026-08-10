# -*- coding: utf-8 -*-
"""
FIX40 — 휠체어 구간 '논짓물~대평포구' 귀속 이관 (P503 → P879)

가설:
  '논짓물~대평포구'는 제주올레 8코스(월평 아왜낭목 → 대평포구)의 종점 구간으로 보인다.
  9코스는 대평포구에서 시작하므로 이 구간이 9코스에 속할 수 없다.

  ※ 이지제주올레(2022.07) 원본은 아직 대조하지 않았다. 노선 지식에서 역산한 가설이다.
    제주올레 인터뷰 답변에 '휠체어 구간 10개'로 나오는데 KG 는 이관 후에도 9개다.
    원본 대조 시 이 숫자를 기준으로 삼을 것.

적용 범위 — 구간 데이터만 옮기고 판정값은 열지 않는다:
  · P503  wheelchairSection / Dist / Difficulty 제거
  · P879  동일 3개 필드에 이관
  · P879  wheelchairAccess · activityAccess · mobilityAccess 는 UNKNOWN 유지

  판정을 열지 않는 이유 두 가지.
  ① FIX39 에서 '구간 보유가 코스 활동 가능을 뜻하지 않는다'로 확정했다.
     같은 구간을 옮기면서 8코스에 CONDITIONAL·Y 를 주면 정반대 기준이 된다.
  ② 스키마 원칙상 UNKNOWN 은 '불가'가 아니라 '미조사'다.
     미검증 가설로 UNKNOWN 을 확정값으로 바꾸면 위험 방향이 반대다.
"""
import csv, io

SEC = {"wheelchairSection": "논짓물~대평포구",
       "wheelchairSectionDist": "3.6km",
       "wheelchairDifficulty": "HIGH"}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
by = {}
for r in rows[1:]:
    by[r[ix["placeId"]]] = r

for pid in ("P503", "P879"):
    if pid not in by:
        raise SystemExit(f"[FATAL] {pid} 없음 — 중단")

src_row, dst_row = by["P503"], by["P879"]

# 이관 전 원본값 일치 확인 — 다르면 대상이 바뀐 것이므로 중단
for col, expect in SEC.items():
    actual = src_row[ix[col]].strip()
    if actual != expect:
        raise SystemExit(f"[FATAL] P503 {col} = '{actual}' (기대 '{expect}') — 중단")

# 덮어쓰기 방지 — P879 에 이미 구간이 있으면 중단
for col in SEC:
    if dst_row[ix[col]].strip():
        raise SystemExit(f"[FATAL] P879 {col} 이미 값 존재 — 덮어쓰기 금지, 중단")

log = []

# ── P503 : 구간 제거 ──
for col in SEC:
    log.append(["P503", "FIX40", col, src_row[ix[col]], "(제거)",
                "8코스 종점 구간으로 판단 — P879 로 이관"])
    src_row[ix[col]] = ""

src_row[ix["mobilityCaveat"]] = (
    "제주올레 9코스는 오름과 계곡을 지나는 산악 구간이 있고 계단과 급한 경사가 포함되어 있어, "
    "휠체어로 코스를 이용하시기는 어렵습니다. 출발점인 대평포구까지는 접근하실 수 있습니다"
)
src_row[ix["correctionHistory"]] = (
    "FIX24: 휠체어 구간 실측 적재 | FIX35: 구간 보유 근거로 게이트 Y | "
    "FIX39: 게이트 N 원복 | FIX40: 구간 '논짓물~대평포구' 를 8코스(P879)로 이관"
)
src_row[ix["verifyNote"]] = (
    "코스 난이도 '상'은 제주올레 공식 분류로 확인. "
    "FIX40 에서 휠체어 구간을 8코스로 이관 — 이지제주올레(2022.07) 원본 대조 미완료"
)
log.append(["P503", "FIX40", "mobilityCaveat", "(구간 언급 포함)", "(구간 언급 제거)",
            "구간 이관에 따라 안내 문구 정리"])

# ── P879 : 구간 이관 (판정값은 열지 않음) ──
for col, val in SEC.items():
    log.append(["P879", "FIX40", col, "(공백)", val, "P503 에서 이관 — 8코스 종점 구간"])
    dst_row[ix[col]] = val

dst_row[ix["mobilityCaveat"]] = (
    "조사자료에 '논짓물~대평포구' 3.6km가 휠체어 통행 가능 구간으로 기록되어 있으나, "
    "해당 구간이 어느 코스에 속하는지 확인이 필요한 상태입니다. "
    "코스 전체의 접근성은 아직 조사되지 않았으니 방문 전 제주올레(064-762-2190)에 문의해 주시기 바랍니다"
)
dst_row[ix["verifyStatus"]] = "PENDING"
dst_row[ix["verifyNote"]] = (
    "※ 미검증: 휠체어 구간 '논짓물~대평포구'를 P503(9코스)에서 이관. "
    "9코스는 대평포구에서 시작하므로 8코스 종점 구간으로 판단했으나 "
    "이지제주올레(2022.07) 원본은 대조하지 않음. "
    "판정값(wheelchairAccess·activityAccess)은 UNKNOWN 유지 — 구간 보유가 코스 활동 가능을 뜻하지 않음(FIX39 원칙). "
    "대조 기준: 제주올레 공식 휠체어 구간은 10개, KG 는 9개"
)
dst_row[ix["correctionHistory"]] = "FIX40: 휠체어 구간 이관 수신 (P503 → P879), 귀속 미검증"
for col, note in [("verifyStatus", "미검증 상태 명시"),
                  ("mobilityCaveat", "단정 회피 문구"),
                  ("correctionHistory", "이관 이력")]:
    log.append(["P879", "FIX40", col, "(변경)", dst_row[ix[col]][:60], note])

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix40_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX40 적용 완료 — {len(log)}건\n")
for pid, lbl in (("P503", "9코스"), ("P879", "8코스")):
    r = by[pid]
    print(f"{pid} {lbl}: section='{r[ix['wheelchairSection']]}' "
          f"mob={r[ix['mobilityAccess']]} wheel={r[ix['wheelchairAccess']]} "
          f"act={r[ix['activityAccess']]} gate={r[ix['recommendForMobility']]} "
          f"verify={r[ix['verifyStatus']]}")
