# -*- coding: utf-8 -*-
"""
FIX44 — 부속섬 여객선 접근성 정정 (2022 실제 승선 시도 기록 반영)

근거: 서귀포신문 2022-12-21 '중증장애인 서명석의 가파도 여행을 고대하며'
      (서귀포시장애인자립생활지원센터 이도건 활동가 · 2022-10 실제 시도 기록)

기존 KG 안내의 오류:
  "접이식 수동휠체어는 선적 가능 / 전동휠체어는 선적 불가"
  → '선적 가능' 과 '혼자 탈 수 있음' 은 다르다. 실제 확인된 상황은 이렇다.
     · 전동휠체어 이용자는 수동휠체어로 갈아타야 한다
     · 배와 수면의 높이 차이로 승선 자체가 위험하다
     · 수동으로 바꿔 타도 여러 사람이 들어 올려야 승선할 수 있다
     · 부잔교와 배를 잇는 램프에 턱이 있고 선실까지 계단이 있다
     · 선내에 휠체어 전용공간이 없다
     · 섬 도착 후에도 동행자가 계속 밀어야 한다
     · 매표 단계에서 이 안내를 받지 못하는 경우가 있다
  결국 해당 사례는 가파도행을 포기했다.

  기사에 따르면 여객선이 다니는 제주 부속섬(가파도·마라도·추자도·우도) 중
  전동휠체어 이용자의 승하선과 선내 안전을 담보하는 여객선은 없다.

적용 범위 — 기사에 직접 근거가 있는 4곳만 반영한다:
  P884 올레 10-1(가파도) · P915 가파도 · P914 마라도 · P416 가파도마라도정기여객선
  우도·추자 계열 20곳은 같은 문제가 의심되나 직접 조사 기록이 아니므로 별도 판단 대상.

※ 2022년 확인 기준이다. 이후 개선되었을 수 있으므로 안내에 시점을 명시한다.
"""
import csv, io

FERRY_CORE = (
    "실제 제약은 운진항에서 배를 타는 과정에 있습니다. 2022년 확인 기준으로, 전동휠체어를 "
    "이용하시면 수동휠체어로 갈아타셔야 하고 배와 수면의 높이 차이가 있어 승선이 어렵습니다. "
    "수동휠체어로 바꿔 타셔도 부잔교와 배를 잇는 램프에 턱이 있고 선실까지 계단이 있어 여러 "
    "사람이 들어 올려야 하며, 선내에 휠체어 전용공간이 없습니다. 섬에 도착하신 뒤에도 동행자가 "
    "계속 밀어드려야 합니다. 매표소에서 이 안내를 받지 못하는 경우가 있으니, 출발 전 운항사"
    "(㈜아름다운섬나라)에 직접 확인하시고 동행자를 미리 확보해 주세요. 이후 개선되었을 수 "
    "있으니 최신 상황도 함께 확인해 주시기 바랍니다"
)

EVIDENCE = (
    "서귀포신문 2022-12-21 기획기사(서귀포시장애인자립생활지원센터, 2022-10 실제 승선 시도 기록) — "
    "운진항 가파도행에서 전동휠체어 이용자는 수동휠체어 환승 요구와 배·수면 높이차로 탑승을 포기. "
    "마라도행은 램프 턱과 선실 계단으로 직원 2인이 들어 올려 승선했고 선내 휠체어 전용공간이 없었음"
    "(교통약자의 이동편의증진법 시행규칙 별표1: 여객정원 100명당 휠체어전용공간 1개 이상). "
    "마라도 선착장은 부잔교 미설치로 하선에 3인의 도움이 필요했음. "
    "기사 기준 제주 부속섬(가파도·마라도·추자도·우도) 중 전동휠체어 승하선·선내안전을 "
    "담보하는 여객선은 없음"
)

NOTE_TAIL = (
    "※ 2022-10 시점 기록 — 이후 항만·선박 개선 여부 미확인. 재확인 필요. "
    "※ 기존 '접이식 수동휠체어 선적 가능' 안내는 '선적'과 '자력 승선'을 혼동한 것으로 FIX44에서 정정"
)

TARGETS = {
    "P884": {  # 올레 10-1코스
        "prefix": ("가파도 4.2km 순환 코스는 완만한 경사로 전 구간 휠체어 통행이 가능하고, 섬 안에 "
                   "장애인 전용주차 2면과 장애인 화장실이 있습니다. 다만 인도가 따로 없는 마을 안길에서는 "
                   "차량 통행에 주의해 주세요. "),
        "companion": "Y",
    },
    "P915": {  # 가파도
        "prefix": "가파도는 섬 안이 대체로 평탄해 휠체어로 둘러보실 수 있습니다. ",
        "companion": "Y",
    },
    "P914": {  # 마라도(마라해양도립공원)
        "prefix": ("마라도는 배에서 내리는 선착장에 부잔교가 설치되어 있지 않아 하선에도 여러 사람의 "
                   "도움이 필요합니다. "),
        "companion": "Y",
    },
    "P416": {  # 가파도 마라도 정기여객선
        "prefix": "",
        "companion": "Y",
    },
}

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
by = {r[ix["placeId"]]: r for r in rows[1:]}
for pid in TARGETS:
    if pid not in by:
        raise SystemExit(f"[FATAL] {pid} 없음 — 중단")

log = []


def setf(pid, col, val, reason):
    r = by[pid]
    if r[ix[col]] == val:
        return
    log.append([pid, "FIX44", col, (r[ix[col]] or "(공백)")[:70], val[:70], reason])
    r[ix[col]] = val


for pid, cfg in TARGETS.items():
    setf(pid, "mobilityCaveat", cfg["prefix"] + FERRY_CORE,
         "2022 실제 승선 시도 기록 반영 — '선적 가능' 표현이 자력 승선으로 오해될 소지")
    setf(pid, "companionRequired", cfg["companion"],
         "승선·선내이동·하선·섬내 이동 전 단계에서 동행자 도움 필요")
    ev = by[pid][ix["activityEvidence"]].strip()
    setf(pid, "activityEvidence", (ev + " / " if ev else "") + EVIDENCE, "1차 기록 근거 추가")
    vn = by[pid][ix["verifyNote"]].strip()
    setf(pid, "verifyNote", (vn + " " if vn else "") + NOTE_TAIL, "확인 시점·재확인 필요 명시")
    ch = by[pid][ix["correctionHistory"]].strip()
    setf(pid, "correctionHistory",
         (ch + " | " if ch else "") + "FIX44: 여객선 승하선 실태 반영, 자력 승선 오해 문구 정정", "이력")
    scu = by[pid][ix["sourceCheckUrl"]].strip()
    if "seogwipo.co.kr" not in scu:
        setf(pid, "sourceCheckUrl",
             (scu + " · " if scu else "") + "https://www.seogwipo.co.kr/news/articleView.html?idxno=215569",
             "1차 기록 출처")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix44_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX44 적용 완료 — {len(log)}건")
cur = None
for l in log:
    if l[0] != cur:
        cur = l[0]; print(f"\n[{cur}]")
    print(f"  {l[2]:22s} → {l[4][:64]}")
