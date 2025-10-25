-- ─────────────────────────────────────────────────────────────
--  IIoT Star Schema: Bronze → Silver → Gold (PostgreSQL 16)
-- ─────────────────────────────────────────────────────────────

-- Opcjonalnie (jeśli chcesz UUID):
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()
-- Opcjonalnie: TimescaleDB (jeśli używamy timescale)
-- CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ─────────────────────────────────────────────────────────────
--  Wymiary (dimensions)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sites (
  site_id   text PRIMARY KEY,
  name      text NOT NULL
);

CREATE TABLE IF NOT EXISTS divisions (
  division_id text PRIMARY KEY,
  site_id     text NOT NULL REFERENCES sites(site_id) ON DELETE CASCADE,
  name        text NOT NULL
);

CREATE TABLE IF NOT EXISTS lines (
  line_id     text PRIMARY KEY,
  site_id     text NOT NULL REFERENCES sites(site_id) ON DELETE CASCADE,
  division_id text NOT NULL REFERENCES divisions(division_id) ON DELETE CASCADE,
  name        text NOT NULL
);

CREATE TABLE IF NOT EXISTS assets (
  asset_id    text PRIMARY KEY,
  site_id     text NOT NULL REFERENCES sites(site_id) ON DELETE CASCADE,
  division_id text NOT NULL REFERENCES divisions(division_id) ON DELETE CASCADE,
  line_id     text NOT NULL REFERENCES lines(line_id) ON DELETE CASCADE,
  class       text NOT NULL,     -- np. press, injection, conveyor
  model       text NOT NULL,
  vendor      text,
  criticality smallint DEFAULT 0,
  commissioning_date date
);

CREATE TABLE IF NOT EXISTS sensors (
  sensor_id text PRIMARY KEY,
  asset_id  text NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
  type      text NOT NULL,       -- np. temp, vib, power, counter
  location  text,                -- np. bearing_A, cabinet
  param_id  text                 -- domyślny parametr jaki mierzy (opcjonalnie)
);

CREATE TABLE IF NOT EXISTS params (
  param_id     text PRIMARY KEY, -- np. temp_bearing, vibration_rms, cycle_count
  name         text NOT NULL,
  unit_default text NOT NULL,    -- np. C, mm/s, count
  min_value    double precision,
  max_value    double precision
  -- Dla prostoty pomijamy tu formułę konwersji do SI; w realu można dodać np. JSON rules
);

