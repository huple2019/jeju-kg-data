# -*- coding: utf-8 -*-
"""
FIX41 — 이지제주올레 원본(2022.07 개정판) 대조 결과 반영

원본 확인 사실:
  · 휠체어 구간은 총 9개 — 01·04·05·06·08·10·12·14·17 코스
  · 09코스에는 휠체어 구간이 존재하지 않음  → FIX40 이관 정확함이 확정됨
  · 08코스 휠체어 구간 : 논짓물 ~ 대평포구 / 3.6km / 난이도 상

대조 결과 불일치 및 누락:
  ① P488 06코스 구간거리  KG 2.6km → 원본 3.3km
  ② P879 08코스  wheelchairCaveat 등 서술 근거가 P503 에 남아 있음 (FIX40 이관 누락)
  ③ P879 판정값이 UNKNOWN — 귀속이 확정됐으므로 P329(05코스)와 동일 패턴 적용
  ④ P503 09코스 잔여 서술 근거 제거 (8코스 것이므로)
"""
import csv, io

CAVEAT_08 = "자연지형 7-10도 이상 경사 6개 구간. 카페8길 유효폭 73cm. 동행자 도움 필수"

src = open("nodes_accessibility.csv", encoding="utf-8-sig").read()
rows = list(csv.reader(io.StringIO(src)))
ix = {c: i for i, c in enumerate(rows[0])}
by = {r[ix["placeId"]]: r for r in rows[1:]}
for pid in ("P488", "P879", "P503"):
    if pid not in by:
        raise SystemExit(f"[FATAL] {pid} 없음 — 중단")

log = []


def setf(pid, col, val, reason):
    r = by[pid]
    before = r[ix[col]]
    if before == val:
        return
    r[ix[col]] = val
    log.append([pid, "FIX41", col, before or "(공백)", val, reason])


# ── ① P488 06코스 구간거리 정정 ──
if by["P488"][ix["wheelchairSectionDist"]].strip() != "2.6km":
    raise SystemExit("[FATAL] P488 거리가 2.6km 가 아님 — 이미 수정됐거나 대상 불일치, 중단")
setf("P488", "wheelchairSectionDist", "3.3km",
     "원본 대조 — 이지제주올레 개정판 '구간거리 : 3.3km / 쇠소깍 ~ 보목포구'")
setf("P488", "mobilityCaveat",
     "휠체어 이용 가능 구간은 '쇠소깍~보목포구' 3.3km 구간에 한합니다(구간 난이도 중). "
     + by["P488"][ix["wheelchairCaveat"]].strip(),
     "구간거리 정정에 따른 안내 문구 재합성")
setf("P488", "correctionHistory",
     (by["P488"][ix["correctionHistory"]].strip() + " | " if by["P488"][ix["correctionHistory"]].strip() else "")
     + "FIX41: 구간거리 2.6km→3.3km (원본 대조)",
     "이력 기록")

# ── ② P879 08코스 — FIX40 에서 누락된 서술 근거 이관 ──
setf("P879", "wheelchairCaveat", CAVEAT_08, "FIX40 이관 누락분 — P503 에 남아 있던 08코스 주의사항")
setf("P879", "slopeInfo", "7~10도 이상 경사 6개 구간",
     "원본 주의사항 — 자연지형 오르막·내리막 6개 구간")
setf("P879", "evidenceType", "PUBLICATION", "근거 유형 — 이지제주올레 발간물")
setf("P879", "source",
     "이지제주올레(제주올레×관광약자접근성안내센터, 재발행 2022.07) 휠체어 구간 조사",
     "원본 출처 이관")
setf("P879", "sourceDate", "2022-07", "원본 발행 시점")

