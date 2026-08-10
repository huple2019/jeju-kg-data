# -*- coding: utf-8 -*-
"""
FIX48 — P884 제주올레 10-1코스 섬·여객선 속성 결손 보완

구조는 이미 올바르다.
  · P915 가파도      = 관광지 장소 (isIsland=Y, ferryPort=운진항)
  · P884 올레 10-1   = 별도 코스 (Area)
  · 무장애 구간      = Accessibility 노드의 wheelchairSection 계열 속성

문제는 P884 에만 섬·여객선 속성이 비어 있다는 점이다.
같은 성격인 P227 올레 1-1코스(우도)는 isIsland=Y / islandName=우도 / ferryPort=성산항 /
ferryMinutes=15 / islandAccessNote 가 모두 채워져 있는데, P884 는 isIsland 가 UNKNOWN 이고
나머지가 전부 공백이다. 섬 코스인데 도달 제약이 Place 레벨에서 잡히지 않는다.

코스 전체 길이 4.2km 는 제주올레 공식 기준이 맞다.
다만 이 값이 들어갈 컬럼이 없다 — nodes_place.csv 에 코스 길이 필드가 없고
27개 올레 코스 전부 durationMin 이 비어 있다.
스키마를 임의로 바꾸지 않고 note 에 기록하며, 컬럼 신설은 별도 판단 대상으로 남긴다.

※ wheelchairSectionDist 에 4.2km 를 되돌리지 않는다.
  그 필드는 '무장애 구간의 거리'이지 '코스 전체 길이'가 아니다.
  FIX47 에서 구간을 '상동포구~휠체어 올레길 종점' 으로 한정했으므로
  전체 길이를 넣으면 구간이 코스 전체인 것처럼 읽힌다.
"""
import csv, io

PATCH = {
    "isIsland": "Y",
    "islandName": "가파도",
    "ferryPort": "운진항",
    "ferryMinutes": "15.0",
    "ferryTrips": "1일 4~5회",
    "halfDayRequired": "Y",
    "durationMin": "90",
    "islandAccessNote": "여객선 필수 — 풍랑특보 시 결항. 방문 전 운항 확인 필요",
    "note": "제주올레길10-1코스: 가파도 일주 올레길. 총 4.2km, 소요 1~2시간, 공식 난이도 하 (제주올레 공식 코스정보)",
}

src = open("nodes_place.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
tgt = [r for r in rows[1:] if r[ix["placeId"]] == "P884"]
if len(tgt) != 1:
    raise SystemExit(f"[FATAL] P884 행 {len(tgt)}개 — 중단")
r = tgt[0]

# 참조 대상(P227 우도 1-1)이 실제로 채워져 있는지 확인 — 패턴 근거
ref = [x for x in rows[1:] if x[ix["placeId"]] == "P227"][0]
for c in ("isIsland", "islandName", "ferryPort", "ferryMinutes"):
    if not ref[ix[c]].strip():
        raise SystemExit(f"[FATAL] 참조 P227 의 {c} 가 비어 있음 — 패턴 전제 붕괴, 중단")

log = []
for col, val in PATCH.items():
    before = r[ix[col]]
    if before == val:
        continue
    r[ix[col]] = val
    log.append(["P884", "FIX48", col, before or "(공백)", val,
                "섬 코스인데 여객선 속성 결손 — P227 올레 1-1(우도)과 동일 패턴 적용"])

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_place.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix48_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX48 적용 완료 — {len(log)}건 (nodes_place.csv)")
for l in log:
    print(f"  {l[2]:20s} {l[3][:26]} → {l[4][:56]}")
