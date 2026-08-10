# -*- coding: utf-8 -*-
"""
FIX45 — 가파도 무장애 접근성 정밀화 (2021 두리함께 현장조사 반영)

근거: 두리함께(무장애여행 전문 사회적기업) 네이버블로그 2021 가파도 무장애 여행정보
      (blog.naver.com/duritrip/222519556245 — 사용자 제공 화면기록으로 확인)

2022 서귀포신문 1차 기록과 상호 확증되며, 실행 가능한 정보가 더 구체적이다.

■ 신규 확보 정보 (기존 KG 에 전혀 없던 것)
  · 조수간만 차이로 승선·하선 높이가 수시로 바뀌어 계단 이용이 불가피하다
  · 승선 높이는 만조·간조에 따라 다르며 **음력 7~13일이 접근성이 가장 좋다**
  · 전동휠체어는 '무게' 때문에 탑승이 어려워 수동휠체어로 교체 후 이용해야 한다
    (2022 기사의 '높이차' 설명과 합쳐 사유가 두 가지로 확인됨)
  · 선박 내부에도 여객선 특성상 계단과 단차가 있다
  · 가파도 상동포구 선착장에는 경사로가 3군데 설치되어 있고,
    선박 접안 위치에 따라 계단 이용을 최소화할 수 있다
  · 운항: 운진항 출발 09·10·11·12·14시(15·16시는 편도), 소요 10~15분
  · 날씨에 따라 결항할 수 있어 사전에 운항 여부를 전화로 확인해야 한다
  · 장애 정도가 심한 장애인 50%, 심하지 않은 장애인 20%, 국가유공자 20% 할인
  · 승선권과 신분증을 출항 5분 전까지 제시해야 한다
  · 장애인화장실 2곳 — 운진항 대합실, 가파도 터미널(상동)
      운진항  출입문 88cm / 출입문~대변기 120cm / 대변기~벽 30cm
      가파도  출입문 82cm / 출입문~대변기 110cm / 대변기~벽 92cm
    ※ 운진항 대변기~벽 30cm 는 휠체어 이동공간이 매우 좁다 — 실사용 경고 필요
  · 무장애 추천 코스는 총 5.2km 13개 지점 (올레 10-1 코스 4.2km 와 별개 경로)

■ 판정은 유지한다
  '이동 지원이 필요하며 각별한 주의가 필요' 이고 경사로 3군데·접안 위치에 따른
  계단 최소화가 가능하므로 '완전 불가' 가 아니다 → activityAccess=CONDITIONAL 유지.
"""
import csv, io

TIDE = ("배를 타고 내리는 높이가 조수간만에 따라 수시로 바뀌어 계단 이용을 피하기 어렵습니다. "
        "음력 7~13일 무렵이 접근성이 가장 좋으니 일정을 잡으실 때 참고해 주세요")

BOARD = ("전동휠체어는 무게 때문에 탑승이 어려워 수동휠체어로 바꿔 타셔야 하고, 선박 안에도 계단과 "
         "단차가 있어 이동 지원이 필요합니다. 동행자를 미리 확보해 주세요")

PLAN = ("날씨에 따라 결항할 수 있으니 출발 전 운항 여부를 전화로 확인하시고, 승선권과 신분증은 "
        "출항 5분 전까지 준비해 주세요. 장애 정도가 심한 장애인은 50%, 심하지 않은 장애인과 "
        "국가유공자는 20% 할인이 적용됩니다")

GAPADO_PORT = ("가파도 상동포구 선착장에는 경사로가 3군데 설치되어 있고, 선박이 접안하는 위치에 따라 "
               "계단 이용을 줄일 수 있습니다")

