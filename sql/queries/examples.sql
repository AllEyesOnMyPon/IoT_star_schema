\timing on

-- 1) Filtrowanie po fabryce/dziale/maszynie (bez JOIN dzięki denormalizacji)
SELECT asset_id, param_id, ts, value_si
FROM signals_norm
WHERE site='PL_A' AND division='A_PRD' AND asset_id='A_L1_PRESS01'
ORDER BY ts
LIMIT 20;

-- 2) p95 temperatury na kubełkach 1-min
SELECT asset_id, date_trunc('minute', ts) AS bucket,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY value_si) AS p95_temp
FROM signals_norm
WHERE param_id='temp_bearing'
GROUP BY asset_id, date_trunc('minute', ts)
ORDER BY asset_id, bucket;

-- 3) Rate z licznika (szt/min), z ochroną przed resetem
WITH x AS (
  SELECT asset_id, ts, value_si AS cnt,
         LAG(value_si) OVER (PARTITION BY asset_id ORDER BY ts) AS prev_cnt,
         EXTRACT(EPOCH FROM (ts - LAG(ts) OVER (PARTITION BY asset_id ORDER BY ts))) AS dt
  FROM signals_norm
  WHERE param_id='cycle_count'
)
SELECT asset_id, ts,
       GREATEST(0, cnt - COALESCE(prev_cnt, cnt)) / NULLIF(dt,0) * 60 AS rate_per_min
FROM x
ORDER BY asset_id, ts;

-- 4) Brak danych > 3 min (healthcheck)
WITH last_seen AS (
  SELECT asset_id, MAX(ts) AS last_ts
  FROM signals_norm
  GROUP BY asset_id
)
SELECT asset_id, last_ts
FROM last_seen
WHERE now() - last_ts > interval '3 minutes';