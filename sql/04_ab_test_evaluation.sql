-- 04_ab_test_evaluation.sql
-- A/B Test: reward_20pct_uplift
-- Window: 2025-11-10 to 2025-12-08 (inclusive)
-- DuckDB compatible
-- Output:
--  - VARIANT_METRICS: control + variant rows
--  - LIFT_VS_CONTROL: % lift of variant vs control (for key KPIs)

CREATE OR REPLACE VIEW ab AS
SELECT * FROM read_csv_auto('data/ab_assignments.csv');

CREATE OR REPLACE VIEW users AS
SELECT * FROM read_csv_auto('data/users.csv');

CREATE OR REPLACE VIEW events AS
SELECT *
FROM read_csv_auto('data/events.csv')
WHERE event_ts >= TIMESTAMP '2025-10-01'
  AND event_ts <= TIMESTAMP '2025-12-31 23:59:00';

CREATE OR REPLACE VIEW purchases AS
SELECT * FROM read_csv_auto('data/purchases.csv');

CREATE OR REPLACE VIEW ads_events AS
SELECT *
FROM read_csv_auto('data/ads_events.csv')
WHERE ad_ts >= TIMESTAMP '2025-10-01'
  AND ad_ts <= TIMESTAMP '2025-12-31 23:59:00';

WITH
params AS (
  SELECT
    TIMESTAMP '2025-11-10 00:00:00' AS test_start,
    TIMESTAMP '2025-12-08 23:59:59' AS test_end,
    'reward_20pct_uplift' AS exp_name
),

-- ----------------------------
-- A/B population
-- ----------------------------
ab_pop AS (
  SELECT
    a.user_id,
    a.experiment_name,
    a.variant,
    a.assign_ts
  FROM ab a, params p
  WHERE a.experiment_name = p.exp_name
    AND a.assign_ts BETWEEN p.test_start AND p.test_end
),

-- ----------------------------
-- Sessions + duration (test window)
-- ----------------------------
sess AS (
  SELECT
    e.user_id,
    e.session_id,
    MIN(CASE WHEN e.event_name='session_start' THEN e.event_ts END) AS start_ts,
    MAX(CASE WHEN e.event_name='session_end' THEN e.event_ts END) AS end_ts
  FROM events e
  GROUP BY 1,2
),

sess_test AS (
  SELECT
    s.user_id,
    s.session_id,
    s.start_ts,
    s.end_ts,
    DATE_DIFF('minute', s.start_ts, s.end_ts) AS duration_min
  FROM sess s, params p
  WHERE s.start_ts BETWEEN p.test_start AND p.test_end
    AND s.start_ts IS NOT NULL AND s.end_ts IS NOT NULL
),

sess_agg AS (
  SELECT
    user_id,
    COUNT(*) AS sessions,
    AVG(duration_min) AS avg_session_duration_min
  FROM sess_test
  GROUP BY 1
),

-- ----------------------------
-- Level starts & completes (test window)
-- ----------------------------
levels AS (
  SELECT
    e.user_id,
    SUM(CASE WHEN e.event_name='level_start' THEN 1 ELSE 0 END) AS level_starts,
    SUM(CASE WHEN e.event_name='level_complete' THEN 1 ELSE 0 END) AS level_completes
  FROM events e, params p
  WHERE e.event_ts BETWEEN p.test_start AND p.test_end
  GROUP BY 1
),

-- ----------------------------
-- Revenue per user (test window)
-- ----------------------------
iap_user AS (
  SELECT
    p.user_id,
    SUM(p.revenue_usd) AS iap_revenue
  FROM purchases p, params par
  WHERE p.purchase_ts BETWEEN par.test_start AND par.test_end
  GROUP BY 1
),

ads_user AS (
  SELECT
    a.user_id,
    SUM(a.ad_revenue_usd) AS ads_revenue,
    COUNT(*) AS ad_impressions
  FROM ads_events a, params par
  WHERE a.ad_ts BETWEEN par.test_start AND par.test_end
  GROUP BY 1
),

-- ----------------------------
-- D1 retention guardrail (based on assign day)
-- D1 = has session_start on day(assign_ts)+1
-- ----------------------------
dau AS (
  SELECT
    DATE_TRUNC('day', event_ts) AS day,
    user_id
  FROM events
  WHERE event_name='session_start'
  GROUP BY 1,2
),

d1 AS (
  SELECT
    ap.user_id,
    ap.variant,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM dau d
        WHERE d.user_id = ap.user_id
          AND d.day = DATE_TRUNC('day', ap.assign_ts) + INTERVAL 1 DAY
      ) THEN 1 ELSE 0
    END AS retained_d1
  FROM ab_pop ap
),

