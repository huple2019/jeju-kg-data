"""
huple_etri_connector.py — 휴플 KG × ETRI 제주AX 추론엔진 연동

현 단계 방식 (ETRI 안내 기준):
    Client Tool-use 미지원 → KG를 먼저 조회하고, 결과를 프롬프트에 합성해 전달.

설계 원칙
    1. KG 조회 로직을 함수 단위로 분리한다.
       → 추후 Tool Registry가 열리면 같은 함수를 MCP 도구로 노출만 하면 된다.
    2. 안전 안내 문구(advisoryMessage)는 LLM이 재작성하지 못하게 하고,
       재작성되더라도 응답 검증에서 걸러낸다.
    3. 20B 소형 모델이므로 컨텍스트를 최소화한다. (상위 N곳, 필요한 필드만)

환경변수
    JEJU_BASE_URL   기본값 https://jejuax.ngrok.app/api/agent
    JEJU_API_KEY    ETRI 발급 키 (코드/저장소에 하드코딩 금지)
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
BASE_URL = os.environ.get("JEJU_BASE_URL", "https://jejuax.ngrok.app/api/agent")
API_KEY = os.environ["JEJU_API_KEY"]           # 없으면 즉시 실패시킨다
URL = f"{BASE_URL}/v1/responses"
HEADERS = {"Content-Type": "application/json", "X-API-Key": API_KEY}
MODEL = "jeju-tourism-agent"

NEO4J_URI = os.environ["NEO4J_URI"]
NEO4J_AUTH = (os.environ["NEO4J_USER"], os.environ["NEO4J_PASSWORD"])

# 컨텍스트 예산 — 소형 모델이므로 좁게 잡는다
MAX_PLACES = 5

# 사용자 응답에 절대 나와서는 안 되는 표현
# (프로젝트 원칙: 사망/부상 건수를 노출하지 않고 행동 지침만 전달)
FORBIDDEN = re.compile(r"사망|숨진|사상자|치사|익사|\d+\s*명이?\s*(?:숨|사망|다)")


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
6. 친절하고 정돈된 문장으로 답변하되, 과장하거나 불안을 조장하지 마십시오.
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


def call_agent(prompt: str, stream: bool = False, timeout: int = 180) -> dict:
    r = requests.post(URL, headers=HEADERS, timeout=timeout,
                      json={"model": MODEL, "input": prompt, "stream": stream})
    r.raise_for_status()
    return r.json()


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
        season: str | None = None, anchor: str | None = None,
        place: str | None = None, weather: dict | None = None,
        strict: bool = False, include_lodging: bool = False) -> dict:
    """
    query_type: condition | nearby | status
    weather: {"wind":16.0,"rain":0.0,"visibility":3000}
    """
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
        return {"answer": "조건에 맞는 정보를 찾지 못했습니다. 조건을 넓혀 다시 질문해 주세요.",
                "context": "", "guard": GuardResult(True, []), "raw": None}

    context, verbatim = build_context_block(rows)

    extra = ""
    if weather and (place or anchor):
        target = place or anchor
        risks = weather_risk(target, weather.get("wind", 0.0),
                             weather.get("rain", 0.0),
                             weather.get("visibility", 10000))
        if risks:
            lines = [f"  - {r['risk']} ({r['level']}): "
                     f"{', '.join(r['actions']) if r['actions'] else '주의'}"
                     for r in risks]
            extra = "\n[현재 기상 조건으로 발동된 위험]\n" + "\n".join(lines)
            verbatim.extend(r["risk"] for r in risks)

    prompt = compose_prompt(user_question, context, extra)
    raw = call_agent(prompt)
    answer = extract_ai_text(raw)
    guard = validate_answer(answer, verbatim)

    # 안전 원칙 위반 시 LLM 답변 대신 KG 원문을 그대로 제시한다
    if not guard.ok:
        answer = ("아래는 지식그래프에서 확인된 정보입니다.\n\n" + context)

    return {"answer": answer, "context": context, "guard": guard, "raw": raw}


# ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    r = ask("휠체어로 갈 만한 제주 해안 관광지 알려줘",
            query_type="condition", profile="VP_WHEEL", month=8, season="여름")
    print("=" * 60)
    print("[컨텍스트]\n", r["context"][:800])
    print("=" * 60)
    print("[검증]", "통과" if r["guard"].ok else r["guard"].issues)
    print("=" * 60)
    print("[답변]\n", r["answer"])
