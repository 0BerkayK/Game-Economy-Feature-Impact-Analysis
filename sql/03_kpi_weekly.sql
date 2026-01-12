-- 03_kpi_weekly.sql
-- Weekly game health KPIs (engagement + monetization + economy)
-- DuckDB compatible

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

-- ---------------------------------------------------------
-- DAILY ACTIVE USERS (DAU)
-- ---------------------------------------------------------
CREATE OR REPLACE TEMP VIEW dau AS
SELECT
  DATE_TRUNC('day', event_ts) AS day,
  user_id
FROM events
WHERE event_name = 'session_start'
GROUP BY 1,2;

-- ---------------------------------------------------------
-- SESSIONS + DURATION
-- ---------------------------------------------------------
CREATE OR REPLACE TEMP VIEW sessions AS
SELECT
  user_id,
  session_id,
  MIN(CASE WHEN event_name='session_start' THEN event_ts END) AS session_start_ts,
  MAX(CASE WHEN event_name='session_end' THEN event_ts END) AS session_end_ts
FROM events
GROUP BY 1,2;

CREATE OR REPLACE TEMP VIEW session_durations AS
SELECT
  DATE_TRUNC('day', session_start_ts) AS day,
  user_id,
  session_id,
  DATE_DIFF('minute', session_start_ts, session_end_ts) AS duration_min
FROM sessions
WHERE session_start_ts IS NOT NULL
  AND session_end_ts IS NOT NULL;

-- ---------------------------------------------------------
-- DAILY REVENUE (IAP + ADS)
-- ---------------------------------------------------------
CREATE OR REPLACE TEMP VIEW iap_daily AS
SELECT
  DATE_TRUNC('day', purchase_ts) AS day,
  SUM(revenue_usd) AS iap_revenue_usd,
  COUNT(*) AS iap_txn,
  COUNT(DISTINCT user_id) AS payers
FROM purchases
GROUP BY 1;

CREATE OR REPLACE TEMP VIEW ads_daily AS
SELECT
  DATE_TRUNC('day', ad_ts) AS day,
  SUM(ad_revenue_usd) AS ads_revenue_usd,
  COUNT(*) AS ad_impressions,
  COUNT(DISTINCT user_id) AS ad_viewers
FROM ads_events
GROUP BY 1;

-- ---------------------------------------------------------
-- DAILY LEVEL STATS
-- ---------------------------------------------------------
CREATE OR REPLACE TEMP VIEW level_daily AS
SELECT
  DATE_TRUNC('day', event_ts) AS day,
  SUM(CASE WHEN event_name='level_start' THEN 1 ELSE 0 END) AS level_starts,
  SUM(CASE WHEN event_name='level_complete' THEN 1 ELSE 0 END) AS level_completes
FROM events
GROUP BY 1;

-- ---------------------------------------------------------
-- RETENTION (D1 / D7) based on install cohorts
-- ---------------------------------------------------------
CREATE OR REPLACE TEMP VIEW retention_daily AS
WITH installs AS (
  SELECT user_id, DATE_TRUNC('day', install_ts) AS install_day
  FROM users
),
activity AS (
  SELECT user_id, day
  FROM dau
)
SELECT
  i.install_day AS day,
  COUNT(DISTINCT i.user_id) AS installs,
  COUNT(DISTINCT CASE WHEN a.day = i.install_day + INTERVAL 1 DAY THEN i.user_id END) AS retained_d1,
  COUNT(DISTINCT CASE WHEN a.day = i.install_day + INTERVAL 7 DAY THEN i.user_id END) AS retained_d7,
  ROUND(1.0 * COUNT(DISTINCT CASE WHEN a.day = i.install_day + INTERVAL 1 DAY THEN i.user_id END) / NULLIF(COUNT(DISTINCT i.user_id),0), 4) AS d1_retention,
  ROUND(1.0 * COUNT(DISTINCT CASE WHEN a.day = i.install_day + INTERVAL 7 DAY THEN i.user_id END) / NULLIF(COUNT(DISTINCT i.user_id),0), 4) AS d7_retention
