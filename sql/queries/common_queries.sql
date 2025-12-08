-- ============================================================================
-- Common Query Library for Ignition TimescaleDB
-- ============================================================================
-- Description: Frequently used queries for tag history analysis
-- Version: 1.3.0
-- Last Updated: 2025-12-08
-- ============================================================================

-- =============================================================================
-- TIME-BASED QUERIES
-- =============================================================================

-- Query 1: Last Hour of Data
-- Usage: Get recent data for all tags
SELECT 
    t.tagpath,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value,
    d.dataintegrity as quality
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
ORDER BY d.t_stamp DESC;

-- Query 2: Specific Date Range
-- Usage: Get data for a specific tag and date range
SELECT 
    to_timestamp(t_stamp / 1000) as timestamp,
    COALESCE(intvalue, floatvalue) as value
FROM sqlth_1_data
WHERE tagid = (SELECT id FROM sqlth_te WHERE tagpath = '[default]Production/Temperature')
  AND t_stamp >= (EXTRACT(EPOCH FROM '2025-12-01 00:00:00'::timestamp) * 1000)
  AND t_stamp < (EXTRACT(EPOCH FROM '2025-12-02 00:00:00'::timestamp) * 1000)
ORDER BY t_stamp;

-- Query 3: Last 24 Hours by Tag Path
-- Usage: Query by tag path with good quality filter
SELECT 
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
  AND d.dataintegrity = 192  -- Good quality only
ORDER BY d.t_stamp;

-- =============================================================================
-- AGGREGATION QUERIES
-- =============================================================================

-- Query 4: Hourly Averages (Last 7 Days)
-- Usage: Calculate hourly statistics using time_bucket
SELECT 
    time_bucket(3600000, d.t_stamp) as hour_bucket,
    to_timestamp(time_bucket(3600000, d.t_stamp) / 1000) as hour,
    AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value,
    MIN(COALESCE(d.intvalue, d.floatvalue)) as min_value,
    MAX(COALESCE(d.intvalue, d.floatvalue)) as max_value,
    COUNT(*) as sample_count
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
  AND d.dataintegrity = 192
GROUP BY hour_bucket
ORDER BY hour_bucket DESC;

-- Query 5: Daily Statistics (Last 30 Days)
-- Usage: Daily min/max/avg with standard deviation
SELECT 
    DATE(to_timestamp(time_bucket(86400000, t_stamp) / 1000)) as day,
    COUNT(*) as samples,
    AVG(COALESCE(intvalue, floatvalue)) as avg_value,
    STDDEV(COALESCE(intvalue, floatvalue)) as std_dev,
    MIN(COALESCE(intvalue, floatvalue)) as min_value,
    MAX(COALESCE(intvalue, floatvalue)) as max_value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
  AND dataintegrity = 192
GROUP BY day
ORDER BY day DESC;

-- Query 6: Monthly Summary
-- Usage: Monthly aggregates for trending
SELECT 
    DATE_TRUNC('month', to_timestamp(t_stamp / 1000)) as month,
    COUNT(*) as total_samples,
    AVG(COALESCE(intvalue, floatvalue)) as monthly_avg,
    MIN(COALESCE(intvalue, floatvalue)) as monthly_min,
    MAX(COALESCE(intvalue, floatvalue)) as monthly_max
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 year') * 1000)
GROUP BY month
ORDER BY month DESC;

-- =============================================================================
-- MULTI-TAG QUERIES
-- =============================================================================

-- Query 7: Multiple Tags Comparison
-- Usage: Compare multiple tags side by side
SELECT 
    to_timestamp(d.t_stamp / 1000) as timestamp,
    t.tagpath,
    COALESCE(d.intvalue, d.floatvalue) as value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath IN (
    '[default]Production/Temperature',
    '[default]Production/Pressure',
    '[default]Production/FlowRate'
)
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
  AND d.dataintegrity = 192
ORDER BY d.t_stamp DESC, t.tagpath;

-- Query 8: Tag Group Pattern Match
-- Usage: Get all tags matching a pattern
SELECT 
    t.tagpath,
    COUNT(*) as sample_count,
    AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value,
    MIN(COALESCE(d.intvalue, d.floatvalue)) as min_value,
    MAX(COALESCE(d.intvalue, d.floatvalue)) as max_value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath LIKE '[default]Production/%'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
  AND d.dataintegrity = 192
GROUP BY t.tagpath
ORDER BY t.tagpath;

-- Query 9: Latest Value Per Tag
-- Usage: Get most recent value for each tag
SELECT DISTINCT ON (d.tagid)
    t.tagpath,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value,
    d.dataintegrity
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath LIKE '[default]Production/%'
  AND t.retired IS NULL
ORDER BY d.tagid, d.t_stamp DESC;

-- =============================================================================
-- DATA QUALITY QUERIES
-- =============================================================================

-- Query 10: Quality Code Distribution
-- Usage: Analyze data quality over time
SELECT 
    DATE(to_timestamp(t_stamp / 1000)) as day,
    dataintegrity,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY DATE(to_timestamp(t_stamp / 1000))), 2) as percentage
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
GROUP BY day, dataintegrity
ORDER BY day DESC, dataintegrity;

-- Query 11: Missing Data Gaps
-- Usage: Identify time gaps in data collection
WITH expected_samples AS (
    SELECT 
        time_bucket(3600000, t_stamp) as hour_bucket,
        COUNT(*) as actual_samples
    FROM sqlth_1_data
    WHERE tagid = (SELECT id FROM sqlth_te WHERE tagpath = '[default]Production/Temperature')
      AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
    GROUP BY hour_bucket
)
SELECT 
    to_timestamp(hour_bucket / 1000) as hour,
    actual_samples,
    CASE 
        WHEN actual_samples < 3000 THEN 'LOW'  -- Less than expected for 1-second scan
        ELSE 'OK'
    END as status
