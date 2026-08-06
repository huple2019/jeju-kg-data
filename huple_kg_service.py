"""
huple_kg_service.py — 휴플 KG 기반 안전관광 추천 서비스 코어

역할
    KG 조회 → 컨텍스트 생성 → LLM 프롬프트 합성 → 응답 안전 검증

LLM 무관 설계
    `call_llm` 을 교체하면 어떤 모델에도 붙습니다.
    (자체 서비스 / OpenAI / Anthropic / ETRI AX 등)
    KG 조회·컨텍스트·검증 로직은 LLM이 바뀌어도 그대로 씁니다.

설계 원칙
    1. KG 조회 로직을 함수 단위로 분리한다.
       → 추후 Tool Registry가 열리면 같은 함수를 MCP 도구로 노출만 하면 된다.
    2. 안전 안내 문구(advisoryMessage)는 LLM이 재작성하지 못하게 하고,
       재작성되더라도 응답 검증에서 걸러낸다.
    3. 20B 소형 모델이므로 컨텍스트를 최소화한다. (상위 N곳, 필요한 필드만)

환경변수
    LLM_BASE_URL    자체 서비스 LLM 엔드포인트
    LLM_API_KEY     LLM 인증 키 (코드/저장소에 하드코딩 금지)
    NEO4J_URI       neo4j+s://xxxx.databases.neo4j.io
    NEO4J_USER      neo4j
    NEO4J_PASSWORD  Aura 비밀번호
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from typing import Any

import requests
from neo4j import GraphDatabase

# ───────────────────────────────────────────────────────────────
# 설정
# ───────────────────────────────────────────────────────────────
NEO4J_URI = os.environ["NEO4J_URI"]
NEO4J_AUTH = (os.environ["NEO4J_USER"], os.environ["NEO4J_PASSWORD"])

# 컨텍스트 예산 — 소형 모델이므로 좁게 잡는다
MAX_PLACES = 5

# 사용자 응답에 절대 나와서는 안 되는 표현
# (프로젝트 원칙: 사망/부상 건수를 노출하지 않고 행동 지침만 전달)
FORBIDDEN = re.compile(r"사망|숨진|사상자|치사|익사|\d+\s*명이?\s*(?:숨|사망|다)")


# ───────────────────────────────────────────────────────────────
# 0. 질의 해석 — 모호하면 되묻는다 (Clarification)
#
#    "장애인"은 4축(이동·시각·청각·발달) 중 어느 것인지 특정되지 않습니다.
#    추측해서 답하면 엉뚱한 정보를 주게 되므로 되묻는 것이 원칙입니다.
#    시점도 마찬가지입니다. 계절이 판정을 바꾸므로 언제 가는지 알아야 합니다.
# ───────────────────────────────────────────────────────────────
PROFILE_KEYWORDS = {
    "VP_WHEEL":    ["휠체어", "전동휠체어", "수동휠체어", "휠체어석"],
    "VP_MOBILITY": ["보행", "목발", "지팡이", "다리가 불편", "걷기 힘", "거동이 불편"],
    "VP_VISUAL":   ["시각장애", "저시력", "앞이 안 보", "시각 장애", "안내견", "점자"],
    "VP_HEARING":  ["청각장애", "난청", "귀가 안", "청각 장애", "수어", "보청기"],
    "VP_DEVELOP":  ["발달장애", "지적장애", "자폐", "발달 장애"],
    "VP_OLDER":    ["어르신", "고령", "노인", "연세"],
    "VP_INFANT":   ["유모차", "아기", "영유아", "아이와"],
}
# 어느 축인지 특정되지 않는 표현
AMBIGUOUS_TERMS = ["장애인", "장애가", "몸이 불편", "거동", "교통약자", "관광약자", "무장애"]

PROFILE_LABEL = {
    "VP_WHEEL":    "휠체어 이용",
    "VP_MOBILITY": "보행이 불편(목발·지팡이 등)",
    "VP_VISUAL":   "시각장애",
    "VP_HEARING":  "청각장애",
    "VP_DEVELOP":  "발달·지적장애",
    "VP_OLDER":    "고령·어르신",
    "VP_INFANT":   "유모차·영유아 동반",
}

MONTH_PAT = re.compile(r"(\d{1,2})\s*월")
SEASON_PAT = {"봄": 4, "여름": 8, "가을": 10, "겨울": 1,
              "장마": 7, "휴가철": 8, "성수기": 8, "연휴": None}


@dataclass
class Clarification:
    """되물어야 할 때 반환한다. 서비스는 이를 선택지로 표시한다."""
    field: str                 # 'profile' | 'month' | 'purpose'
    question: str
    options: list[tuple[str, str]]   # (값, 표시문구)


def resolve_profile(question: str) -> tuple[str | None, Clarification | None]:
    """질문에서 방문자 유형을 판별한다. 모호하면 되묻는다."""
    for pid, kws in PROFILE_KEYWORDS.items():
        if any(k in question for k in kws):
            return pid, None
    if any(t in question for t in AMBIGUOUS_TERMS):
        return None, Clarification(
            field="profile",
            question="어떤 도움이 필요하신지 알려주시면 더 정확히 안내해 드릴 수 있습니다.",
            options=[(k, v) for k, v in PROFILE_LABEL.items()],
        )
    return None, None          # 유형 언급 없음 → 일반 추천


def resolve_month(question: str, today_month: int | None = None
                  ) -> tuple[int | None, Clarification | None]:
    """방문 시점을 판별한다. 계절이 판정을 바꾸므로 모르면 되묻는다."""
    m = MONTH_PAT.search(question)
    if m:
        v = int(m.group(1))
        if 1 <= v <= 12:
            return v, None
    for word, mon in SEASON_PAT.items():
        if word in question and mon:
            return mon, None
    if any(w in question for w in ["오늘", "지금", "내일", "이번 주", "당장"]):
        return today_month, None
    return None, Clarification(
        field="month",
        question="언제 방문하실 예정인가요? 계절에 따라 안내가 달라집니다.",
        options=[("3", "봄 (3~5월)"), ("8", "여름 (6~8월)"),
                 ("10", "가을 (9~11월)"), ("1", "겨울 (12~2월)")],
    )


# ── 축별로 어떤 데이터가 얼마나 있는지 (되물을 때 함께 안내) ────
AXIS_COVERAGE = {
    "VP_WHEEL": "이동 접근성은 전 관광지에 조사되어 있습니다",
    "VP_MOBILITY": "이동 접근성은 전 관광지에 조사되어 있습니다",
    "VP_VISUAL": "시각 접근성 정보는 24곳에만 확보되어 있습니다",
    "VP_HEARING": "청각 접근성 정보는 25곳에만 확보되어 있습니다",
    "VP_DEVELOP": "발달 접근성 정보는 9곳에만 확보되어 있습니다",
    "VP_OLDER": "고령층 접근성은 전 관광지에 조사되어 있습니다",
    "VP_INFANT": "유모차 접근성은 전 관광지에 조사되어 있습니다",
}


# ───────────────────────────────────────────────────────────────
# 1. KG 조회 — 추후 MCP 도구로 그대로 승격 가능한 단위
# ───────────────────────────────────────────────────────────────
_driver = GraphDatabase.driver(NEO4J_URI, auth=NEO4J_AUTH)


def _run(cypher: str, **params) -> list[dict]:
    with _driver.session() as s:
        return [r.data() for r in s.run(cypher, **params)]


# --- 유형 1: 조건 검색 (Condition-search) ----------------------
CYPHER_CONDITION = """
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE p.recommendable = 'Y'
  AND ($month IS NULL OR p.eventMonthStart IS NULL
       OR ($month >= p.eventMonthStart AND $month <= p.eventMonthEnd))
  AND ($category IS NULL OR p.categoryMain = $category)
  // 숙박·교통시설은 '관광지 추천' 대상이 아니다.
  // 호텔·공항은 접근성 등급이 높게 나오지만 여행 목적지가 아니므로
  // $includeLodging=true 로 명시할 때만 포함한다.
  AND ($includeLodging OR NOT p.categoryMain IN ['숙박시설','교통시설'])
