# -*- coding: utf-8 -*-
"""
FIX38 — P951 세리월드 판정 범위 정정

배경:
  세리월드는 카트레이싱·승마체험·미로공원이 결합된 복합 레저시설인데,
  카트 조항 하나로 시설 전체를 activityAccess=UNAVAILABLE 처리하고 있었다.

운영사 공식 요금·이용안내(seriworld.modoo.at) 재확인 결과 조항이 둘로 나뉜다:
  · 카트   — 장애인의 경우 상황에 따라 이용 제한 가능, 탑승 거부 가능.
             2인승은 성인 보호자 동승. 임산부·노약자·주취자 이용 제한.
  · 미로공원 — 통로가 좁고 계단을 이용해야 하므로 휠체어·유모차 입장 불가.
  · 승마   — 장애인 관련 명시 없음. 확인된 것은 7세 이상·키 120cm 이상·90kg 이하.

판정:
  · activityAccess  UNAVAILABLE → CONDITIONAL
      승마가 미확인이므로 '전면 불가'를 확정할 수 없다.
  · recommendForMobility  N 유지 (근거 교체)
      3개 체험 중 2개가 휠체어 제한 명시, 승마만 미확인 — 이동축을 여는 근거가 없다.
      기존 근거였던 '카트 조항 전파'는 부정확하므로 문구를 바꾼다.
  · strollerAccess  FULL → PARTIAL
      미로공원 유모차 입장 불가 명시. 다만 카트장·승마장은 가능할 수 있다.
"""
import csv, io

P951 = {
    "activityAccess": "CONDITIONAL",

    # 게이트는 유지하되 근거를 교체한다 (값 동일, 근거 문구만 변경)
    "recommendForMobility": "N",

    "strollerAccess": "PARTIAL",

    "accessVerdictReason": (
        "시설접근 가능 / 활동참여 조건부 — 복합 레저시설. 카트는 장애인 이용 제한·탑승 거부 가능 명시, "
        "미로공원은 계단·좁은 통로로 휠체어·유모차 입장 불가 명시, 승마는 장애인 관련 안내 미확인. "
        "판정을 시설 전체가 아니라 체험별로 구분함"
    ),

    "partialReason": (
        "[FIX38] 카트 조항을 시설 전체에 전파한 기존 판정을 정정. "
        "카트·미로공원은 제한 명시, 승마는 미확인 — 전면 불가 확정 불가"
    ),

    "mobilityCaveat": (
        "체험별로 이용 조건이 다릅니다. 미로공원은 통로가 좁고 계단이 있어 휠체어와 유모차를 가지고 "
        "입장하실 수 없습니다. 카트는 장애인의 경우 안전상 이용이 제한되거나 탑승이 어려울 수 있고, "
        "임산부·고령 이용자도 제한 대상입니다. 2인승은 성인 보호자가 함께 타셔야 합니다. "
        "승마는 장애인 이용 안내가 확인되지 않았으니 예약 전 시설에 직접 문의해 주세요. "
        "장애인화장실은 이용하실 수 있습니다"
    ),

    "activityEvidence": (
        "세리월드 공식 요금·이용안내(seriworld.modoo.at) — 조항 2개 확인. "
        "① 카트: 장애인의 경우 상황에 따라 이용 제한 가능·탑승 거부 가능, 2인승 성인 보호자 동승, "
        "임산부·노약자·주취자 이용 제한, 36개월 미만 이용 불가. "
        "② 미로공원: 통로가 좁고 계단을 이용해야 하므로 휠체어·유모차 입장 불가. "
        "③ 승마: 장애인 관련 명시 없음 — 7세 이상·키 120cm 이상 단독승마, 90kg 이하 확인"
    ),

    "verifyStatus": "PARTIAL",

    "verifyNote": (
        "카트·미로공원은 운영사 공식 문구로 직접 확인(2026-08). 승마는 장애인 이용 안내 미확보 — 유선 확인 필요. "
        "※ 일부 자료의 '엘리베이터'는 세리리조트(숙박) 부대시설로 확인되므로 세리월드 편의시설 근거로 쓰지 말 것"
    ),

    "correctionHistory": "FIX21-A: 경로상 휠체어 접근 불가 | FIX38: 카트 조항 전체 전파 정정, UNAVAILABLE→CONDITIONAL",
}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
tgt = [r for r in rows[1:] if r[ix["placeId"]] == "P951"]
if len(tgt) != 1:
    raise SystemExit(f"[FATAL] P951 행 {len(tgt)}개 — 중단")
r = tgt[0]

log = []
for col, val in P951.items():
    before = r[ix[col]]
    if before == val:
        log.append(["P951", "FIX38", col, before, val, "값 유지 — 근거 문구만 교체"])
        continue
    r[ix[col]] = val
    log.append(["P951", "FIX38", col, before or "(공백)", val,
                "카트 조항 전체 전파 정정 — 체험별 판정 분리"])

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix38_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX38 적용 완료 — {len(log)}건")
for l in log:
    print(f"  {l[2]:22s} {l[3][:30]} → {l[4][:52]}")