-- ----------------------------
-- User-level metrics table
-- ----------------------------
user_metrics AS (
  SELECT
    ap.variant,
    ap.user_id,

    COALESCE(sa.sessions, 0) AS sessions,
    sa.avg_session_duration_min AS avg_session_duration_min,

    COALESCE(l.level_starts, 0) AS level_starts,
    COALESCE(l.level_completes, 0) AS level_completes,

    COALESCE(i.iap_revenue, 0) AS iap_revenue,
    COALESCE(ad.ads_revenue, 0) AS ads_revenue,
    COALESCE(ad.ad_impressions, 0) AS ad_impressions,

    COALESCE(d1.retained_d1, 0) AS retained_d1
  FROM ab_pop ap
  LEFT JOIN sess_agg sa ON ap.user_id = sa.user_id
  LEFT JOIN levels l ON ap.user_id = l.user_id
  LEFT JOIN iap_user i ON ap.user_id = i.user_id
  LEFT JOIN ads_user ad ON ap.user_id = ad.user_id
  LEFT JOIN d1 d1 ON ap.user_id = d1.user_id
),

-- ----------------------------
-- Variant-level aggregation
-- ----------------------------
agg AS (
  SELECT
    variant,
    COUNT(*) AS users,

    AVG(sessions) AS avg_sessions_per_user,
    AVG(avg_session_duration_min) AS avg_session_duration_min,

    SUM(level_starts) AS total_level_starts,
    SUM(level_completes) AS total_level_completes,
    ROUND(1.0 * SUM(level_completes) / NULLIF(SUM(level_starts),0), 4) AS level_completion_rate,

    SUM(iap_revenue) AS total_iap_revenue,
    SUM(ads_revenue) AS total_ads_revenue,
    SUM(iap_revenue + ads_revenue) AS total_revenue,

    ROUND(1.0 * SUM(iap_revenue + ads_revenue) / NULLIF(COUNT(*),0), 4) AS arpu,

    SUM(ad_impressions) AS total_ad_impressions,
    ROUND(1.0 * SUM(ad_impressions) / NULLIF(COUNT(*),0), 2) AS ads_impressions_per_user,

    ROUND(AVG(retained_d1), 4) AS d1_retention
  FROM user_metrics
  GROUP BY 1
),

ctrl AS (SELECT * FROM agg WHERE variant='control'),
var  AS (SELECT * FROM agg WHERE variant='variant')

-- ----------------------------
-- Output: variant metrics + lift
-- ----------------------------
SELECT
  'VARIANT_METRICS' AS section,
  variant,
  users,
  avg_sessions_per_user,
  avg_session_duration_min,
  total_level_starts,
  total_level_completes,
  level_completion_rate,
  total_iap_revenue,
  total_ads_revenue,
  total_revenue,
  arpu,
  ads_impressions_per_user,
  d1_retention
FROM agg

UNION ALL

SELECT
  'LIFT_VS_CONTROL' AS section,
  'variant' AS variant,
  var.users AS users,

  -- lift metrics as % change vs control
  ROUND(100.0 * (var.avg_sessions_per_user - ctrl.avg_sessions_per_user) / NULLIF(ctrl.avg_sessions_per_user,0), 2) AS avg_sessions_per_user,
  ROUND(100.0 * (var.avg_session_duration_min - ctrl.avg_session_duration_min) / NULLIF(ctrl.avg_session_duration_min,0), 2) AS avg_session_duration_min,

  NULL AS total_level_starts,
  NULL AS total_level_completes,

  ROUND(100.0 * (var.level_completion_rate - ctrl.level_completion_rate) / NULLIF(ctrl.level_completion_rate,0), 2) AS level_completion_rate,

  ROUND(100.0 * (var.total_iap_revenue - ctrl.total_iap_revenue) / NULLIF(ctrl.total_iap_revenue,0), 2) AS total_iap_revenue,
  ROUND(100.0 * (var.total_ads_revenue - ctrl.total_ads_revenue) / NULLIF(ctrl.total_ads_revenue,0), 2) AS total_ads_revenue,

  ROUND(100.0 * (var.total_revenue - ctrl.total_revenue) / NULLIF(ctrl.total_revenue,0), 2) AS total_revenue,
  ROUND(100.0 * (var.arpu - ctrl.arpu) / NULLIF(ctrl.arpu,0), 2) AS arpu,

  ROUND(100.0 * (var.ads_impressions_per_user - ctrl.ads_impressions_per_user) / NULLIF(ctrl.ads_impressions_per_user,0), 2) AS ads_impressions_per_user,
  ROUND(100.0 * (var.d1_retention - ctrl.d1_retention) / NULLIF(ctrl.d1_retention,0), 2) AS d1_retention
FROM var, ctrl;
