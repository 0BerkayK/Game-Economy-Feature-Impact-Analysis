-- 02_funnel_analysis.sql
-- Funnel: install -> session_start -> level_start -> level_complete
-- + per-day funnel health (to catch tracking breaks)

CREATE OR REPLACE VIEW users AS
SELECT * FROM read_csv_auto('data/users.csv');

CREATE OR REPLACE VIEW events AS
SELECT *
FROM read_csv_auto('data/events.csv')
WHERE event_ts >= TIMESTAMP '2025-10-01'
  AND event_ts <= TIMESTAMP '2025-12-31 23:59:00';

-- First occurrences per user
WITH firsts AS (
  SELECT
    u.user_id,
    DATE_TRUNC('day', u.install_ts) AS install_day,
    MIN(CASE WHEN e.event_name = 'session_start' THEN e.event_ts END) AS first_session_ts,
    MIN(CASE WHEN e.event_name = 'level_start' THEN e.event_ts END) AS first_level_start_ts,
    MIN(CASE WHEN e.event_name = 'level_complete' THEN e.event_ts END) AS first_level_complete_ts
  FROM users u
  LEFT JOIN events e
    ON u.user_id = e.user_id
  GROUP BY 1,2
),
flags AS (
  SELECT
    user_id,
    install_day,
    first_session_ts IS NOT NULL AS has_session,
    first_level_start_ts IS NOT NULL AS has_level_start,
    first_level_complete_ts IS NOT NULL AS has_level_complete
  FROM firsts
)
SELECT
  'FUNNEL_OVERALL' AS section,
  COUNT(*) AS installs,
  SUM(CASE WHEN has_session THEN 1 ELSE 0 END) AS to_session,
  SUM(CASE WHEN has_level_start THEN 1 ELSE 0 END) AS to_level_start,
  SUM(CASE WHEN has_level_complete THEN 1 ELSE 0 END) AS to_level_complete,
  ROUND(1.0 * SUM(CASE WHEN has_session THEN 1 ELSE 0 END) / COUNT(*), 4) AS cr_install_to_session,
  ROUND(
    1.0 * SUM(CASE WHEN has_level_start THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN has_session THEN 1 ELSE 0 END), 0),
    4
  ) AS cr_session_to_level_start,
  ROUND(
    1.0 * SUM(CASE WHEN has_level_complete THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN has_level_start THEN 1 ELSE 0 END), 0),
    4
  ) AS cr_level_start_to_complete
FROM flags;

-- Per-day funnel
WITH firsts AS (
  SELECT
    u.user_id,
    DATE_TRUNC('day', u.install_ts) AS install_day,
    MIN(CASE WHEN e.event_name = 'session_start' THEN e.event_ts END) AS first_session_ts,
    MIN(CASE WHEN e.event_name = 'level_start' THEN e.event_ts END) AS first_level_start_ts,
    MIN(CASE WHEN e.event_name = 'level_complete' THEN e.event_ts END) AS first_level_complete_ts
  FROM users u
  LEFT JOIN events e
    ON u.user_id = e.user_id
  GROUP BY 1,2
)
SELECT
  'FUNNEL_BY_INSTALL_DAY' AS section,
  install_day,
  COUNT(*) AS installs,
  ROUND(1.0 * SUM(CASE WHEN first_session_ts IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 4) AS cr_install_to_session,
  ROUND(
    1.0 * SUM(CASE WHEN first_level_start_ts IS NOT NULL THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN first_session_ts IS NOT NULL THEN 1 ELSE 0 END), 0),
    4
  ) AS cr_session_to_level_start,
  ROUND(
    1.0 * SUM(CASE WHEN first_level_complete_ts IS NOT NULL THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN first_level_start_ts IS NOT NULL THEN 1 ELSE 0 END), 0),
    4
  ) AS cr_level_start_to_complete
FROM firsts
GROUP BY 1,2
ORDER BY install_day;

-- Debug lists (sample)
WITH firsts AS (
  SELECT
    u.user_id,
    u.install_ts,
    MIN(CASE WHEN e.event_name = 'session_start' THEN e.event_ts END) AS first_session_ts,
    MIN(CASE WHEN e.event_name = 'level_start' THEN e.event_ts END) AS first_level_start_ts,
    MIN(CASE WHEN e.event_name = 'level_complete' THEN e.event_ts END) AS first_level_complete_ts
  FROM users u
  LEFT JOIN events e
    ON u.user_id = e.user_id
  GROUP BY 1,2
)
SELECT
  'DEBUG_SESSION_NO_LEVEL_START' AS section,
  user_id, install_ts, first_session_ts
FROM firsts
WHERE first_session_ts IS NOT NULL AND first_level_start_ts IS NULL
LIMIT 50;

WITH firsts AS (
  SELECT
    u.user_id,
    u.install_ts,
    MIN(CASE WHEN e.event_name = 'level_start' THEN e.event_ts END) AS first_level_start_ts,
    MIN(CASE WHEN e.event_name = 'level_complete' THEN e.event_ts END) AS first_level_complete_ts
  FROM users u
  LEFT JOIN events e
    ON u.user_id = e.user_id
  GROUP BY 1,2
)
SELECT
  'DEBUG_LEVEL_START_NO_COMPLETE' AS section,
  user_id, install_ts, first_level_start_ts
FROM firsts
WHERE first_level_start_ts IS NOT NULL AND first_level_complete_ts IS NULL
LIMIT 50;
