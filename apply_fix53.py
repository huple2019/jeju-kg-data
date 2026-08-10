# -*- coding: utf-8 -*-
"""
FIX53 — 거문오름 중복 노드 병합 (A안: 스키마 변경 없이)

  P554 거문오름                    → 병합 대상 (recommendable=N)
  P795 거문오름(UNESCO 세계자연유산)   → 대표 노드 유지

대표 노드를 P795로 잡는 근거:
  비짓제주 공식 레코드의 명칭·좌표(33.4569963, 126.7143064)와 일치.
  Place 우선 데이터 소스가 비짓제주 관광정보이므로 정합성 원칙상 canonical.

다만 접근성 정보는 P554 가 원본이다. 방향을 반대로 잡으면 조사 결과가 소실된다.
  P554  disabledToilet=FULL / slopeInfo=전시관 경사로·엘리베이터+탐방로 계단 / 소개문
  P795  disabledToilet=UNKNOWN / slopeInfo=UNKNOWN / note 는 메타 문구
  → P554 의 접근성을 P795 로 옮긴다.

화장실 등급은 FULL 이 아니라 PARTIAL 로 넣는다.
  비짓제주는 탐방 중 화장실 이용이 불가하니 탐방 전 미리 다녀오도록 안내한다.
  한국관광공사 무장애 정보에는 장애인 화장실이 등록돼 있다.
  즉 '탐방안내소에는 있고 탐방로 안에는 없다' 가 정확하다.
  FULL 로 두면 '전 구간 이용 가능' 으로 읽히므로 PARTIAL + 위치 명시가 맞다.
  ※ v3 에는 RouteSegment 노드가 없어 노드 분리로 표현할 수 없다.
    위치 구분은 mobilityCaveat 텍스트로 전달한다. (v4 과제)

관계 처리:
  위험패턴  P554 24개가 P795 26개에 전부 포함 — 재배선 불필요
  화재사건  P795 에만 3건 — 손대지 않음
  활동      P554 의 ACT_007(등반)은 P795 의 ACT_019(등산)과 사실상 동일 — 이관하지 않음
  → 관계 이동 없이 P554 를 추천 대상에서만 내린다. 관계 삭제도 하지 않아 이력이 보존된다.
"""
import csv, io

CAVEAT = ("화장실은 탐방안내소에 있습니다. 탐방로 안에는 화장실이 없으니 출발 전에 이용해 주세요. "
          "전시관은 경사로와 엘리베이터로 이동하실 수 있으나 탐방로에는 계단과 경사 구간이 있습니다")

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
by = {r[ix["placeId"]]: r for r in rows[1:]}
for pid in ("P554", "P795"):
    if pid not in by:
        raise SystemExit(f"[FATAL] {pid} 없음 — 중단")

# 병합 전제 확인 — P554 가 실제로 더 풍부한지
if by["P554"][ix["disabledToilet"]] != "FULL" or by["P795"][ix["disabledToilet"]] != "UNKNOWN":
    raise SystemExit("[FATAL] 화장실 값이 전제와 다름 — 이미 수정됐거나 대상 불일치, 중단")

log = []


def setf(pid, col, val, reason):
    r = by[pid]
    if r[ix[col]] == val:
        return
    log.append([pid, "FIX53", col, (r[ix[col]] or "(공백)")[:60], (val or "(공백)")[:60], reason])
    r[ix[col]] = val


# ── P795 : P554 의 접근성 흡수 ──
setf("P795", "disabledToilet", "PARTIAL",
     "탐방안내소에는 장애인화장실 있음 / 탐방로 내부에는 없음 — FULL 은 전 구간으로 오독됨")
setf("P795", "slopeInfo", by["P554"][ix["slopeInfo"]], "P554 조사값 이관")
setf("P795", "mobilityCaveat",
     (by["P795"][ix["mobilityCaveat"]].strip() + " " if by["P795"][ix["mobilityCaveat"]].strip() else "") + CAVEAT,
     "화장실 위치 구분 안내 — v3 에 RouteSegment 가 없어 텍스트로 전달")
setf("P795", "verifyNote",
     (by["P795"][ix["verifyNote"]].strip() + " " if by["P795"][ix["verifyNote"]].strip() else "") +
     "※ FIX53: P554 거문오름 중복 노드 병합 — 접근성 조사값(장애인화장실·경사)을 이관받음. "
     "화장실은 탐방안내소 한정이므로 FULL 이 아니라 PARTIAL. "
     "근거: 비짓제주(탐방 중 화장실 이용 불가 안내), 한국관광공사 무장애 정보(장애인화장실 등록)",
     "병합 근거")
setf("P795", "correctionHistory",
     (by["P795"][ix["correctionHistory"]] + " | " if by["P795"][ix["correctionHistory"]].strip() else "") +
     "FIX53: P554 병합 수신 (대표 노드)", "이력")

# ── P554 : 병합 대상 표시 ──
setf("P554", "verifyNote",
     "※ FIX53: P795 거문오름(UNESCO 세계자연유산)과 동일 장소. 좌표 430m 차이. "
     "비짓제주 공식 레코드와 일치하는 P795 를 대표 노드로 삼고 이 노드는 추천 대상에서 제외함. "
     "접근성 조사값은 P795 로 이관 완료. 관계(위험패턴 24·활동 2)는 이력 보존을 위해 남겨둠",
     "병합 이력")
setf("P554", "correctionHistory",
     (by["P554"][ix["correctionHistory"]] + " | " if by["P554"][ix["correctionHistory"]].strip() else "") +
     "FIX53: P795 로 병합 (중복 노드)", "이력")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

# ── Place : P554 추천 제외 ──
src = open("nodes_place.csv", encoding="utf-8-sig").read()
prows = list(csv.reader(io.StringIO(src)))
pix = {c: i for i, c in enumerate(prows[0])}
pby = {r[pix["placeId"]]: r for r in prows[1:]}
r = pby["P554"]
before = r[pix["recommendable"]]
r[pix["recommendable"]] = "N"
log.append(["P554", "FIX53", "recommendable", before, "N", "중복 노드 — 대표 P795 로 병합, 추천 대상에서 제외"])
bnote = r[pix["note"]]
r[pix["note"]] = (bnote.strip() + " | " if bnote.strip() else "") + \
    "[FIX53] 중복 노드 — 대표는 P795 거문오름(UNESCO 세계자연유산). 접근성 조사값은 P795 로 이관"
log.append(["P554", "FIX53", "note", bnote[:50], r[pix["note"]][:60], "병합 이력"])

# P795 에 소개문이 없으면 P554 소개문 이관
p795 = pby["P795"]
if "소개:" not in p795[pix["note"]] and "소개:" in pby["P554"][pix["note"]]:
    intro = [x for x in pby["P554"][pix["note"]].split("|") if "소개:" in x]
    if intro:
        b = p795[pix["note"]]
        p795[pix["note"]] = (b.strip() + " | " if b.strip() else "") + intro[0].strip()
        log.append(["P795", "FIX53", "note", b[:50], p795[pix["note"]][:60], "P554 소개문 이관"])

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(prows)
open("nodes_place.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix53_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX53 적용 완료 — {len(log)}건")
cur = None
for l in log:
    if l[0] != cur:
        cur = l[0]; print(f"\n[{cur}]")
    print(f"  {l[2]:20s} {l[3][:26]} → {l[4][:52]}")