-- ─────────────────────────────────────────────────────────────
--  Bronze: RAW (append-only)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS raw_events (
  msg_id      text PRIMARY KEY,  -- idempotencja (unikalne ID wiadomości)
  asset_id    text NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
  topic       text,
  payload_raw jsonb NOT NULL,    -- surowy JSON z MQTT/edge
  machine_ts  timestamptz NOT NULL,
  ingest_ts   timestamptz NOT NULL DEFAULT now(),
  gateway_id  text,
  schema_ver  integer NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_raw_events_asset_ingest_ts ON raw_events(asset_id, ingest_ts);
CREATE INDEX IF NOT EXISTS idx_raw_events_payload_gin ON raw_events USING GIN (payload_raw);

-- ─────────────────────────────────────────────────────────────
--  Silver: sygnały znormalizowane (fact table: wąska/tidy)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS signals_norm (
  id          bigserial PRIMARY KEY,
  ts          timestamptz NOT NULL,
  asset_id    text NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
  -- Denormalizacja najczęstszych wymiarów do szybkich filtrów:
  site        text NOT NULL,
  division    text NOT NULL,
  line        text NOT NULL,
  class       text NOT NULL,
  model       text NOT NULL,
  sensor_id   text,
  param_id    text NOT NULL REFERENCES params(param_id) ON DELETE RESTRICT,
  value_si    double precision NOT NULL,
  unit_si     text NOT NULL,
  quality_flag smallint NOT NULL DEFAULT 0, -- 0=OK,1=MISSING,2=ESTIMATED,3=OUTLIER
  machine_ts  timestamptz,
  ingest_ts   timestamptz,
  schema_ver  integer NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_signals_norm_asset_ts ON signals_norm(asset_id, ts);
CREATE INDEX IF NOT EXISTS idx_signals_norm_param_ts ON signals_norm(param_id, ts);
CREATE INDEX IF NOT EXISTS idx_signals_norm_site_line_ts ON signals_norm(site, line, ts);

-- Opcjonalnie: hypertable (Timescale)
-- SELECT create_hypertable('signals_norm', by_range('ts'), migrate_data=>true, if_not_exists=>true);

-- Pomocniczy widok: parsowanie RAW -> kolumny (prosty wariant demo)
CREATE OR REPLACE VIEW v_raw_parsed AS
SELECT
  r.msg_id,
  r.asset_id,
  r.machine_ts,
  r.ingest_ts,
  (r.payload_raw->>'param')::text                  AS param_id,
  (r.payload_raw->>'value')::double precision      AS value_raw,
  (r.payload_raw->>'unit')::text                   AS unit_raw,
  (r.payload_raw->>'sensor_id')::text              AS sensor_id
FROM raw_events r;

-- ETL: RAW → Silver (demo: zakładamy, że unit_raw jest już w SI)
CREATE OR REPLACE FUNCTION etl_raw_to_silver() RETURNS integer AS $$
DECLARE
  inserted_count integer;
BEGIN
  INSERT INTO signals_norm (
    ts, asset_id, site, division, line, class, model, sensor_id,
    param_id, value_si, unit_si, quality_flag, machine_ts, ingest_ts
  )
  SELECT
    COALESCE(v.machine_ts, v.ingest_ts) AS ts,
    v.asset_id,
    a.site_id       AS site,
    a.division_id   AS division,
    a.line_id       AS line,
    a.class,
    a.model,
    v.sensor_id,
    v.param_id,
    v.value_raw     AS value_si,
    COALESCE(v.unit_raw, p.unit_default) AS unit_si,
    0 AS quality_flag,
    v.machine_ts,
    v.ingest_ts
  FROM v_raw_parsed v
  JOIN assets a  ON a.asset_id = v.asset_id
  JOIN params p  ON p.param_id = v.param_id
  LEFT JOIN LATERAL (
    SELECT 1 -- hook na walidację/konwersję w realnym ETL
  ) _ ON true
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────
--  Gold: metryki/KPI (materializacje)
-- ─────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS metrics_1m AS
SELECT
  asset_id,
  param_id,
  date_trunc('minute', ts) AS window_start,
  AVG(value_si)                                          AS avg_val,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY value_si) AS p95_val,
  MIN(value_si)                                          AS min_val,
  MAX(value_si)                                          AS max_val,
  COUNT(*)                                               AS n
FROM signals_norm
GROUP BY asset_id, param_id, date_trunc('minute', ts);

-- Unikalny indeks wymagany do REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS uq_metrics_1m ON metrics_1m(asset_id, param_id, window_start);

-- Helper do odświeżania materializacji
CREATE OR REPLACE FUNCTION refresh_metrics_1m() RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY metrics_1m;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────
--  Alerting (polityki + zdarzenia) – szkic
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alert_policies (
  policy_id   bigserial PRIMARY KEY,
  level       text NOT NULL CHECK (level IN ('global','class','model','asset')),
  selector    text NOT NULL, -- np. 'press', 'PressCo H-200', 'line1-press03'
  metric      text NOT NULL, -- np. 'temp_bearing'
  condition   text NOT NULL, -- np. '> 80'
  window_s    integer NOT NULL DEFAULT 120,
  hysteresis  text,          -- np. '3C/5m'
  severity    text NOT NULL CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  actions     text,
  UNIQUE(level, selector, metric)
);

CREATE TABLE IF NOT EXISTS alerts (
  alert_id   bigserial PRIMARY KEY,
  asset_id   text NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
  policy_id  bigint REFERENCES alert_policies(policy_id) ON DELETE SET NULL,
  ts_open    timestamptz NOT NULL DEFAULT now(),
  ts_close   timestamptz,
  severity   text NOT NULL,
  state      text NOT NULL DEFAULT 'OPEN',
  evidence   jsonb
);