WITH p, ac,
     CASE $profile
       WHEN 'VP_WHEEL'    THEN ac.wheelchairAccess
       WHEN 'VP_MOBILITY' THEN ac.mobilityAccess
       WHEN 'VP_INFANT'   THEN ac.strollerAccess
       WHEN 'VP_OLDER'    THEN ac.elderlyAccess
       WHEN 'VP_VISUAL'   THEN ac.visualAccess
       WHEN 'VP_HEARING'  THEN ac.hearingAccess
       WHEN 'VP_DEVELOP'  THEN ac.cognitiveAccess
       ELSE ac.mobilityAccess END AS grade
WHERE $profile IS NULL OR grade IN
      CASE WHEN $strict THEN ['FULL'] ELSE ['FULL','PARTIAL'] END
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
WHERE (adv.peakSeason = '' OR adv.peakSeason = $season)
RETURN p.name AS name, p.categoryMid AS category, grade AS accessGrade,
       ac.facilityAccess AS facility, ac.activityAccess AS activity,
       ac.companionRequired AS companion, ac.assistLevel AS assistLevel,
       ac.beachAccessRoute AS beachRoute, ac.beachEntryNote AS beachNote,
       ac.waterEntryNote AS waterNote,
       ac.disabledToilet AS toilet, ac.mobilityCaveat AS caveat,
       ac.verifyStatus AS verified,
       coalesce(p.directRiskScore, 0.0) AS directRisk,
       p.ambientRiskLevel AS ambientLevel, p.ambientNote AS ambientNote,
       p.swimmingRestriction AS restriction, p.harborType AS harborType,
       p.restrictionEffectiveDate AS restrictionDate,
       adv.advisoryMessage AS advisory,
       p.openHours AS hours, p.feeGeneral AS fee
