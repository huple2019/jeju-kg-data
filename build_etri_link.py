# -*- coding: utf-8 -*-
"""ETRI weather 직접접근 연동:
 1) RiskPattern 조건식 → 구조화(factorKey=ETRI필드명, operator, threshold)
 2) ETRI weather 필드 ↔ RiskPattern factor 매핑표
 3) 실시간 판정 Cypher (ETRI DB조회값을 파라미터로 주입)
"""
import pandas as pd, re
RC='/tmp/chk/rc'; OUT='/home/claude/etri'

rp = pd.read_csv(f'{RC}/nodes_riskpattern.csv')

# ===== ETRI 필드 매핑 (factor 논리명 → ETRI 실제 컬럼) =====
# 예보: weather_forecasting_tb / 실시간관측: weather_realtime_observation_tb
ETRI_MAP = {
 # factor논리명 : (예보컬럼, 관측컬럼, 특보기준 관측컬럼, 단위, 산출메모)
 'wind_speed':   ('wind_speed','wind_speed_10m_avg_ms','wind_speed_max_instant_ms','m/s','관측 순간최대=특보판정용'),
 'rain_mm_h':    ('precipitation','rain_acc_60m_mm','rain_acc_12h_mm','mm/h','예보 precipitation=시간당, 관측 60m/12h 누적'),
 'wave_height':  ('wave_height',None,None,'m','예보만 제공(관측 없음)'),
 'apparent_temp':('temperature','temp_air_1m_avg_c',None,'C','기온→체감온도 서버 환산(습도 결합)'),
 'min_temp':     ('temperature','temp_air_1m_avg_c',None,'C','일 최저는 예보 시계열 min 산출'),
 'lightning':    ('lightning_strike',None,None,'code','낙뢰(신규 활용 가능)'),
 # 아래는 ETRI weather 밖 — 별도 출처
 'snow_24h':     (None,None,None,'cm','ETRI 미제공 — 기상청 별도 or 예보 확장 필요'),
 'cai':          (None,None,None,'CAI','환경부 에어코리아(ETRI 밖)'),
 'occupancy':    (None,None,None,'percent','혼잡도 — 별도 산출(교통/방문자)'),
 'minutes_to_sunset':(None,None,None,'min','천문 계산(서버)'),
}
mp=[]
for f,(fc,ob,al,u,memo) in ETRI_MAP.items():
    mp.append({'factor':f,'etri_forecast_col':fc or '','etri_observation_col':ob or '',
               'etri_alert_col':al or '','unit':u,'source':'ETRI_weather' if fc else 'external','note':memo})
pd.DataFrame(mp).to_csv(f'{OUT}/etri_weather_factor_mapping.csv',index=False,encoding='utf-8-sig')

# ===== RiskPattern 조건식 구조화 =====
# factor 추출: 조건식 첫 토큰
FACTOR_RE = re.compile(r'^\s*([a-z_]+)\s*(>=|<=|=|>|<)')
def parse(cond):
    m=FACTOR_RE.match(str(cond))
    return m.group(1) if m else None

rows=[]
env=rp[rp['env_id'].notna() & (rp['env_id']!='')]
for _,r in env.iterrows():
    factor=parse(r['condition_expr'])
    etri=ETRI_MAP.get(factor)
    tmin=r['threshold_min']; tmax=r['threshold_max']
    # operator/threshold 정규화
    if pd.notna(tmin) and pd.notna(tmax):
        op='range'; lo=tmin; hi=tmax
    elif pd.notna(tmin):
        op='>='; lo=tmin; hi=None
    elif pd.notna(tmax):
        op='<='; lo=None; hi=tmax
    else:
        op='special'; lo=None; hi=None  # zone/time 기반
    # zone 조건 추출
    zone=re.search(r'zone IN \[([^\]]+)\]', str(r['condition_expr']))
    rows.append({
        'risk_id':r['risk_id'],'factor':factor,
        'param_key':f'${factor}',                     # Cypher 파라미터명
        'etri_forecast_col':etri[0] if etri else '',
        'etri_alert_col':etri[2] if etri else '',
        'operator':op,'threshold_low':lo,'threshold_high':hi,
        'unit':r['threshold_unit'],
        'zone_condition':zone.group(1) if zone else '',
        'risk_level':r['risk_level'],
        'available_in_etri':'Y' if (etri and etri[0]) else 'N',
    })
struct=pd.DataFrame(rows)
struct.to_csv(f'{OUT}/riskpattern_conditions_structured.csv',index=False,encoding='utf-8-sig')

print('구조화된 조건:', len(struct))
print('ETRI weather 직접판정 가능:', (struct['available_in_etri']=='Y').sum(),'/',len(struct))
print('  가능 factor:', sorted(struct[struct.available_in_etri=='Y']['factor'].unique()))
print('  ETRI밖(별도):', sorted(struct[struct.available_in_etri=='N']['factor'].unique()))