TARGETS = {
    "P884": (  # 올레 10-1코스
        "가파도 4.2km 순환 코스는 완만한 경사로 전 구간 휠체어 통행이 가능하고, 섬 안에 장애인 전용주차 "
        "2면과 장애인 화장실이 있습니다. 인도가 따로 없는 마을 안길에서는 차량 통행에 주의해 주세요. "
        f"실제 제약은 배를 타고 내리는 과정입니다. {TIDE}. {BOARD}. {GAPADO_PORT}. {PLAN}. "
        "2021~2022년 확인 기준이므로 최신 상황도 함께 확인해 주시기 바랍니다"
    ),
    "P915": (  # 가파도
        "가파도는 섬 안이 대체로 평탄해 휠체어로 둘러보실 수 있고, 무장애 추천 코스가 총 5.2km 13개 "
        f"지점으로 안내되어 있습니다. 장애인 화장실은 가파도 터미널(상동)에 있습니다. {TIDE}. {BOARD}. "
        f"{GAPADO_PORT}. {PLAN}. 2021~2022년 확인 기준이므로 최신 상황도 함께 확인해 주시기 바랍니다"
    ),
    "P416": (  # 가파도 마라도 정기여객선
        f"{TIDE}. {BOARD}. 운진항에서 가파도 상동포구까지는 10~15분이 걸립니다. {GAPADO_PORT}. {PLAN}. "
        "2021~2022년 확인 기준이므로 최신 상황도 함께 확인해 주시기 바랍니다"
    ),
    "P896": (  # 운진항
        f"운진항 승선장은 {TIDE}. {BOARD}. 대합실에 장애인 화장실이 있으나 대변기와 벽 사이 여유가 "
        "약 30cm로 좁아 휠체어를 돌리기 어려울 수 있습니다. 가파도 터미널 쪽 장애인 화장실이 "
        f"공간에 여유가 있습니다. {PLAN}"
    ),
}

EVIDENCE_ADD = (
    "두리함께 가파도 무장애 여행정보(2021) — 승선장은 조수간만 차이로 승선 높이가 수시로 바뀌어 "
    "계단 이용 불가피, 선박 내에도 계단·단차 존재. 음력 7~13일이 접근성 최적. "
    "전동휠체어는 무게로 탑승 곤란하여 수동휠체어 교체 필요. "
    "상동포구 선착장 경사로 3개소, 접안 위치에 따라 계단 이용 최소화 가능. "
    "장애인화장실 2개소 — 운진항 대합실(출입문 88cm/출입문~대변기 120cm/대변기~벽 30cm), "
    "가파도 터미널(82cm/110cm/92cm). 무장애 추천 코스 5.2km 13개 지점. "
    "운항 10~15분, 결항 시 사전 전화 확인 필요. 중증 장애인 50%·경증 20%·국가유공자 20% 할인"
)

NOTE_ADD = (
    "※ FIX45: 두리함께 2021 현장조사 반영 — 2022 서귀포신문 1차 기록과 상호 확증. "
    "전동휠체어 탑승 곤란 사유가 '무게'(2021)와 '배·수면 높이차'(2022) 두 가지로 확인됨. "
    "판정은 CONDITIONAL 유지 — 경사로 3개소와 접안 위치 조정으로 완전 불가는 아님"
)

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
    log.append([pid, "FIX45", col, (r[ix[col]] or "(공백)")[:60], val[:60], reason])
    r[ix[col]] = val


for pid, caveat in TARGETS.items():
    setf(pid, "mobilityCaveat", caveat, "2021 현장조사 반영 — 조수·경사로·할인·결항 확인 등 실행정보 추가")
    setf(pid, "companionRequired", "Y", "이동 지원 필요 명시")
    ev = by[pid][ix["activityEvidence"]].strip()
    if "두리함께" not in ev:
        setf(pid, "activityEvidence", (ev + " / " if ev else "") + EVIDENCE_ADD, "2021 현장조사 근거 추가")
    vn = by[pid][ix["verifyNote"]].strip()
    if "FIX45" not in vn:
        setf(pid, "verifyNote", (vn + " " if vn else "") + NOTE_ADD, "상호 확증 기록")
    scu = by[pid][ix["sourceCheckUrl"]].strip()
    if "duritrip" not in scu:
        setf(pid, "sourceCheckUrl",
             (scu + " · " if scu else "") + "https://blog.naver.com/duritrip/222519556245 (두리함께 2021)",
             "출처 추가")
    ch = by[pid][ix["correctionHistory"]].strip()
    setf(pid, "correctionHistory",
         (ch + " | " if ch else "") + "FIX45: 두리함께 2021 현장조사 반영 (조수 시점·경사로·할인·결항)", "이력")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix45_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX45 적용 완료 — {len(log)}건")
cur = None
for l in log:
    if l[0] != cur:
        cur = l[0]; print(f"\n[{cur}]")
    print(f"  {l[2]:22s} → {l[4][:62]}")
