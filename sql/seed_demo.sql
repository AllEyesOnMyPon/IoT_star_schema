-- Demo danych: 2 fabryki (PL_A, PL_B), 2 działy, 2 linie, 2 maszyny, parametry i RAW

-- Sites
INSERT INTO sites(site_id, name) VALUES
  ('PL_A','Fabryka A')  ON CONFLICT DO NOTHING,
  ('PL_B','Fabryka B')  ON CONFLICT DO NOTHING;

-- Divisions (działy)
INSERT INTO divisions(division_id, site_id, name) VALUES
  ('A_MNT','PL_A','Montaż'),
  ('A_PRD','PL_A','Produkcja'),
  ('B_PRD','PL_B','Produkcja')
ON CONFLICT DO NOTHING;

-- Lines
INSERT INTO lines(line_id, site_id, division_id, name) VALUES
  ('A_L1','PL_A','A_PRD','Linia 1'),
  ('B_L1','PL_B','B_PRD','Linia 1')
ON CONFLICT DO NOTHING;

-- Assets (dwie różne prasy)
INSERT INTO assets(asset_id, site_id, division_id, line_id, class, model, vendor, criticality)
VALUES
  ('A_L1_PRESS01','PL_A','A_PRD','A_L1','press','PressCo H-200','PressCo',2),
  ('B_L1_PRESS01','PL_B','B_PRD','B_L1','press','MegaPress M-250','Mega',3)
ON CONFLICT DO NOTHING;

-- Params
INSERT INTO params(param_id, name, unit_default, min_value, max_value) VALUES
  ('temp_bearing','Temperatura łożyska','C', 0, 120),
  ('cycle_count','Licznik cykli','count', 0, NULL)
ON CONFLICT DO NOTHING;

-- RAW events (payload JSON: param/value/unit/machine_ts/sensor_id)
INSERT INTO raw_events(msg_id, asset_id, topic, payload_raw, machine_ts, gateway_id)
VALUES
  ('m1', 'A_L1_PRESS01', 'pl/PL_A/A_L1/press01/temp',
    '{"param":"temp_bearing","value":72.5,"unit":"C","sensor_id":"A_PRESS01_T1","machine_ts":"2025-10-25T10:00:05Z"}',
    '2025-10-25T10:00:05Z', 'gw-1'),
  ('m2', 'A_L1_PRESS01', 'pl/PL_A/A_L1/press01/counter',
    '{"param":"cycle_count","value":100,"unit":"count","sensor_id":"A_PRESS01_C1","machine_ts":"2025-10-25T10:00:05Z"}',
    '2025-10-25T10:00:05Z', 'gw-1'),
  ('m3', 'A_L1_PRESS01', 'pl/PL_A/A_L1/press01/temp',
    '{"param":"temp_bearing","value":74.1,"unit":"C","sensor_id":"A_PRESS01_T1","machine_ts":"2025-10-25T10:01:05Z"}',
    '2025-10-25T10:01:05Z', 'gw-1'),
  ('m4', 'A_L1_PRESS01', 'pl/PL_A/A_L1/press01/counter',
    '{"param":"cycle_count","value":112,"unit":"count","sensor_id":"A_PRESS01_C1","machine_ts":"2025-10-25T10:01:05Z"}',
    '2025-10-25T10:01:05Z', 'gw-1'),
  ('m5', 'B_L1_PRESS01', 'pl/PL_B/B_L1/press01/temp',
    '{"param":"temp_bearing","value":68.0,"unit":"C","sensor_id":"B_PRESS01_T1","machine_ts":"2025-10-25T10:00:10Z"}',
    '2025-10-25T10:00:10Z', 'gw-2'),
  ('m6', 'B_L1_PRESS01', 'pl/PL_B/B_L1/press01/counter',
    '{"param":"cycle_count","value":95,"unit":"count","sensor_id":"B_PRESS01_C1","machine_ts":"2025-10-25T10:00:10Z"}',
    '2025-10-25T10:00:10Z', 'gw-2');

-- Przykładowe polityki alertów (różne modele)
INSERT INTO alert_policies(level, selector, metric, condition, window_s, hysteresis, severity, actions) VALUES
  ('global','*','temp_bearing','> 85',120,'3C/5m','HIGH','CMMS,SMS'),
  ('model','PressCo H-200','temp_bearing','> 80',120,'3C/5m','HIGH','CMMS,SMS'),
  ('model','MegaPress M-250','temp_bearing','> 85',120,'3C/5m','HIGH','CMMS,SMS')
ON CONFLICT DO NOTHING;

-- ETL: RAW → Silver
SELECT etl_raw_to_silver();

-- Materializacja Gold (1m)
SELECT refresh_metrics_1m();