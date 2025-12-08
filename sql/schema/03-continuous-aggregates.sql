-- ============================================================================
-- Continuous Aggregates for Ignition Tag History
-- ============================================================================
-- Description: Creates hierarchical continuous aggregates for multi-resolution data
-- Version: 1.3.0
-- Last Updated: 2025-12-08
-- Prerequisites: 
--   - Hypertables configured
--   - Data being collected in sqlth_1_data
-- Maintained by: Miller-Eads Automation
-- ============================================================================

-- Usage: psql -U postgres -d historian -f 03-continuous-aggregates.sql

\echo '============================================================================'
\echo 'Continuous Aggregates Setup'
\echo '============================================================================'
\echo ''

\c historian

-- ============================================================================
-- Tier 1: 1-Minute Aggregates
-- ============================================================================

\echo 'Creating 1-minute continuous aggregate...'

CREATE MATERIALIZED VIEW IF NOT EXISTS tag_history_1min
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 minute', t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS avg_value,
    MAX(COALESCE(intvalue, floatvalue)) AS max_value,
    MIN(COALESCE(intvalue, floatvalue)) AS min_value,
    STDDEV(COALESCE(intvalue, floatvalue)) AS stddev_value,
    COUNT(*) AS sample_count,
    SUM(CASE WHEN dataintegrity = 192 THEN 1 ELSE 0 END) AS good_count,
    MAX(dataintegrity) AS worst_quality
FROM sqlth_1_data
WHERE dataintegrity = 192  -- Good quality only
GROUP BY bucket, tagid;

\echo '✓ 1-minute aggregate view created'

-- Add refresh policy (refresh every 5 minutes for data from last hour)
SELECT add_continuous_aggregate_policy('tag_history_1min',
    start_offset => INTERVAL '1 hour',
    end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '5 minutes');

\echo '✓ Refresh policy added (every 5 minutes)'

-- Add retention policy (keep for 1 year)
SELECT add_retention_policy('tag_history_1min', INTERVAL '1 year');

\echo '✓ Retention policy added (1 year)'
\echo ''

-- ============================================================================
-- Tier 2: Hourly Aggregates (from 1-minute data)
-- ============================================================================

\echo 'Creating hourly continuous aggregate...'

CREATE MATERIALIZED VIEW IF NOT EXISTS tag_history_1hour
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    AVG(stddev_value) AS avg_stddev,
    SUM(sample_count) AS total_samples,
    SUM(good_count) AS total_good_samples
FROM tag_history_1min
GROUP BY bucket, tagid;

\echo '✓ Hourly aggregate view created'

