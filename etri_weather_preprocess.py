# -*- coding: utf-8 -*-
"""
ETRI weather → Neo4j 판정 파라미터 전처리
────────────────────────────────────────────────────────────
역할: 서비스 서버가 ETRI PostgreSQL에서 읽어온 원천 기상값을 받아,
      파생값(체감온도·상류강수·일몰시간 등)을 계산하고,
      Neo4j 판정 Cypher에 넣을 파라미터 dict로 변환한다.

원칙:
  - 원천 데이터(기온·습도·풍속)는 ETRI 테이블 그대로 사용, 저장 안 함
  - 파생 계산은 판정 직전(여기)에서만 수행
  - Neo4j는 "판정"만, 계산은 이 모듈이 담당
  - 안전 판정에 LLM 미개입

의존성 없음(표준 라이브러리만). astral 있으면 일몰 정확도↑(선택).
"""
from __future__ import annotations
import math
from datetime import datetime, date, timedelta, timezone
from typing import Optional, TypedDict

KST = timezone(timedelta(hours=9))


# ══════════════════════════════════════════════════════════════
# 1. ETRI 원천 입력 스키마 (서버가 SQL로 조회한 결과를 이 형태로 전달)
# ══════════════════════════════════════════════════════════════
class ETRIForecast(TypedDict, total=False):
    """weather_forecasting_tb 한 행 (최근접 격자·최신 reported_at)"""
    temperature: float            # 기온 °C
    humidity: float               # 상대습도 %
    precipitation: float          # 시간당 강수 mm/h
    wind_speed: float             # 풍속 m/s
    wave_height: float            # 파고 m
    lightning_strike: float       # 낙뢰 (0=없음)

class ETRIObservation(TypedDict, total=False):
    """weather_realtime_observation_tb 한 행 (특보 판정용 관측값)"""
    wind_speed_10m_avg_ms: float
    wind_speed_max_instant_ms: float   # 순간최대풍속 (강풍특보 판정)
    temp_air_1m_avg_c: float
    rain_acc_60m_mm: float             # 시간당 강수
    rain_acc_12h_mm: float             # 12h 누적 (호우특보 판정)
    humidity_rel_1m_avg_pct: float


# ══════════════════════════════════════════════════════════════
# 2. 파생값 계산 — 기상청 공식 산식
# ══════════════════════════════════════════════════════════════
def apparent_temp_summer(ta: float, rh: float) -> float:
    """
    여름철 체감온도 (기상청 2022.6.2 개정식)
    Tw: Stull 추정 습구온도
    체감온도 = -0.2442 + 0.55399·Tw + 0.45535·Ta − 0.0022·Tw² + 0.00278·Tw·Ta + 3.0
    """
    tw = (ta * math.atan(0.151977 * (rh + 8.313659) ** 0.5)
          + math.atan(ta + rh) - math.atan(rh - 1.67633)
          + 0.00391838 * rh ** 1.5 * math.atan(0.023101 * rh) - 4.686035)
    return round(-0.2442 + 0.55399 * tw + 0.45535 * ta
                 - 0.0022 * tw ** 2 + 0.00278 * tw * ta + 3.0, 1)


def apparent_temp_winter(ta: float, v_ms: float) -> float:
    """
    겨울철 체감온도 (풍속냉각, 기상청식)
    기온 10℃ 이하 & 풍속 1.3 m/s 이상일 때만 유효.
    V는 km/h로 변환하여 사용.
    체감온도 = 13.12 + 0.6215·Ta − 11.37·V^0.16 + 0.3965·V^0.16·Ta
    """
    v_kmh = v_ms * 3.6
    if ta > 10 or v_ms < 1.3:
        return ta  # 산출 조건 미충족 → 기온 그대로
    return round(13.12 + 0.6215 * ta - 11.37 * v_kmh ** 0.16
                 + 0.3965 * v_kmh ** 0.16 * ta, 1)


def apparent_temp(ta: float, rh: Optional[float], v_ms: Optional[float],
                  when: Optional[date] = None) -> float:
    """
    계절 자동 분기 체감온도.
    - 여름(5~9월) & 습도 有 → 여름식
    - 겨울(11~3월) & 기온≤10 & 풍속≥1.3 → 겨울식
    - 그 외 → 기온 그대로
    """
    when = when or datetime.now(KST).date()
    m = when.month
    if 5 <= m <= 9 and rh is not None:
        return apparent_temp_summer(ta, rh)
    if (m >= 11 or m <= 3) and v_ms is not None:
        return apparent_temp_winter(ta, v_ms)
    return round(ta, 1)