ORDER BY (grade='FULL') DESC, (ac.verifyStatus='VERIFIED') DESC, directRisk ASC
LIMIT $limit
"""


# --- 유형 2: 근처 검색 (Anchor-nearby) -------------------------
CYPHER_NEARBY = """
MATCH (anchor:Place {name: $anchor})
MATCH (p:Place)-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
WHERE p.recommendable = 'Y' AND p <> anchor
  AND point.distance(p.location, anchor.location) <= $radiusM
WITH p, ac, point.distance(p.location, anchor.location) AS dist
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
RETURN p.name AS name, p.categoryMid AS category,
       round(dist) AS distanceM,
       ac.mobilityAccess AS accessGrade, ac.mobilityCaveat AS caveat,
       coalesce(p.directRiskScore, 0.0) AS directRisk,
       p.ambientRiskLevel AS ambientLevel,
       adv.advisoryMessage AS advisory
ORDER BY dist ASC
LIMIT $limit
"""


# --- 유형 3: 상태 확인 (Status-check) --------------------------
CYPHER_STATUS = """
MATCH (p:Place {name: $name})-[:HAS_ACCESSIBILITY]->(ac:Accessibility)
OPTIONAL MATCH (p)-[:HAS_ADVISORY]->(adv:PlaceAdvisory)
OPTIONAL MATCH (p)-[:IS_DESIGNATED_HARBOR]->(h:DesignatedHarbor)
RETURN p.name AS name, p.openHours AS hours, p.closedDays AS closed,
       p.feeGeneral AS fee, p.feeDisabled AS feeDisabled,
       p.recommendable AS recommendable,
       p.recommendExcludeReason AS excludeReason,
       ac.mobilityAccess AS mobility, ac.visualAccess AS visual,
       ac.hearingAccess AS hearing, ac.cognitiveAccess AS cognitive,
       ac.facilityAccess AS facility, ac.activityAccess AS activity,
       ac.companionRequired AS companion, ac.assistLevel AS assistLevel,
       ac.disabledToilet AS toilet, ac.mobilityCaveat AS caveat,
       ac.verifyStatus AS verified, ac.source AS source,
       p.swimmingRestriction AS restriction, h.harborType AS harborType,
       p.restrictionEffectiveDate AS restrictionDate,
       adv.advisoryMessage AS advisory
