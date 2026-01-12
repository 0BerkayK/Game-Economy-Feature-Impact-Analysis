
-- Goal: validate data consistency, schema sanity, duplicates, timestamp ranges

-- DuckDB: create views from CSVs

CREATE OR REPLACE VIEW users AS
SELECT * FROM read_csv_auto('data/users.csv');

CREATE OR REPLACE VIEW ab_assignments AS
SELECT * FROM read_csv_auto('data/ab_assignments.csv');

CREATE OR REPLACE VIEW events AS
SELECT *
FROM read_csv_auto('data/events.csv')
WHERE event_ts >= TIMESTAMP '2025-10-01'
  AND event_ts <  TIMESTAMP '2026-01-01';


CREATE OR REPLACE VIEW purchases AS
SELECT * FROM read_csv_auto('data/purchases.csv');

CREATE OR REPLACE VIEW ads_events AS
SELECT *
FROM read_csv_auto('data/ads_events.csv')
WHERE ad_ts >= TIMESTAMP '2025-10-01'
  AND ad_ts <  TIMESTAMP '2026-01-01';


-- 1) Row counts
SELECT 'users' AS table_name, COUNT(*) AS n FROM users
UNION ALL SELECT 'ab_assignments', COUNT(*) FROM ab_assignments
UNION ALL SELECT 'events', COUNT(*) FROM events
UNION ALL SELECT 'purchases', COUNT(*) FROM purchases
UNION ALL SELECT 'ads_events', COUNT(*) FROM ads_events;

-- 2) Null checks (critical columns)
SELECT
  SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS null_user_id,
  SUM(CASE WHEN install_ts IS NULL THEN 1 ELSE 0 END) AS null_install_ts
FROM users;

SELECT
  SUM(CASE WHEN event_ts IS NULL THEN 1 ELSE 0 END) AS null_event_ts,
  SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS null_user_id,
  SUM(CASE WHEN session_id IS NULL THEN 1 ELSE 0 END) AS null_session_id,
  SUM(CASE WHEN event_name IS NULL THEN 1 ELSE 0 END) AS null_event_name
FROM events;

-- 3) Timestamp range checks
SELECT
  MIN(install_ts) AS min_install_ts,
  MAX(install_ts) AS max_install_ts
FROM users;

SELECT
  MIN(event_ts) AS min_event_ts,
  MAX(event_ts) AS max_event_ts
FROM events;

SELECT
  MIN(purchase_ts) AS min_purchase_ts,
  MAX(purchase_ts) AS max_purchase_ts
FROM purchases;

-- 4) Duplicate checks
-- Users should be unique
SELECT user_id, COUNT(*) AS cnt
FROM users
GROUP BY 1
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 50;

-- Events duplicates: exact same (user_id, session_id, event_name, event_ts)
SELECT user_id, session_id, event_name, event_ts, COUNT(*) AS cnt
FROM events
GROUP BY 1,2,3,4
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 50;

-- 5) Session ordering sanity
-- session_end should be after session_start
WITH sess AS (
  SELECT
    user_id,
    session_id,
    MIN(CASE WHEN event_name='session_start' THEN event_ts END) AS session_start_ts,
    MAX(CASE WHEN event_name='session_end' THEN event_ts END) AS session_end_ts
  FROM events
  GROUP BY 1,2
)
SELECT *
FROM sess
WHERE session_start_ts IS NOT NULL
  AND session_end_ts IS NOT NULL
  AND session_end_ts < session_start_ts
LIMIT 50;

-- 6) Event name distribution (spot oddities)
SELECT event_name, COUNT(*) AS n
FROM events
GROUP BY 1
ORDER BY n DESC;

-- 7) Missing critical events per session
-- sessions that have start but no end
WITH sess AS (
  SELECT
    user_id,
    session_id,
    MAX(CASE WHEN event_name='session_start' THEN 1 ELSE 0 END) AS has_start,
    MAX(CASE WHEN event_name='session_end' THEN 1 ELSE 0 END) AS has_end
  FROM events
  GROUP BY 1,2
)
SELECT
  SUM(CASE WHEN has_start=1 AND has_end=0 THEN 1 ELSE 0 END) AS sessions_missing_end,
  SUM(CASE WHEN has_start=0 AND has_end=1 THEN 1 ELSE 0 END) AS sessions_missing_start,
  COUNT(*) AS total_sessions
FROM sess;

-- 8) Currency sanity checks
-- currency_balance should not be negative (soft check)
SELECT *
FROM events
WHERE currency_balance IS NOT NULL AND currency_balance < 0
LIMIT 50;

-- currency_delta should be non-negative for level_complete (reward)
SELECT *
FROM events
WHERE event_name='level_complete'
  AND currency_delta IS NOT NULL
  AND currency_delta < 0
LIMIT 50;


-- (FORCE OUTPUT) Row counts again
SELECT 'users' AS table_name, COUNT(*) AS n FROM users
UNION ALL SELECT 'ab_assignments', COUNT(*) FROM ab_assignments
UNION ALL SELECT 'events', COUNT(*) FROM events
UNION ALL SELECT 'purchases', COUNT(*) FROM purchases
UNION ALL SELECT 'ads_events', COUNT(*) FROM ads_events
;

-- (FORCE OUTPUT) sessions missing start/end
WITH sess AS (
  SELECT
    user_id,
    session_id,
    MAX(CASE WHEN event_name='session_start' THEN 1 ELSE 0 END) AS has_start,
    MAX(CASE WHEN event_name='session_end' THEN 1 ELSE 0 END) AS has_end
  FROM events
  GROUP BY 1,2
)
SELECT
  SUM(CASE WHEN has_start=1 AND has_end=0 THEN 1 ELSE 0 END) AS sessions_missing_end,
  SUM(CASE WHEN has_start=0 AND has_end=1 THEN 1 ELSE 0 END) AS sessions_missing_start,
  COUNT(*) AS total_sessions
FROM sess
;