def minutes_to_sunset(lat: float, lon: float,
                      now: Optional[datetime] = None) -> int:
    """
    일몰까지 남은 분 (야간위험·길잃음 판정용).
    astral 설치 시 정확, 없으면 NOAA 근사식으로 폴백.
    음수면 이미 일몰 지남.
    """
    now = now or datetime.now(KST)
    try:
        from astral import LocationInfo
        from astral.sun import sun
        loc = LocationInfo(latitude=lat, longitude=lon)
        s = sun(loc.observer, date=now.date(), tzinfo=KST)
        return int((s["sunset"] - now).total_seconds() // 60)
    except Exception:
        # NOAA 근사: 일몰 시각(시간, KST)
        n = now.timetuple().tm_yday
        decl = 23.45 * math.sin(math.radians(360 / 365 * (n - 81)))
        ha = math.degrees(math.acos(
            max(-1, min(1, -math.tan(math.radians(lat)) * math.tan(math.radians(decl))))))
        # 태양남중시각 ≈ 12 - (경도-135)/15  (KST 표준자오선 135°E)
        solar_noon = 12 - (lon - 135) / 15
        sunset_h = solar_noon + ha / 15
        sunset = now.replace(hour=int(sunset_h),
                             minute=int((sunset_h % 1) * 60),
                             second=0, microsecond=0)
        return int((sunset - now).total_seconds() // 60)


# ══════════════════════════════════════════════════════════════
# 3. 메인: ETRI 값 → Neo4j 파라미터 dict
# ══════════════════════════════════════════════════════════════
class JudgementParams(TypedDict, total=False):
    placeName: str
    wind_speed: float          # 예보 풍속
    wind_gust: float           # 관측 순간최대 (특보 판정용)
    rain_mmh: float
    rain_12h: float            # 12h 누적 (호우특보)
    wave_height: float
    apparent_temp: float       # ★ 서버 환산값
    temperature: float
    humidity: float
    upstream_rain_mmh: float   # 상류(한라산권) 강수 — 별도 조회
    minutes_to_sunset: int
    # ETRI 밖(개발자 수집분 주입 지점) — 없으면 생략
    snow_24h: Optional[float]
    cai: Optional[float]
    occupancy: Optional[float]


def build_params(
    place_name: str,
    place_lat: float,
    place_lon: float,
    forecast: ETRIForecast,
    observation: Optional[ETRIObservation] = None,
    upstream_forecast: Optional[ETRIForecast] = None,   # 한라산권 격자 예보
    external: Optional[dict] = None,                     # {snow_24h, cai, occupancy}
    when: Optional[date] = None,
) -> JudgementParams:
    """
    서비스 서버 사용 예:
        f = query_etri_forecast(lat, lon)          # 최근접 격자 최신 예보
        o = query_etri_observation(lat, lon)       # 최근접 관측소 (특보용)
        up = query_etri_forecast(HALLA_LAT, HALLA_LON)  # 상류 격자
        params = build_params("산방산", lat, lon, f, o, up)
        session.run(REALTIME_CYPHER, **params)
    """
    obs = observation or {}
    ext = external or {}

    # 체감온도: 관측 습도 우선, 없으면 예보 습도
    ta = forecast.get("temperature")
    rh = obs.get("humidity_rel_1m_avg_pct", forecast.get("humidity"))
    v = obs.get("wind_speed_10m_avg_ms", forecast.get("wind_speed"))
    app_t = apparent_temp(ta, rh, v, when) if ta is not None else None

    params: JudgementParams = {
        "placeName": place_name,
        "wind_speed": forecast.get("wind_speed"),
        # 특보 판정은 순간최대풍속 우선 (없으면 예보 풍속)
        "wind_gust": obs.get("wind_speed_max_instant_ms", forecast.get("wind_speed")),
        "rain_mmh": obs.get("rain_acc_60m_mm", forecast.get("precipitation")),
        "rain_12h": obs.get("rain_acc_12h_mm"),
        "wave_height": forecast.get("wave_height"),
        "temperature": ta,
        "humidity": rh,
        "apparent_temp": app_t,
        "minutes_to_sunset": minutes_to_sunset(place_lat, place_lon,
                                               datetime.now(KST) if when is None else None),
    }
    # 상류강수 (계곡·세월교 FlashFlood 판정용)
    if upstream_forecast is not None:
        params["upstream_rain_mmh"] = upstream_forecast.get("precipitation")
    # ETRI 밖 — 개발자 수집분이 있으면 주입, 없으면 키 생략(해당 위험 판정 skip)
    for k in ("snow_24h", "cai", "occupancy"):
        if k in ext and ext[k] is not None:
            params[k] = ext[k]

    # None 값은 제거 (Cypher에서 IS NOT NULL로 skip 처리됨)
    return {k: v for k, v in params.items() if v is not None}


# ══════════════════════════════════════════════════════════════
# 4. 검증 (샘플 실행)
# ══════════════════════════════════════════════════════════════
if __name__ == "__main__":
    # 시나리오: 한여름 산방산, 기온 32℃·습도 70%·순간풍속 16m/s·파고 3.2m
    f: ETRIForecast = {"temperature": 32.0, "humidity": 70.0, "precipitation": 2.0,
                       "wind_speed": 12.0, "wave_height": 3.2, "lightning_strike": 0.0}
    o: ETRIObservation = {"wind_speed_10m_avg_ms": 12.0, "wind_speed_max_instant_ms": 16.0,
                          "temp_air_1m_avg_c": 32.0, "rain_acc_60m_mm": 2.0,
                          "rain_acc_12h_mm": 30.0, "humidity_rel_1m_avg_pct": 70.0}
    p = build_params("산방산", 33.2361, 126.3131, f, o,
                     external={"cai": 45})   # 대기질만 수집분 있다고 가정
    print("=== 산방산 여름 판정 파라미터 ===")
    for k, v in p.items():
        print(f"  {k:20s} = {v}")
    print(f"\n  → 체감온도 환산: 기온 32℃ + 습도 70% = {p['apparent_temp']}℃ (폭염 판정용)")
    print(f"  → 특보 판정용 순간풍속: {p['wind_gust']} m/s")

    # 겨울 시나리오
    fw: ETRIForecast = {"temperature": 2.0, "humidity": 50.0, "wind_speed": 8.0,
                        "precipitation": 0.0, "wave_height": 1.0}
    pw = build_params("한라산탐방로", 33.3617, 126.5292, fw, when=date(2026, 1, 15))
    print(f"\n=== 겨울 한라산 ===")
    print(f"  기온 2℃ + 풍속 8m/s → 체감온도 {pw['apparent_temp']}℃")