"""


# --- 실시간 기상 위험 판정 -------------------------------------
CYPHER_WEATHER_RISK = """
MATCH (p:Place {name: $name})
MATCH (e:EnvironmentAxis)-[t:TRIGGERS]->(r:RiskPattern)-[:APPLIES_TO]->(p)
WHERE (e.envId = 'ENV_WIND_SPEED'  AND $windSpeed  >= toFloat(r.thresholdMin))
   OR (e.envId = 'ENV_RAIN_AMOUNT' AND $rainMmH    >= toFloat(r.thresholdMin))
   OR (e.envId = 'ENV_VISIBILITY'  AND $visibility <  1000)
OPTIONAL MATCH (r)-[:RESULTS_IN]->(act:RecommendationAction)
RETURN DISTINCT r.name AS risk, r.riskLevel AS level,
       collect(DISTINCT act.action_name) AS actions
"""


def search_by_condition(profile=None, month=None, season=None, category=None,
                        strict=False, include_lodging=False, limit=MAX_PLACES):
    """include_lodging: 숙소/공항을 결과에 포함할지. 기본은 제외."""
    return _run(CYPHER_CONDITION, profile=profile, month=month,
                season=season or "", category=category, strict=strict,
                includeLodging=include_lodging, limit=limit)


def search_nearby(anchor: str, radius_m: int = 5000, limit: int = MAX_PLACES):
    return _run(CYPHER_NEARBY, anchor=anchor, radiusM=radius_m, limit=limit)


def check_status(name: str):
    rows = _run(CYPHER_STATUS, name=name)
    return rows[0] if rows else None


def weather_risk(name: str, wind=0.0, rain=0.0, visibility=10000):
    return _run(CYPHER_WEATHER_RISK, name=name, windSpeed=wind,
                rainMmH=rain, visibility=visibility)


# ───────────────────────────────────────────────────────────────
# 2. 컨텍스트 빌더 — KG 결과를 프롬프트용 문자열로
# ───────────────────────────────────────────────────────────────
GRADE_KR = {"FULL": "완전 이용 가능", "PARTIAL": "부분 이용 가능",
            "NONE": "이용 불가", "UNKNOWN": "정보 미확보"}
AVAIL_KR = {"AVAILABLE": "가능", "CONDITIONAL": "조건부", "UNAVAILABLE": "불가",
            "UNKNOWN": "미확인"}


@dataclass
class PlaceContext:
    """LLM에 전달할 장소 1건. 내부 근거 필드는 절대 포함하지 않는다."""
    name: str
    lines: list[str] = field(default_factory=list)
    verbatim: list[str] = field(default_factory=list)  # 원문 유지 필수 문구

    def render(self) -> str:
        body = "\n".join(f"  - {x}" for x in self.lines)
        return f"■ {self.name}\n{body}"


def build_place_context(row: dict) -> PlaceContext:
    c = PlaceContext(name=row.get("name", ""))
    add = c.lines.append

    if row.get("category"):
        add(f"유형: {row['category']}")
    if row.get("distanceM") is not None:
        add(f"거리: 약 {int(row['distanceM'])}m")

    g = row.get("accessGrade") or row.get("mobility")
    if g:
        add(f"접근성: {GRADE_KR.get(g, g)}"
            + (f" (검증완료)" if row.get("verified") == "VERIFIED" else ""))

    # 시설/활동 분리는 오안내 방지에 중요하므로 다를 때만 명시
    fa, aa = row.get("facility"), row.get("activity")
    if fa and aa and fa != aa:
        add(f"시설 이용 {AVAIL_KR.get(fa, fa)} / 활동 참여 {AVAIL_KR.get(aa, aa)}")
        # 활동 참여 근거가 없으면 '가능'으로 오해되지 않도록 명시한다.
        # (예: 온천은 시설 접근이 되어도 입욕에 보조·이동전이가 필요할 수 있음)
        if aa == "UNKNOWN":
            add("[확인필요] 활동 참여 가능 여부는 확인되지 않았습니다. "
                "보조 인력이 필요할 수 있으니 시설에 미리 문의해 주세요")
        elif aa == "CONDITIONAL" and row.get("companion") == "Y":
            # 시설이 공식적으로 동반을 요구한 경우 — 반드시 전달해야 한다
            note = row.get("assistLevel") or "동행자의 도움이 필요합니다"
            add(f"[동반필요] {note}")
            c.verbatim.append(note)

    if row.get("toilet") in ("FULL", "PARTIAL"):
        add("장애인화장실 있음")
    elif row.get("toilet") == "NONE":
        add("장애인화장실 없음")

    if row.get("hours"):
        add(f"운영시간: {row['hours']}")
    if row.get("fee"):
        add(f"요금: {row['fee']}")

    # ── 안전 정보 (원문 유지 대상) ──────────────────────
    # ── 해변 특화 안내 ────────────────────────────────
    #   모래사장 이동과 입수는 접근성 등급과 별개 문제입니다.
    if row.get("beachNote"):
        add(f"[모래사장] {row['beachNote']}")
        c.verbatim.append(row["beachNote"])
    if row.get("waterNote"):
        add(f"[입수] {row['waterNote']}")
        c.verbatim.append(row["waterNote"])

    if row.get("caveat"):
        add(f"[주의] {row['caveat']}")
        c.verbatim.append(row["caveat"])
    if row.get("advisory"):
        add(f"[안전안내] {row['advisory']}")
        c.verbatim.append(row["advisory"])
    if row.get("restriction") == "PROHIBITED_FROM_2027":
        txt = (f"{row.get('harborType','어항구역')}으로 지정되어 "
               f"{row.get('restrictionDate','2027-04-22')}부터 물놀이·다이빙이 금지됩니다")
        add(f"[법적제한] {txt}")
        c.verbatim.append(txt)
    # 주변 사고는 등급만 노출한다.
    #   ambientNote 에는 "연평균 N건" 같은 수치가 들어 있으나,
    #   1km 집계와 읍면동 집계는 면적이 달라 수치 비교가 불가하고
    #   숫자 자체가 불안을 키우므로 정성 표현으로만 전달한다.
    if row.get("ambientLevel") == "HIGH":
        add("[주변] 주변 지역에 안전사고가 잦은 편입니다. 이동 중 주의해 주세요")
    elif row.get("ambientLevel") == "MEDIUM":
        add("[주변] 주변 지역에 안전사고 이력이 있습니다")

    return c


def build_context_block(rows: list[dict]) -> tuple[str, list[str]]:
    """(컨텍스트 문자열, 원문유지 문구 목록) 반환"""
    ctxs = [build_place_context(r) for r in rows]
    text = "\n\n".join(c.render() for c in ctxs)
    verbatim = [v for c in ctxs for v in c.verbatim]
    return text, verbatim


# ───────────────────────────────────────────────────────────────
# 2-1. 기상 안내 — 관측값을 사람이 읽을 문장으로
#
#   임계값은 KG의 rels_environment_risk.csv 와 동일하게 유지합니다.
#   관측값이 없으면 "위험 없음"이 아니라 "확인 불가"로 처리합니다.
# ───────────────────────────────────────────────────────────────
def weather_notice(obs: dict | None, outdoor: bool = True) -> tuple[str, list[str]]:
    """
    obs 예: {"airTemp":35.1,"windSpeed":16.0,"rainMmH":0.0,
             "visibility":3000,"waveHeight":1.2,"observedAt":"2026-08-05 14:00"}
    반환: (안내문, 원문유지 대상)
    """
    if not obs:
        return ("[기상] 현재 기상 정보를 확인하지 못했습니다. "
                "방문 전 기상청 예보를 직접 확인해 주세요"), []
    lines, keep = [], []
    t   = obs.get("airTemp")
    w   = obs.get("windSpeed")
    r   = obs.get("rainMmH")
    vis = obs.get("visibility")
    wave= obs.get("waveHeight")

    cur = []
    if t is not None:   cur.append(f"기온 {t}℃")
    if w is not None:   cur.append(f"풍속 {w}m/s")
    if r:               cur.append(f"시간당 강수 {r}mm")
    if vis is not None: cur.append(f"시정 {int(vis)}m")
    if wave is not None:cur.append(f"파고 {wave}m")
    when = obs.get("observedAt", "")
    if cur:
        lines.append(f"[현재 기상{' · ' + when if when else ''}] " + ", ".join(cur))

    # 임계 판정 — KG 규칙과 동일 기준
    if t is not None and outdoor:
        if t >= 35:
            m = ("폭염 수준입니다. 야외 활동을 자제하시고, 부득이하면 "
                 "그늘과 실내를 오가며 수분을 자주 섭취해 주세요")
            lines.append(f"[주의] {m}"); keep.append(m)
        elif t >= 33:
            m = "기온이 높습니다. 한낮(11~16시) 야외 활동은 피해 주세요"
            lines.append(f"[주의] {m}"); keep.append(m)
        elif t <= -3:
            m = "한파 수준입니다. 노출 부위를 최소화하고 결빙 구간에 유의해 주세요"
            lines.append(f"[주의] {m}"); keep.append(m)
    if w is not None and outdoor:
        if w >= 14:
            m = ("강풍특보 수준입니다. 해안·오름·전망대 등 노출 구간 방문을 "
                 "미루시기 바랍니다")
            lines.append(f"[경고] {m}"); keep.append(m)
        elif w >= 10:
            m = "바람이 강합니다. 해안과 능선 노출 구간은 피해 주세요"
            lines.append(f"[주의] {m}"); keep.append(m)
    if r is not None and r >= 20:
        m = "호우 수준입니다. 계곡·하천 주변은 접근하지 마십시오"
        lines.append(f"[경고] {m}"); keep.append(m)
    elif r is not None and r >= 10:
        m = "비가 내리고 있습니다. 노면이 미끄러우니 이동에 주의해 주세요"
        lines.append(f"[주의] {m}"); keep.append(m)
    if vis is not None and vis < 200:
        m = "짙은 안개로 시야 확보가 어렵습니다. 이동을 자제하십시오"
        lines.append(f"[경고] {m}"); keep.append(m)
    elif vis is not None and vis < 1000:
        m = "안개가 끼어 있습니다. 운전 시 감속하고 차간 거리를 넓혀 주세요"
        lines.append(f"[주의] {m}"); keep.append(m)
    if wave is not None and wave >= 2.0:
        m = "파고가 높습니다. 갯바위·방파제 접근을 삼가 주세요"
        lines.append(f"[경고] {m}"); keep.append(m)

    if len(lines) <= 1:
        lines.append("[기상] 현재 특별한 기상 위험은 확인되지 않았으나, "
                     "제주는 날씨 변화가 빠르니 출발 전 다시 확인해 주세요")
    return "\n".join(lines), keep


# ───────────────────────────────────────────────────────────────
# 3. 프롬프트 합성
#    input이 단일 문자열이므로 지시사항을 여기에 함께 넣는다.
# ───────────────────────────────────────────────────────────────
INSTRUCTION = """다음은 제주 안전관광 지식그래프에서 조회한 검증된 정보입니다.

