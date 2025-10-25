-- Szkic OEE per zmiana (dla potrzeb prezentacji)
-- Załóżmy okno zmiany 8–16 dla PL_A; w realu trzymaj tabelę shifts/batches.
WITH window AS (
  SELECT 'PL_A'::text AS site,
         timestamptz '2025-10-25 08:00:00+00' AS ts_start,
         timestamptz '2025-10-25 16:00:00+00' AS ts_end
)
, slice AS (
  SELECT s.asset_id,
         SUM(CASE WHEN s.param_id='cycle_count' THEN s.value_si ELSE 0 END) AS pieces_total,
         -- Demo: zakładamy 98% jakości (w realu weź param 'pieces_good')
         SUM(CASE WHEN s.param_id='cycle_count' THEN s.value_si*0.98 ELSE 0 END) AS pieces_good,
         COUNT(*) FILTER (WHERE s.param_id='cycle_count') AS samples
  FROM signals_norm s
  JOIN window w ON s.site=w.site AND s.ts>=w.ts_start AND s.ts<w.ts_end
  GROUP BY s.asset_id
)
SELECT asset_id,
       (pieces_good / NULLIF(pieces_total,0)) AS quality
       -- Availability/Performance pominiete w demie; w realu dodaj sygnały downtime i takt_nominalny
FROM slice;