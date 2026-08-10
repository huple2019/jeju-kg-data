# -*- coding: utf-8 -*-
"""
FIX37 — 올레 코스 명명 통일 + P884 재판정

A. 명명 통일  '제주올레길N코스' → '제주올레 N코스' (7건)
   근거: KG 내 분포 제주올레 20 vs 제주올레길 7 (다수파)
         공식 고유명칭도 '제주올레' — (사)제주올레 / jejuolle.org
   대상: Place.name 및 이력 CSV의 관광지명 컬럼

B. P884 제주올레 10-1코스(가파도) 재판정
   FIX28이 '난이도 상'으로 잘못 기록하고 activityAccess=UNAVAILABLE 처리한 건을 정정.
   공식 코스 정보: 4.2km / 1~2시간 / 난이도 하 / 완만한 경사, 전 구간 휠체어 이용 가능
   실제 제약은 코스가 아니라 여객선 승하선 — 접이식 수동휠체어 선적 가능,
   전동휠체어는 선적 불가로 안내됨.
   → UNAVAILABLE(불가) 이 아니라 CONDITIONAL(조건부) 이 정확함.
"""
import csv, io

RENAME = {
    "제주올레길15-A코스": "제주올레 15-A코스",
    "제주올레길10코스":   "제주올레 10코스",
    "제주올레길8코스":    "제주올레 8코스",
    "제주올레길18코스":   "제주올레 18코스",
    "제주올레길19코스":   "제주올레 19코스",
    "제주올레길7-1코스":  "제주올레 7-1코스",
    "제주올레길10-1코스": "제주올레 10-1코스",
}

log = []

# ══════════ A. Place.name 통일 ══════════
src = open("nodes_place.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
existing = {r[ix["name"]] for r in rows[1:]}

for old, new in RENAME.items():
    if new in existing:
        raise SystemExit(f"[FATAL] 개명 충돌: '{new}' 이미 존재 — 중단")

hit = 0
for r in rows[1:]:
    old = r[ix["name"]]
    if old in RENAME:
        r[ix["name"]] = RENAME[old]
        log.append([r[ix["placeId"]], "FIX37-A", "name", old, RENAME[old],
                    "명명 통일 — KG 내 다수파(20:7) 및 공식 고유명칭 '제주올레'"])
        hit += 1
if hit != len(RENAME):
    raise SystemExit(f"[FATAL] 개명 대상 {len(RENAME)}건 중 {hit}건만 매칭 — 중단")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_place.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

# ══════════ B. P884 재판정 ══════════
FERRY = ("가파도행 여객선 승하선이 실제 제약입니다. 접이식 수동휠체어는 선적이 가능하나 "
         "전동휠체어는 선적이 불가한 것으로 안내되므로, 전동휠체어를 이용하시면 운항사에 "
         "반드시 사전 확인하시기 바랍니다(마라도가파도정기여객선 운진항). "
         "섬 안 4.2km 순환 구간은 완만하고 포장·평탄한 구간이 많아 휠체어 통행이 가능하나 "
         "일부 노면이 고르지 않아 동행자 보조를 권장합니다. 장애인화장실은 미확인 상태입니다")

P884 = {
    "activityAccess":      "CONDITIONAL",
    "accessVerdictReason": ("시설접근 가능 / 활동참여 조건부 — 올레 10-1(가파도) 4.2km 난이도 하, "
                            "완만한 경사로 전 구간 휠체어 이용 가능. 제약은 코스가 아니라 여객선 승하선"),
    "partialReason":       ("[FIX37] 올레 10-1(가파도) 4.2km 난이도 하 (FIX28의 '난이도 상' 기재 오류 정정). "
                            "여객선 승하선 조건부"),
    "mobilityCaveat":      FERRY,
    "recommendForMobility": "Y",
    "companionRequired":    "UNKNOWN",   # '권장'이지 '필수' 아님 — Y로 올리면 필수로 읽힘
    "activityEvidence":    ("제주올레 공식 코스정보 — 총 4.2km · 소요 1~2시간 · 난이도 하 · 완만한 경사로 "
                            "전 구간 휠체어 이용 가능. 운진항 대합실 장애인 주차구역·화장실 및 휠체어 접근 통로 안내. "
                            "여객선 접이식 수동휠체어 선적 가능 / 전동휠체어 선적 불가 안내"),
    "sourceCheckUrl":      ("https://easyjeju.net · https://www.jejuolle.org/trail#/road/10_1 (공식 코스정보) · "
                            "https://wonderfulis.co.kr (마라도가파도정기여객선)"),
    "verifyStatus":        "PARTIAL",
    "verifyNote":          ("코스 난이도·경사는 제주올레 공식 정보로 확인(2026-08). "
                            "여객선 휠체어 선적 조건은 2차 안내자료 기준 — 운영사 공식 FAQ 원문 미확보, 유선 확인 권장"),
    "correctionHistory":   "nan | FIX28: Activity 축 모순 해소 | FIX37: 난이도 오기재 정정, UNAVAILABLE→CONDITIONAL",
}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
tgt = [r for r in rows[1:] if r[ix["placeId"]] == "P884"]
if len(tgt) != 1:
    raise SystemExit(f"[FATAL] P884 접근성 행 {len(tgt)}개 — 중단")
r = tgt[0]
for col, val in P884.items():
    before = r[ix[col]]
    if before == val:
        continue
    r[ix[col]] = val
    log.append(["P884", "FIX37-B", col, before or "(공백)", val,
                "가파도 코스 난이도 하 확인 — 제약은 코스가 아닌 여객선 승하선"])

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

# ══════════ 이력 CSV의 관광지명도 함께 통일 ══════════
for fn, col in [("CORRECTION_LOG_MASTER.csv", "관광지명"),
                ("fix34_core_activity_exclusion_log.csv", None)]:
    txt = open(fn, encoding="utf-8-sig").read()
    n = sum(txt.count(o) for o in RENAME)
    for o, nw in RENAME.items():
        txt = txt.replace(o, nw)
    open(fn, "w", encoding="utf-8-sig", newline="").write(txt)
    print(f"  {fn}: 명칭 {n}건 치환")

with open("fix37_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"\nFIX37 적용 완료 — {len(log)}건")
for l in log:
    print(f"  {l[0]} {l[1]} {l[2]}: {l[3][:34]} → {l[4][:44]}")
