erDiagram
  SITES {
    string site_id PK
    string name
  }
  DIVISIONS {
    string division_id PK
    string site_id FK
    string name
  }
  LINES {
    string line_id PK
    string site_id FK
    string division_id FK
    string name
  }
  ASSETS {
    string asset_id PK
    string site_id FK
    string division_id FK
    string line_id FK
    string class
    string model
    string vendor
    int    criticality
    date   commissioning_date
  }
  SENSORS {
    string sensor_id PK
    string asset_id FK
    string type
    string location
    string param_id FK
  }
  PARAMS {
    string param_id PK
    string name
    string unit_default
    float  min_value
    float  max_value
  }
  RAW_EVENTS {
    string msg_id PK
    string asset_id FK
    string topic
    json   payload_raw
    datetime machine_ts
    datetime ingest_ts
    string gateway_id
    int    schema_ver
  }
  SIGNALS_NORM {
    bigint id PK
    datetime ts
    string  asset_id FK
    string  site
    string  division
    string  line
    string  class
    string  model
    string  sensor_id
    string  param_id FK
    float   value_si
    string  unit_si
    int     quality_flag
    datetime machine_ts
    datetime ingest_ts
    int     schema_ver
  }
  METRICS_1M {
    string  asset_id FK
    string  param_id FK
    datetime window_start
    float   avg_val
    float   p95_val
    float   min_val
    float   max_val
    int     n
  }
  ALERT_POLICIES {
    bigint policy_id PK
    string level        // global | class | model | asset
    string selector
    string metric
    string condition
    int    window_s
    string hysteresis
    string severity     // LOW | MEDIUM | HIGH | CRITICAL
    string actions
  }
  ALERTS {
    bigint alert_id PK
    string asset_id FK
    bigint policy_id FK
    datetime ts_open
    datetime ts_close
    string severity
    string state
    json   evidence
  }

  SITES ||--o{ DIVISIONS : has
  SITES ||--o{ LINES     : has
  DIVISIONS ||--o{ LINES  : has
  LINES ||--o{ ASSETS     : has
  ASSETS ||--o{ SENSORS   : has
  PARAMS ||--o{ SENSORS   : default_param
  ASSETS ||--o{ RAW_EVENTS   : emits
  ASSETS ||--o{ SIGNALS_NORM : emits
  PARAMS ||--o{ SIGNALS_NORM : measures
  SIGNALS_NORM ||--o{ METRICS_1M : aggregates
  ALERT_POLICIES ||--o{ ALERTS   : triggers
  ASSETS ||--o{ ALERTS           : raises