FROM installs i
LEFT JOIN activity a
  ON i.user_id = a.user_id
 AND (a.day = i.install_day + INTERVAL 1 DAY OR a.day = i.install_day + INTERVAL 7 DAY)
GROUP BY 1;

-- ---------------------------------------------------------
-- WEEKLY AGGREGATION
-- ---------------------------------------------------------
WITH week_dau AS (
  -- For each week: unique actives in that week (WAU)
  SELECT
    DATE_TRUNC('week', day) AS week,
    COUNT(DISTINCT user_id) AS weekly_active_users
  FROM dau
  GROUP BY 1
),
week_sessions AS (
  SELECT
    DATE_TRUNC('week', day) AS week,
    COUNT(DISTINCT session_id) AS sessions,
    AVG(duration_min) AS avg_session_duration_min,
    SUM(CASE WHEN duration_min < 0 OR duration_min > 240 THEN 1 ELSE 0 END) AS suspicious_durations
  FROM session_durations
  GROUP BY 1
),
week_revenue AS (
  SELECT
    DATE_TRUNC('week', day) AS week,
    SUM(iap_revenue_usd) AS iap_revenue_usd,
    SUM(ads_revenue_usd) AS ads_revenue_usd,
    SUM(iap_txn) AS iap_txn,
    SUM(ad_impressions) AS ad_impressions,
    SUM(payers) AS payers_daily_sum,
    SUM(ad_viewers) AS ad_viewers_daily_sum
  FROM (
    SELECT
      COALESCE(i.day, a.day) AS day,
      COALESCE(i.iap_revenue_usd, 0) AS iap_revenue_usd,
      COALESCE(a.ads_revenue_usd, 0) AS ads_revenue_usd,
      COALESCE(i.iap_txn, 0) AS iap_txn,
      COALESCE(a.ad_impressions, 0) AS ad_impressions,
      COALESCE(i.payers, 0) AS payers,
      COALESCE(a.ad_viewers, 0) AS ad_viewers
    FROM iap_daily i
    FULL OUTER JOIN ads_daily a
      ON i.day = a.day
  )
  GROUP BY 1
),
week_levels AS (
  SELECT
    DATE_TRUNC('week', day) AS week,
    SUM(level_starts) AS level_starts,
    SUM(level_completes) AS level_completes,
    ROUND(1.0 * SUM(level_completes) / NULLIF(SUM(level_starts),0), 4) AS level_completion_rate
  FROM level_daily
  GROUP BY 1
),
week_retention AS (
  SELECT
    DATE_TRUNC('week', day) AS week,
    AVG(d1_retention) AS avg_d1_retention,
    AVG(d7_retention) AS avg_d7_retention
  FROM retention_daily
  GROUP BY 1
)
SELECT
  d.week,
  d.weekly_active_users,
  s.sessions,
  ROUND(1.0 * s.sessions / NULLIF(d.weekly_active_users,0), 3) AS sessions_per_user,
  ROUND(s.avg_session_duration_min, 2) AS avg_session_duration_min,
  s.suspicious_durations,

  r.iap_revenue_usd,
  r.ads_revenue_usd,
  (r.iap_revenue_usd + r.ads_revenue_usd) AS total_revenue_usd,

  ROUND(1.0 * (r.iap_revenue_usd + r.ads_revenue_usd) / NULLIF(d.weekly_active_users,0), 4) AS approx_arpwau,

  l.level_starts,
  l.level_completes,
  l.level_completion_rate,

  w.avg_d1_retention,
  w.avg_d7_retention,

  r.ad_impressions,
  r.iap_txn
FROM week_dau d
LEFT JOIN week_sessions s ON d.week = s.week
LEFT JOIN week_revenue r ON d.week = r.week
LEFT JOIN week_levels l ON d.week = l.week
LEFT JOIN week_retention w ON d.week = w.week
ORDER BY d.week;
