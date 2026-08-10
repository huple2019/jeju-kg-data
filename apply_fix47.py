# -*- coding: utf-8 -*-
"""
FIX47 — 두리함께 2021 무장애 지도 반영

■ A. P884 올레 10-1 — wheelchairSection 을 실측 기준으로 한정

  FIX42 는 제주올레 공식 코스정보('완만한 경사, 전 구간 휠체어 이용 가능')를 근거로
  '전 구간 (상동포구~가파포구)' 4.2km 로 넣었다.
  두리함께 2021 무장애 지도는 다르게 본다.
    · 올레 10-1(빨간 실선)에 오르막 6~7도 55m, 오르막 2곳, 내리막 11도가 표시돼 있다
    · 지도에 '휠체어 올레길 종점' 이 별도 지점(6번)으로 찍혀 있다
    · 그 종점은 '오르막 6~7도 55m' 표시 바로 옆이다 — 그 경사가 종점 사유로 보인다
  → 실측 우선. '상동포구~휠체어 올레길 종점' 으로 한정한다.

  ※ 거리는 비운다. 지도에 휠체어 구간의 거리가 표기돼 있지 않다.
    4.2km 는 코스 전체 길이이므로 그대로 쓰면 틀린다. 추정하지 않는다.
  ※ 난이도는 LOW 유지 — 종점을 만든 경사가 구간 밖이므로 구간 내부는 완만하다.

■ B. P915 가파도 — 무장애 순환 코스 5.2km 등재

  올레 10-1(내륙 마을길 편도)과 별개인 해안 순환로다.
  터미널(상동포구) 출발·도착, 13개 지점, 지도상 경사 표시 없음.
  wheelchairSection 값을 '전 구간' 으로 시작시켜 서비스가 [전구간] 으로 분기하게 한다.

  ※ 13개 지점의 번호가 범례와 지도 본문에서 서로 다르다.
    범례  5 고냉이돌 / 6 풍력발전소 / 7 가파초등학교 / 11 보건진료소 / 13 상동마을
    본문  6 휠체어 올레길 종점 / 7 보건진료소 / 9 상동마을 / 10 개엄주리코지 정자
    지점 목록은 확정하지 않고 '13개 지점' 사실만 기록한다. 원본 재확인 필요.
"""
import csv, io

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
by = {r[ix["placeId"]]: r for r in rows[1:]}
log = []


def setf(pid, col, val, reason):
    r = by[pid]
    if r[ix[col]] == val:
        return
    log.append([pid, "FIX47", col, (r[ix[col]] or "(공백)")[:70], (val or "(공백)")[:70], reason])
    r[ix[col]] = val


# ───────────── A. P884 ─────────────
if not by["P884"][ix["wheelchairSection"]].startswith("전 구간"):
    raise SystemExit("[FATAL] P884 wheelchairSection 이 '전 구간' 으로 시작하지 않음 — 대상 불일치, 중단")

setf("P884", "wheelchairSection", "상동포구~휠체어 올레길 종점",
     "두리함께 2021 무장애 지도 — 올레 10-1에 휠체어 올레길 종점이 별도 표시됨")
setf("P884", "wheelchairSectionDist", "",
     "지도에 휠체어 구간 거리 미표기 — 4.2km는 코스 전체 길이이므로 사용 불가. 추정하지 않음")
setf("P884", "wheelchairCaveat",
     "종점 부근에 6~7도 오르막 55m 구간이 있습니다. 코스 전체(가파포구까지)를 이어서 가시기는 어렵습니다",
     "지도 경사 표시 반영")
