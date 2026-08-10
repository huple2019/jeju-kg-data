# -*- coding: utf-8 -*-
"""
FIX43 — 올레 1-1·7코스 등급 정정 + 10-1(가파도) 편의정보 보강

■ A. P227 올레 1-1코스 · P358 올레 7코스 — 휠체어 축 NONE 으로 정정

  두 코스는 제주올레 공식 휠체어 코스 10개 목록 밖이며, 공식 코스정보에도
  무장애 구간이 표기되지 않는다. KG 의 PARTIAL 은 코스 통행 실측이 아니라
  accessVerdictReason 에 적힌 대로 '시설접근 기준 판정 — 활동참여 개별 근거 미확보',
  즉 주차장·화장실 등 시설접근에서 파생된 값이었다.
  routeCondition 도 이를 뒷받침한다.
    · 1-1  일부 절벽/비포장 구간 접근 제한
    · 7    단차 있음 + 계단 있음
  → P503(09코스)와 동일 패턴 적용: mobility/wheelchair=NONE, activity=UNAVAILABLE, gate=N

  건드리지 않는 것:
    · elderlyAccess  보행 가능한 고령 이용자는 난이도 문제이지 통행 불가가 아니다
    · strollerAccess 유모차는 계단을 들어 넘을 수 있어 NONE 이 과하다 — 별도 판단 필요
    · disabledToilet 코스상 화장실 존재 여부는 통행 가부와 별개다

■ B. P884 올레 10-1코스(가파도) — 열린관광 무장애 편의정보 반영

  확인된 현지 편의정보: 장애인 전용주차 2대, 주출입구까지 약 220m,
  상시 개방형 출입통로(넓음), 휠체어·전동스쿠터 진입 쉬움, 장애인 화장실 있음.
  지형 보완: 인도가 따로 없는 마을 안길은 차량 통행에 주의가 필요하다.

  ※ 반드시 안내해야 할 모순 ※
    현지 편의정보는 '전동 스쿠터 사용자 진입 쉬움' 이라고 하지만,
    가파도행 여객선은 전동휠체어 선적이 불가한 것으로 안내된다.
    즉 섬 안은 전동 이동보조기구가 다닐 수 있는데 배에 실을 수 없어
    도달 자체가 막히는 구조다. 현지 정보만 보고 출발하면 항구에서 막힌다.

  ※ 출처 구분 ※
    제공된 여객선 무장애 편의정보(경사로·선내 장애인 화장실)는 '마라도' 여객선 건이다.
    운진항 출항·운항사가 겹치더라도 선박이 다르면 사양이 다르므로
    가파도행 근거로 확정하지 않고 '확인 필요' 로 표시한다.
"""
import csv, io

FIX_A = {
    "mobilityAccess": "NONE",
    "wheelchairAccess": "NONE",
    "activityAccess": "UNAVAILABLE",
    "recommendForMobility": "N",
}

REASON = {
    "P227": ("올레 1-1코스(우도) — 제주올레 공식 휠체어 코스 10개 목록 밖. "
             "일부 절벽·비포장 구간으로 휠체어 통행 불가. 여객선 승선 시 높이차·선내 계단"),
    "P358": ("올레 7코스 — 제주올레 공식 휠체어 코스 10개 목록 밖. "
             "단차와 계단이 있어 휠체어 통행 불가"),
}
CAVEAT = {
    "P227": ("우도 올레 1-1코스는 절벽과 비포장 구간이 있고 여객선 승선 시 높이차와 선내 계단이 있어 "
             "휠체어로 코스를 이용하시기는 어렵습니다. 우도 내 다른 무장애 이용 지점은 별도로 확인해 주세요"),
    "P358": ("올레 7코스는 단차와 계단이 포함되어 있어 휠체어로 코스를 이용하시기는 어렵습니다. "
             "서귀포 시내 구간의 개별 지점 접근성은 별도로 확인해 주세요"),
}

GAPADO_CAVEAT = (
    "가파도 4.2km 순환 코스는 완만한 경사로 전 구간 휠체어 통행이 가능하고, 섬 안에 장애인 전용주차 2면과 "
    "장애인 화장실이 있습니다. 다만 인도가 따로 없는 마을 안길에서는 차량 통행에 주의해 주세요. "
    "가장 중요한 제약은 가파도행 여객선입니다. 접이식 수동휠체어는 선적이 가능하나 전동휠체어는 선적이 "
    "불가한 것으로 안내됩니다. 섬 안은 전동 이동보조기구로 다니기 좋다고 안내되어 있으나 배에 실을 수 "
    "없으면 도달하실 수 없으니, 전동휠체어나 전동스쿠터를 이용하시면 출발 전 반드시 운항사에 확인해 "
    "주시기 바랍니다(마라도가파도정기여객선 운진항)"
)

