# -*- coding: utf-8 -*-
"""
FIX35 — 올레 구간 판정 반영 (구간 보유 9코스)
FIX36 — 액티비티 3곳 장애인 이용 근거 웹 확인 반영

원칙:
  - 결측/공백 덮어쓰기 금지: 기존 값이 있으면 건드리지 않고 SKIP 로그를 남긴다.
  - 대상 placeId가 없으면 조용히 넘어가지 않고 즉시 에러를 던진다. (v3 silent-loss 재발 방지)
"""
import csv, io, sys

SRC = "nodes_accessibility.csv"
DIFF_KOR = {"MEDIUM": "중", "HIGH": "상", "LOW": "하"}

# ---- FIX35 대상: wheelchairSection 실측 보유 9개 코스 -------------------
OLLE = ["P215", "P319", "P329", "P488", "P503", "P619", "P621", "P624", "P878"]

# ---- FIX36: 웹 확인 결과 ------------------------------------------------
FIX36 = {
    "P992": {
        "activityEvidence": (
            "한국관광공사 열린관광 모두의여행 무장애 관광정보 등재 — 장애인 전용주차 2대, "
            "주출입구까지 약 40m, 부지 넓음(시설접근 근거). 만 14세 이상 이용. "
            "ATV·버기카는 이용자가 직접 운전·조작하는 구조. "
            "운영사 공식 장애인 이용제한 문구는 확인되지 않음 — 사전 문의 필수(064-738-0500)"
        ),
        "sourceCheckUrl": "https://easyjeju.net · access.visitkorea.or.kr(열린관광 등재) · daeyooland.com",
        "verifyStatus": "PARTIAL",
        "verifyNote": "시설접근은 열린관광 공식 등재로 확인. activityAccess=UNAVAILABLE은 조작 구조 기반 추론 — 운영사 명시 문구 미확보(2026-08 재확인)",
    },
    "P951": {
        "activityEvidence": (
            "세리월드 공식 요금안내(seriworld.modoo.at) — 장애인의 경우 상황에 따라 카트 이용을 "
            "제한할 수 있고 탑승을 거부할 수 있음이 명시됨. 2인승은 성인 보호자 동승 조건. "
            "임산부·노약자 이용 제한. 미로공원은 통로 폭이 좁음"
        ),
        "sourceCheckUrl": "https://easyjeju.net · https://seriworld.modoo.at/?link=9udmzefr (공식 요금·이용안내)",
        "verifyStatus": "VERIFIED",
        "verifyNote": "운영사 공식 홈페이지 명시 문구로 직접 확인(2026-08). 단 판정 범위는 카트레이싱 기준 — 승마·미로공원·유로번지는 개별 미판정",
    },
    "P944": {
        "activityEvidence": (
            "조브 신장 130cm 이상·빅조브 150cm 이상, 체중 90kg 이상 탑승 불가, 기본 2인 동승. "
            "경사면을 170~300m 굴러 내려오는 구조. "
            "운영사 공식 장애인 이용제한 문구는 확인되지 않음 — 사전 문의 필수"
        ),
        "sourceCheckUrl": "https://easyjeju.net · visitjeju.net · 예약처 공통 탑승기준(신장·체중)",
        "verifyStatus": "PARTIAL",
        "verifyNote": "탑승 신체기준(신장·체중)은 확인. activityAccess=UNAVAILABLE은 자세 유지 요구 구조 기반 추론 — 운영사 명시 문구 미확보(2026-08 재확인)",
    },
}

src = open(SRC, encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
hdr = rows[0]
ix = {c: i for i, c in enumerate(hdr)}
by_pid = {r[ix["placeId"]]: r for r in rows[1:]}

log = []


def need(pid):
    if pid not in by_pid:
        raise SystemExit(f"[FATAL] placeId {pid} 없음 — 대상 누락, 중단")
    return by_pid[pid]


# ===================== FIX35 =====================
for pid in OLLE:
    r = need(pid)
    sec = r[ix["wheelchairSection"]].strip()
    dist = r[ix["wheelchairSectionDist"]].strip()
    diff = r[ix["wheelchairDifficulty"]].strip()
    cav = r[ix["wheelchairCaveat"]].strip()
    mob = r[ix["mobilityAccess"]].strip()
    if not sec or not dist:
        raise SystemExit(f"[FATAL] {pid} 구간/거리 결측 — FIX24 적재 불완전, 중단")

    # (1) 구간 보유 코스는 recommendForMobility='Y'로 복원
    before_rec = r[ix["recommendForMobility"]]
    if before_rec != "Y":
        r[ix["recommendForMobility"]] = "Y"
        log.append([pid, "FIX35", "recommendForMobility", before_rec, "Y",
                    "실측 휠체어 구간 보유 — activityAccess=UNAVAILABLE 일괄판정에서 복원"])

    # (2) 구간명·거리를 서비스 응답 필드(mobilityCaveat)에 합성
    note = (f"휠체어 이용 가능 구간은 '{sec}' {dist} 구간에 한합니다"
            f"(구간 난이도 {DIFF_KOR.get(diff, diff)}). {cav}")
    before_cav = r[ix["mobilityCaveat"]].strip()
    if before_cav:
        log.append([pid, "FIX35", "mobilityCaveat", before_cav, "(변경없음)",
                    "기존 값 존재 — 덮어쓰기 금지 원칙에 따라 SKIP"])
    else:
        r[ix["mobilityCaveat"]] = note
        log.append([pid, "FIX35", "mobilityCaveat", "(공백)", note,
                    "구간명·거리 필수 안내 — 서비스 RETURN 절에 실리는 필드로 합성"])

    # (3) NONE 등급은 조건검색 비노출 대상임을 명시 기록
    if mob == "NONE":
        log.append([pid, "FIX35", "(노출정책)", "-", "조건검색 제외 / 상태확인만 안내",
                    "mobilityAccess=NONE + 실측구간 보유 — 코스 전체 접근 불가로 조건검색 비노출"])

# ===================== FIX36 =====================
for pid, patch in FIX36.items():
    r = need(pid)
    for col, val in patch.items():
        before = r[ix[col]].strip()
        if col in ("activityEvidence",) and before:
            log.append([pid, "FIX36", col, before, "(변경없음)", "기존 근거 존재 — SKIP"])
            continue
        r[ix[col]] = val
        log.append([pid, "FIX36", col, before or "(공백)", val, "웹 1차 출처 확인 반영(2026-08)"])

# ===================== 저장 =====================
out = io.StringIO()
csv.writer(out, lineterminator="\n").writerows(rows)
open(SRC, "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix35_36_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"적용 완료 — 변경/기록 {len(log)}건")
for l in log:
    print(" ", l[0], l[1], l[2], "→", (l[4][:70] if l[4] else ""))