setf("P884", "mobilityCaveat",
     "올레 10-1코스는 상동포구에서 '휠체어 올레길 종점'까지 휠체어로 이동하실 수 있습니다. "
     "종점 부근에 6~7도 오르막 55m 구간이 있어 코스 전체를 이어서 가시기는 어렵습니다. "
     "가파도를 한 바퀴 도시려면 해안을 따라 도는 무장애 순환 코스(5.2km)를 이용해 주세요. "
     "실제 제약은 배를 타고 내리는 과정입니다. 그 높이가 조수간만에 따라 수시로 바뀌어 계단 이용을 "
     "피하기 어렵습니다. 음력 7~13일 무렵이 접근성이 가장 좋으니 일정을 잡으실 때 참고해 주세요. "
     "전동휠체어는 무게 때문에 탑승이 어려워 수동휠체어로 바꿔 타셔야 하고, 선박 안에도 계단과 단차가 "
     "있어 이동 지원이 필요합니다. 동행자를 미리 확보해 주세요. 가파도 상동포구 선착장에는 경사로가 "
     "3군데 설치되어 있고, 선박이 접안하는 위치에 따라 계단 이용을 줄일 수 있습니다. 날씨에 따라 "
     "결항할 수 있으니 출발 전 운항 여부를 전화로 확인하시고, 승선권과 신분증은 출항 5분 전까지 "
     "준비해 주세요. 장애 정도가 심한 장애인은 50%, 심하지 않은 장애인과 국가유공자는 20% 할인이 "
     "적용됩니다. 2021~2022년 확인 기준이므로 최신 상황도 함께 확인해 주시기 바랍니다",
     "구간 한정으로 정정 + 대체 경로(순환 코스) 안내 추가")
setf("P884", "verifyNote",
     by["P884"][ix["verifyNote"]].strip() +
     " ※ FIX47: 제주올레 공식은 '전 구간 휠체어 이용 가능'이나 두리함께 2021 무장애 지도는 "
     "'휠체어 올레길 종점'을 별도 표시하고 올레 10-1 경로에 오르막 6~7도 55m·오르막 2곳·내리막 11도를 "
     "표기함. 실측을 우선해 구간 한정으로 정정. 휠체어 구간의 거리는 원본에 미표기 — 재확인 필요",
     "자료 불일치 및 실측 우선 판단 기록")
setf("P884", "correctionHistory",
     by["P884"][ix["correctionHistory"]].strip() + " | FIX47: 전 구간 → 상동포구~휠체어 올레길 종점 (실측 우선)",
     "이력")

# ───────────── B. P915 ─────────────
if by["P915"][ix["wheelchairSection"]].strip():
    raise SystemExit("[FATAL] P915 wheelchairSection 이미 값 존재 — 덮어쓰기 금지, 중단")

setf("P915", "wheelchairSection", "전 구간 순환 (터미널 출발·도착)",
     "두리함께 2021 무장애 추천 코스 — 해안 순환로, 올레 10-1과 별개 경로")
setf("P915", "wheelchairSectionDist", "5.2km", "지도 명시")
setf("P915", "wheelchairDifficulty", "LOW", "지도상 경사 표시 없음")
setf("P915", "mobilityCaveat",
     "가파도에는 휠체어로 섬을 한 바퀴 돌 수 있는 무장애 추천 코스가 있습니다. 터미널에서 출발해 "
     "해안을 따라 13개 지점을 지나 터미널로 돌아오는 5.2km 순환로이며, 지도상 경사 표시가 없는 "
     "평탄한 길입니다. 올레 10-1코스는 섬 안쪽 마을길을 지나는 별개 경로로 오르막이 있으니 "
     "휠체어로 이동하실 때는 순환 코스를 이용해 주세요. 장애인 화장실은 가파도 터미널(상동 대합실)에 "
     "있습니다. " + by["P915"][ix["mobilityCaveat"]].split("가파도는 섬 안이 대체로 평탄해 휠체어로 둘러보실 수 있고, 무장애 추천 코스가 총 5.2km 13개 지점으로 안내되어 있습니다. 장애인 화장실은 가파도 터미널(상동)에 있습니다. ")[-1],
     "무장애 순환 코스 등재 및 올레 10-1과의 구분 명시")
setf("P915", "verifyNote",
     by["P915"][ix["verifyNote"]].strip() +
     " ※ FIX47: 무장애 추천 코스 5.2km(13개 지점, 터미널 순환) 등재. 올레 10-1(4.2km 편도, 내륙 마을길)과 "
     "별개 경로임. 13개 지점의 번호가 지도 범례와 본문에서 서로 달라 지점 목록은 확정하지 않음 — 원본 재확인 필요",
     "등재 근거 및 미확정 사항 기록")
setf("P915", "correctionHistory",
     by["P915"][ix["correctionHistory"]].strip() + " | FIX47: 무장애 순환 코스 5.2km 등재",
     "이력")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix47_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX47 적용 완료 — {len(log)}건")
cur = None
for l in log:
    if l[0] != cur:
        cur = l[0]; print(f"\n[{cur}]")
    print(f"  {l[2]:24s} {l[3][:30]} → {l[4][:44]}")