GAPADO = {
    "disabledToilet": "FULL",
    "routeCondition": "단차 없음+휠체어 접근 가능+인도 없는 마을 안길 차량 주의",
    "mobilityCaveat": GAPADO_CAVEAT,
    "activityEvidence": (
        "제주올레 공식 코스정보 — 4.2km · 1~2시간 · 난이도 하 · 완만한 경사, 전 구간 휠체어 이용 가능. "
        "한국관광공사 열린관광 무장애 편의정보(가파도) — 장애인 전용주차 2대, 주출입구까지 약 220m, "
        "상시 개방형 출입통로(넓음, 휠체어·전동스쿠터 진입 쉬움), 장애인 화장실 있음. "
        "지형 보완 — 인도 없는 마을 안길 차량 통행 주의. "
        "여객선: 접이식 수동휠체어 선적 가능 / 전동휠체어 선적 불가 안내"
    ),
    "sourceCheckUrl": (
        "https://easyjeju.net · https://www.jejuolle.org/trail#/road/10_1 (공식 코스정보) · "
        "https://access.visitkorea.or.kr (열린관광 가파도 cotId=e3a53bc7) · "
        "https://www.jejudatahub.net · https://wonderfulis.co.kr (마라도가파도정기여객선)"
    ),
    "verifyNote": (
        "제주올레 공식 코스정보로 확인(2026-08) — 전 구간 휠체어 이용 가능. "
        "제주올레 공식 휠체어 코스 10개 중 유일한 '전 구간' 코스이며 나머지 9개는 구간 한정. "
        "현지 편의시설은 한국관광공사 열린관광 무장애 편의정보로 확인. "
        "※ 모순 주의: 현지는 '전동스쿠터 진입 쉬움'이나 여객선은 전동휠체어 선적 불가 — "
        "섬 안 이동은 가능하나 도달이 막히는 구조이므로 반드시 함께 안내할 것. "
        "※ 출처 구분: 제공된 여객선 무장애 편의정보(출입구 경사로·선내 장애인 화장실)는 '마라도' 여객선 건임. "
        "운진항 출항·운항사가 겹쳐도 선박이 다르면 사양이 다르므로 가파도행은 별도 확인 필요"
    ),
    "correctionHistory": (
        "nan | FIX28: Activity 축 모순 해소 | FIX37: 난이도 오기재 정정, UNAVAILABLE→CONDITIONAL | "
        "FIX42: 공식 휠체어 코스 10개 체계 등재 — 전 구간 코스 | FIX43: 열린관광 편의정보 반영, 여객선 모순 명시"
    ),
}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
by = {r[ix["placeId"]]: r for r in rows[1:]}
for pid in ("P227", "P358", "P884"):
    if pid not in by:
        raise SystemExit(f"[FATAL] {pid} 없음 — 중단")

log = []


def setf(pid, col, val, reason):
    r = by[pid]
    if r[ix[col]] == val:
        return
    log.append([pid, "FIX43", col, r[ix[col]] or "(공백)", val, reason])
    r[ix[col]] = val


# ── A. 1-1 · 7코스 ──
for pid in ("P227", "P358"):
    if by[pid][ix["wheelchairSection"]].strip():
        raise SystemExit(f"[FATAL] {pid} 에 wheelchairSection 존재 — 공식 목록 밖 전제와 모순, 중단")
    for col, val in FIX_A.items():
        setf(pid, col, val, "공식 휠체어 코스 목록 밖 + 통행 장애 명시 — 시설접근 파생 PARTIAL 정정")
    setf(pid, "accessVerdictReason",
         f"시설접근 조건부 / 활동참여 불가 — {REASON[pid]}", "판정 근거 명문화")
    setf(pid, "partialReason", f"[FIX43] {REASON[pid]}", "판정 근거")
    setf(pid, "mobilityCaveat", CAVEAT[pid], "서비스 안내 문구")
    setf(pid, "verifyNote",
         "제주올레 공식 코스정보에 무장애 구간 표기 없음(2026-08 확인). "
         "기존 PARTIAL 은 시설접근 기준에서 파생된 값으로 코스 통행 실측이 아니었음",
         "검증 근거")
    setf(pid, "correctionHistory",
         "FIX43: 시설접근 파생 PARTIAL 정정 — 휠체어 축 NONE, 활동참여 UNAVAILABLE", "이력")

# ── B. 10-1 가파도 ──
for col, val in GAPADO.items():
    setf("P884", col, val, "열린관광 무장애 편의정보 반영 및 여객선 모순 명시")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix43_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX43 적용 완료 — {len(log)}건")
cur = None
for l in log:
    if l[0] != cur:
        cur = l[0]; print(f"\n[{cur}]")
    print(f"  {l[2]:22s} {l[3][:26]} → {l[4][:56]}")