# ── ③ P879 판정 — P329(05코스)와 동일 패턴 ──
#    두 코스 모두 '전체 코스는 불가 / 실측 구간만 통행 가능 / 난이도 상' 으로 동일하다.
setf("P879", "mobilityAccess", "NONE", "코스 전체는 휠체어 통행 불가 — P329(05코스)와 동일 패턴")
setf("P879", "wheelchairAccess", "NONE", "동일")
setf("P879", "activityAccess", "CONDITIONAL", "실측 구간 한정 통행 가능 — 전면 불가 아님")
setf("P879", "recommendForMobility", "Y", "구간 보유 — 상태확인에서 구간 안내 (조건검색은 NONE 등급으로 제외)")
setf("P879", "companionRequired", "Y", "원본 명시 — 동행자 도움 필요")
setf("P879", "mobilityCaveat",
     f"휠체어 이용 가능 구간은 '논짓물~대평포구' 3.6km 구간에 한합니다(구간 난이도 상). {CAVEAT_08}",
     "구간명·거리 필수 안내 — 서비스 RETURN 대상 필드")
setf("P879", "accessVerdictReason",
     "시설접근 조건부 / 활동참여 조건부 — 08코스 전체(19.6km)는 휠체어 통행 불가하나 "
     "논짓물~대평포구 3.6km 구간은 통행 가능(난이도 상, 동행자 도움 필요)",
     "판정 근거 명문화")
setf("P879", "partialReason",
     "[FIX41] 이지제주올레 원본 대조 완료 — 08코스 휠체어 구간 확정. 구간 한정 접근",
     "판정 근거")
setf("P879", "verifyStatus", "VERIFIED", "원본 대조 완료 — PENDING 해제")
setf("P879", "verifyNote",
     "이지제주올레(2022.07 개정판) 원본 대조 완료 — 목차 및 본문에 '08코스 휠체어구간 : 논짓물 - 대평포구' 명시. "
     "원본 휠체어 구간은 총 9개(01·04·05·06·08·10·12·14·17)이며 09코스에는 구간이 없음. "
     "※ 제주올레 인터뷰(2026)에는 휠체어 구간이 10개로 언급됨 — 2022.07 이후 1개 추가 추정, 미확인",
     "검증 완료 기록")
setf("P879", "sourceCheckUrl", "https://easyjeju.net · 이지제주올레 개정판(2022.07)", "출처 갱신")
setf("P879", "correctionHistory",
     "FIX40: 휠체어 구간 이관 수신 (P503 → P879) | FIX41: 원본 대조 완료, 서술 근거 이관 및 판정 확정",
     "이력 기록")

# ── ④ P503 09코스 — 8코스 것이던 잔여 서술 근거 제거 ──
setf("P503", "wheelchairCaveat", "", "08코스 주의사항이었음 — P879 로 이관 완료")
setf("P503", "verifyNote",
     "이지제주올레(2022.07 개정판) 원본 대조 완료 — 09코스에는 휠체어 구간이 존재하지 않음. "
     "기존에 적재돼 있던 '논짓물~대평포구'는 08코스 구간이며 P879 로 이관함. "
     "코스 난이도 '상'은 제주올레 공식 분류",
     "검증 완료 — 가설이 원본으로 확정됨")
setf("P503", "verifyStatus", "VERIFIED", "원본 대조 완료")
setf("P503", "correctionHistory",
     "FIX24: 휠체어 구간 실측 적재(오귀속) | FIX35: 구간 보유 근거로 게이트 Y | "
     "FIX39: 게이트 N 원복 | FIX40: 구간을 P879 로 이관 | FIX41: 원본 대조로 오귀속 확정, 잔여 근거 제거",
     "이력 기록")

out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows)
open("nodes_accessibility.csv", "w", encoding="utf-8-sig", newline="").write(out.getvalue())

with open("fix41_change_log.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placeId", "fix", "field", "before", "after", "reason"])
    w.writerows(log)

print(f"FIX41 적용 완료 — {len(log)}건")
cur = None
for l in log:
    if l[0] != cur:
        cur = l[0]; print(f"\n[{cur}]")
    print(f"  {l[2]:22s} {l[3][:28]} → {l[4][:56]}")