FROM expected_samples
WHERE actual_samples < 3000
ORDER BY hour_bucket DESC;

-- Query 12: Bad Quality Data Count
-- Usage: Count non-good quality samples
SELECT 
    t.tagpath,
    COUNT(*) as bad_samples,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM sqlth_1_data WHERE tagid = d.tagid) as bad_percentage
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.dataintegrity != 192
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
GROUP BY t.tagpath, d.tagid
HAVING COUNT(*) > 100
ORDER BY bad_samples DESC;

-- =============================================================================
-- PERFORMANCE QUERIES
-- =============================================================================

-- Query 13: Sample Rate Analysis
-- Usage: Calculate actual sample rate per tag
SELECT 
    t.tagpath,
    COUNT(*) as total_samples,
    EXTRACT(EPOCH FROM (MAX(to_timestamp(d.t_stamp/1000)) - MIN(to_timestamp(d.t_stamp/1000)))) as time_span_seconds,
    ROUND(
        COUNT(*)::numeric / 
        EXTRACT(EPOCH FROM (MAX(to_timestamp(d.t_stamp/1000)) - MIN(to_timestamp(d.t_stamp/1000)))),
        2
    ) as samples_per_second
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
  AND t.retired IS NULL
GROUP BY t.tagpath
HAVING COUNT(*) > 100
ORDER BY samples_per_second DESC;

-- Query 14: Tag Activity
-- Usage: Find most/least active tags
SELECT 
    t.tagpath,
    COUNT(*) as sample_count,
    MIN(to_timestamp(d.t_stamp/1000)) as first_sample,
    MAX(to_timestamp(d.t_stamp/1000)) as last_sample,
    NOW() - MAX(to_timestamp(d.t_stamp/1000)) as time_since_last
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
GROUP BY t.tagpath
ORDER BY sample_count DESC
LIMIT 20;

-- =============================================================================
-- ADVANCED ANALYTICS
-- =============================================================================

-- Query 15: Moving Average (Last 100 samples)
-- Usage: Calculate rolling average
SELECT 
    to_timestamp(t_stamp / 1000) as timestamp,
    COALESCE(intvalue, floatvalue) as value,
    AVG(COALESCE(intvalue, floatvalue)) OVER (
        ORDER BY t_stamp 
        ROWS BETWEEN 99 PRECEDING AND CURRENT ROW
    ) as moving_avg_100
FROM sqlth_1_data
WHERE tagid = (SELECT id FROM sqlth_te WHERE tagpath = '[default]Production/Temperature')
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
ORDER BY t_stamp DESC;

-- Query 16: Rate of Change
-- Usage: Calculate value change rate
SELECT 
    to_timestamp(t_stamp / 1000) as timestamp,
    COALESCE(intvalue, floatvalue) as value,
    COALESCE(intvalue, floatvalue) - LAG(COALESCE(intvalue, floatvalue)) OVER (ORDER BY t_stamp) as change,
    (t_stamp - LAG(t_stamp) OVER (ORDER BY t_stamp)) / 1000.0 as time_delta_sec
FROM sqlth_1_data
WHERE tagid = (SELECT id FROM sqlth_te WHERE tagpath = '[default]Production/Temperature')
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
ORDER BY t_stamp DESC;

-- Query 17: Percentile Analysis
-- Usage: Calculate percentiles for tag values
SELECT 
    t.tagpath,
    PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY COALESCE(d.intvalue, d.floatvalue)) as p01,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(d.intvalue, d.floatvalue)) as p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY COALESCE(d.intvalue, d.floatvalue)) as p50_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(d.intvalue, d.floatvalue)) as p75,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY COALESCE(d.intvalue, d.floatvalue)) as p99
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
  AND d.dataintegrity = 192
  AND t.tagpath LIKE '[default]Production/%'
GROUP BY t.tagpath;

-- =============================================================================
-- TAG METADATA QUERIES
-- =============================================================================

-- Query 18: Active Tags List
-- Usage: Get all active (non-retired) tags
SELECT 
    id as tagid,
    tagpath,
    datatype,
    to_timestamp(created / 1000) as created_date,
    retired
FROM sqlth_te
WHERE retired IS NULL
ORDER BY tagpath;

-- Query 19: Tag History Enablement Check
-- Usage: Find tags with recent activity
SELECT 
    t.tagpath,
    MAX(to_timestamp(d.t_stamp / 1000)) as last_update,
    NOW() - MAX(to_timestamp(d.t_stamp / 1000)) as time_since_update,
    COUNT(*) as sample_count_24h
FROM sqlth_te t
LEFT JOIN sqlth_1_data d ON t.id = d.tagid
    AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
WHERE t.retired IS NULL
GROUP BY t.tagpath
ORDER BY last_update DESC NULLS LAST;

-- Query 20: Storage Usage Per Tag
-- Usage: Estimate storage per tag (approximation)
SELECT 
    t.tagpath,
    COUNT(*) as total_samples,
    pg_size_pretty(COUNT(*) * 32) as estimated_size  -- Rough estimate: 32 bytes per row
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
GROUP BY t.tagpath
ORDER BY COUNT(*) DESC
LIMIT 20;

-- ============================================================================
-- END OF COMMON QUERIES
-- ============================================================================