-- Add refresh policy
SELECT add_continuous_aggregate_policy('tag_history_1hour',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

\echo '✓ Refresh policy added (every 1 hour)'

-- Add retention policy (keep for 5 years)
SELECT add_retention_policy('tag_history_1hour', INTERVAL '5 years');

\echo '✓ Retention policy added (5 years)'
\echo ''

-- ============================================================================
-- Tier 3: Daily Aggregates (from hourly data)
-- ============================================================================

\echo 'Creating daily continuous aggregate...'

CREATE MATERIALIZED VIEW IF NOT EXISTS tag_history_1day
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    SUM(total_samples) AS total_samples
FROM tag_history_1hour
GROUP BY bucket, tagid;

\echo '✓ Daily aggregate view created'

-- Add refresh policy
SELECT add_continuous_aggregate_policy('tag_history_1day',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');

\echo '✓ Refresh policy added (daily)'

-- Add retention policy (keep for 10 years)
SELECT add_retention_policy('tag_history_1day', INTERVAL '10 years');

\echo '✓ Retention policy added (10 years)'
\echo ''

-- ============================================================================
-- Tier 4: Weekly Aggregates (optional)
-- ============================================================================

\echo 'Creating weekly continuous aggregate...'

CREATE MATERIALIZED VIEW IF NOT EXISTS tag_history_1week
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 week', bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    SUM(total_samples) AS total_samples
FROM tag_history_1day
GROUP BY bucket, tagid;

\echo '✓ Weekly aggregate view created'

-- Add refresh policy
SELECT add_continuous_aggregate_policy('tag_history_1week',
    start_offset => INTERVAL '4 weeks',
    end_offset => INTERVAL '1 week',
    schedule_interval => INTERVAL '1 week');

\echo '✓ Refresh policy added (weekly)'
\echo ''

-- ============================================================================
-- Tier 5: Monthly Aggregates
-- ============================================================================

\echo 'Creating monthly continuous aggregate...'

CREATE MATERIALIZED VIEW IF NOT EXISTS tag_history_1month
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 month', bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    SUM(total_samples) AS total_samples
FROM tag_history_1day
GROUP BY bucket, tagid;

\echo '✓ Monthly aggregate view created'

-- Add refresh policy
SELECT add_continuous_aggregate_policy('tag_history_1month',
    start_offset => INTERVAL '3 months',
    end_offset => INTERVAL '1 month',
    schedule_interval => INTERVAL '1 month');

\echo '✓ Refresh policy added (monthly)'
\echo ''

-- ============================================================================
-- Create Helper Views with Tag Names
-- ============================================================================

\echo 'Creating helper views with tag paths...'

-- 1-minute view with tag names
CREATE OR REPLACE VIEW tag_history_1min_named AS
SELECT 
    m.bucket,
    t.tagpath,
    m.avg_value,
    m.max_value,
    m.min_value,
    m.stddev_value,
    m.sample_count,
    m.good_count,
    m.worst_quality
FROM tag_history_1min m
JOIN sqlth_te t ON m.tagid = t.id
WHERE t.retired IS NULL;

\echo '✓ tag_history_1min_named view created'

-- Hourly view with tag names
CREATE OR REPLACE VIEW tag_history_1hour_named AS
SELECT 
    m.bucket,
    t.tagpath,
    m.avg_value,
    m.max_value,
    m.min_value,
    m.avg_stddev,
    m.total_samples
FROM tag_history_1hour m
JOIN sqlth_te t ON m.tagid = t.id
WHERE t.retired IS NULL;

\echo '✓ tag_history_1hour_named view created'

-- Daily view with tag names
CREATE OR REPLACE VIEW tag_history_1day_named AS
SELECT 
    m.bucket,
    t.tagpath,
    m.avg_value,
    m.max_value,
    m.min_value,
    m.total_samples
FROM tag_history_1day m
JOIN sqlth_te t ON m.tagid = t.id
WHERE t.retired IS NULL;

\echo '✓ tag_history_1day_named view created'
\echo ''

-- ============================================================================
-- Grant Permissions
-- ============================================================================

\echo 'Granting permissions to ignition user...'

GRANT SELECT ON tag_history_1min TO ignition;
GRANT SELECT ON tag_history_1hour TO ignition;
GRANT SELECT ON tag_history_1day TO ignition;
GRANT SELECT ON tag_history_1week TO ignition;
GRANT SELECT ON tag_history_1month TO ignition;

GRANT SELECT ON tag_history_1min_named TO ignition;
GRANT SELECT ON tag_history_1hour_named TO ignition;
GRANT SELECT ON tag_history_1day_named TO ignition;

\echo '✓ Permissions granted'
\echo ''

-- ============================================================================
-- Verification
-- ============================================================================

\echo '============================================================================'
\echo 'Continuous Aggregates Summary'
\echo '============================================================================'

-- List all continuous aggregates
SELECT 
    view_name,
    materialization_hypertable_schema || '.' || materialization_hypertable_name AS materialized_table,
    refresh_lag,
    compression_enabled
FROM timescaledb_information.continuous_aggregates
ORDER BY view_name;

\echo ''
\echo 'Aggregate Policies:'

-- List aggregate policies
SELECT 
    application_name,
    hypertable_name,
    schedule_interval,
    config,
    next_start
FROM timescaledb_information.jobs
WHERE application_name LIKE '%policy%'
ORDER BY hypertable_name, application_name;

\echo ''
\echo '============================================================================'
\echo 'Configuration Complete!'
\echo '============================================================================'
\echo ''
\echo 'Created continuous aggregates:'
\echo '  ✓ tag_history_1min   - 1-minute resolution (kept for 1 year)'
\echo '  ✓ tag_history_1hour  - Hourly resolution (kept for 5 years)'
\echo '  ✓ tag_history_1day   - Daily resolution (kept for 10 years)'
\echo '  ✓ tag_history_1week  - Weekly resolution'
\echo '  ✓ tag_history_1month - Monthly resolution'
\echo ''
\echo 'Helper views (with tag paths):'
\echo '  ✓ tag_history_1min_named'
\echo '  ✓ tag_history_1hour_named'
\echo '  ✓ tag_history_1day_named'
\echo ''
\echo 'Usage Examples:'
\echo '  -- Get hourly averages for last 30 days'
\echo '  SELECT * FROM tag_history_1hour_named'
\echo '  WHERE tagpath = ''[default]Production/Temperature'''
\echo '    AND bucket >= NOW() - INTERVAL ''30 days'';'
\echo ''
\echo '  -- Get daily min/max for a year'
\echo '  SELECT bucket::date, tagpath, min_value, max_value'
\echo '  FROM tag_history_1day_named'
\echo '  WHERE tagpath LIKE ''%Production%'''
\echo '    AND bucket >= NOW() - INTERVAL ''1 year'';'
\echo ''
\echo 'Next Steps:'
\echo '  1. Wait for data to accumulate'
\echo '  2. Create DB Table Historian in Ignition to expose these views'
\echo '  3. Use aggregates in Power Chart and Easy Chart'
\echo '  4. Build custom dashboards and reports'
\echo '============================================================================'