[작성 규칙]
1. 아래 제공된 정보만 사용하고, 없는 사실을 추측하거나 지어내지 마십시오.
2. [주의] [안전안내] [법적제한] 으로 표시된 문장은 반드시 원문 그대로 인용하고
   요약하거나 바꿔 쓰지 마십시오. 안전에 직결되는 문구입니다.
3. 사고 건수, 사망자 수 등 수치를 언급하지 마십시오. 제공된 문구에도 없습니다.
4. 접근성이 "정보 미확보"인 항목은 "이용 불가"가 아니라 "확인이 필요합니다"로
   안내하십시오.
5. [확인필요] 표시가 있으면 "이용 가능"이라고 단정하지 말고, 반드시
   사전 문의가 필요하다는 점을 함께 안내하십시오.
6. [현재 기상] 정보가 있으면 답변에 반드시 포함하고, [주의]·[경고] 문구는
   원문 그대로 전달하십시오. 기상 정보가 없다면 확인이 필요하다고 안내하십시오.
7. 친절하고 정돈된 문장으로 답변하되, 과장하거나 불안을 조장하지 마십시오.
"""


def compose_prompt(user_question: str, context: str, extra: str = "") -> str:
    return (
        f"{INSTRUCTION}\n"
        f"[조회 정보]\n{context}\n"
        f"{extra}\n"
        f"[사용자 질문]\n{user_question}\n"
    )


# ───────────────────────────────────────────────────────────────
# 4. API 호출 + 응답 검증
# ───────────────────────────────────────────────────────────────
def extract_ai_text(resp: dict) -> str:
    out = []
    for item in resp.get("output", []):
        if item.get("type") == "message":
            for c in item.get("content", []):
                if c.get("type") == "output_text":
                    out.append(c.get("text", ""))
    return "\n".join(out)


# ── LLM 호출부 — 여기만 교체하면 모델을 바꿀 수 있습니다 ──────
def call_llm(prompt: str, timeout: int = 180) -> str:
    """
    프롬프트를 받아 답변 텍스트를 반환한다.
    자체 서비스 LLM에 맞게 이 함수만 구현하십시오.
    아래는 ETRI 제주AX 추론엔진 예시입니다(현재 미사용).
    """
    base = os.environ.get("LLM_BASE_URL")
    key = os.environ.get("LLM_API_KEY")
    if not base:
        raise RuntimeError("LLM_BASE_URL 미설정 — call_llm 을 자체 서비스에 맞게 구현하십시오")
    r = requests.post(base, timeout=timeout,
                      headers={"Content-Type": "application/json", "X-API-Key": key or ""},
                      json={"input": prompt, "stream": False})
    r.raise_for_status()
    return extract_ai_text(r.json())


@dataclass
class GuardResult:
    ok: bool
    issues: list[str]


def validate_answer(answer: str, verbatim: list[str]) -> GuardResult:
    """응답이 안전 원칙을 지켰는지 검사한다."""
    issues = []

    if FORBIDDEN.search(answer):
        issues.append("금지 표현(사망/사상자/건수) 포함")

    # 원문 유지 대상이 통째로 사라졌는지 — 핵심 키워드 기준으로 느슨히 확인
    for v in verbatim:
        key = re.sub(r"[^\w가-힣]", "", v)[:12]
        if key and key not in re.sub(r"[^\w가-힣]", "", answer):
            issues.append(f"안전 문구 누락 또는 변형: {v[:28]}…")

    # 시행 전인데 단정
    if "금지되어 있습니다" in answer:
        issues.append("시행 전 규정을 현재 시제로 단정")

    return GuardResult(ok=not issues, issues=issues)


# ───────────────────────────────────────────────────────────────
# 5. 오케스트레이터
# ───────────────────────────────────────────────────────────────
def ask(user_question: str, *, query_type: str = "condition",
        profile: str | None = None, month: int | None = None,
        purpose: str | None = None,
        anchor: str | None = None, place: str | None = None,
        weather: dict | None = None, strict: bool = False,
        include_lodging: bool = False, today_month: int | None = None,
        skip_clarify: bool = False) -> dict:
    """
    query_type: condition | nearby | status
    weather:    {"airTemp":35.1,"windSpeed":16.0,"rainMmH":0.0,
                 "visibility":3000,"waveHeight":1.2,"observedAt":"..."}
    반환에 clarification 이 있으면 사용자에게 선택지를 제시하고 재호출하십시오.
    """
    # ── 0. 되묻기 ────────────────────────────────────────────
    if not skip_clarify:
        if profile is None:
            profile, cl = resolve_profile(user_question)
            if cl:
                return {"clarification": cl, "answer": "", "context": "",
                        "guard": GuardResult(True, []), "prompt": ""}
        if month is None:
            month, cl = resolve_month(user_question, today_month)
            if cl:
                return {"clarification": cl, "answer": "", "context": "",
                        "guard": GuardResult(True, []), "prompt": ""}

    season = (None if month is None else
              "봄" if month in (3, 4, 5) else "여름" if month in (6, 7, 8)
              else "가을" if month in (9, 10, 11) else "겨울")

    # ── 1. KG 조회 ───────────────────────────────────────────
    if query_type == "nearby":
        rows = search_nearby(anchor, limit=MAX_PLACES)
    elif query_type == "status":
        row = check_status(place)
        rows = [row] if row else []
    else:
        rows = search_by_condition(profile=profile, month=month, season=season,
                                   strict=strict, include_lodging=include_lodging,
                                   limit=MAX_PLACES)
    if not rows:
        msg = "조건에 맞는 정보를 찾지 못했습니다."
        if profile in ("VP_VISUAL", "VP_HEARING", "VP_DEVELOP"):
            msg += " " + AXIS_COVERAGE.get(profile, "")
            msg += " 조사되지 않았다는 뜻이지 이용할 수 없다는 뜻은 아닙니다."
        return {"answer": msg, "context": "", "guard": GuardResult(True, []),
                "prompt": "", "clarification": None}

    context, verbatim = build_context_block(rows)

    # ── 2. 기상 ──────────────────────────────────────────────
    outdoor = any(str(r.get("indoorOutdoor", "")).startswith("실외") for r in rows) or True
    wx_text, wx_keep = weather_notice(weather, outdoor=outdoor)
    verbatim.extend(wx_keep)

    # ── 3. 계절 안내 ─────────────────────────────────────────
    season_line = ""
    if season == "여름":
        season_line = "[계절] 해수욕장 개장기간은 통상 7~8월이며, 그 외 기간에는 안전요원이 배치되지 않습니다."
    elif season == "가을":
        season_line = "[계절] 갯바위·방파제 낚시 사고가 잦은 시기입니다."
    elif season == "겨울":
        season_line = "[계절] 해안 강풍과 결빙, 도서 지역 결항에 유의가 필요합니다."
    elif season == "봄":
        season_line = "[계절] 해무가 자주 발생해 시야가 나빠질 수 있습니다."

    extra = "\n".join(x for x in [wx_text, season_line] if x)

    # ── 4. 실시간 위험 발동 ──────────────────────────────────
    if weather and (place or anchor):
        risks = weather_risk(place or anchor,
                             weather.get("windSpeed", 0.0),
                             weather.get("rainMmH", 0.0),
                             weather.get("visibility", 10000))
        if risks:
            extra += "\n[발동된 위험]\n" + "\n".join(
                f"  - {r['risk']} ({r['level']}): "
                f"{', '.join(r['actions']) if r['actions'] else '주의'}" for r in risks)
            verbatim.extend(r["risk"] for r in risks)

    prompt = compose_prompt(user_question, context, extra)
    answer = call_llm(prompt)
    guard = validate_answer(answer, verbatim)
    if not guard.ok:
        answer = "아래는 지식그래프에서 확인된 정보입니다.\n\n" + context + "\n" + extra

    return {"answer": answer, "context": context, "guard": guard,
            "prompt": prompt, "clarification": None,
            "resolved": {"profile": profile, "month": month, "season": season}}


# ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    # ① 모호한 질문 → 되묻기
    r = ask("장애인도 갈 수 있는 제주 관광지 알려줘")
    if r.get("clarification"):
        cl = r["clarification"]
        print("[되묻기]", cl.question)
        for v, label in cl.options:
            print(f"   - {label}  ({v})")

    # ② 유형만 정해지고 시점이 없으면 다시 되묻기
    r = ask("장애인도 갈 수 있는 곳", profile="VP_WHEEL")
    if r.get("clarification"):
        print("\n[되묻기]", r["clarification"].question)

    # ③ 전부 정해지면 조회 + 기상 반영
    r = ask("휠체어로 갈 만한 제주 관광지 추천해줘",
            profile="VP_WHEEL", month=8,
            weather={"airTemp": 35.1, "windSpeed": 4.2, "rainMmH": 0.0,
                     "visibility": 8000, "observedAt": "2026-08-05 14:00"})
    print("\n[해석]", r.get("resolved"))
    print("[검증]", "통과" if r["guard"].ok else r["guard"].issues)
    print("[답변]\n", r["answer"][:600])
