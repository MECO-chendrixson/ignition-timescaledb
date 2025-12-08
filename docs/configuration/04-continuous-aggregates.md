# Continuous Aggregates Configuration

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate  
**Estimated Time:** 25-35 minutes  
**Prerequisites:** 
- Hypertable created and configured
- Data being collected in historian
- Understanding of query patterns and reporting needs
- Compression enabled (recommended)

## Overview

Continuous aggregates enable multi-resolution downsampling by automatically maintaining pre-aggregated views of your time-series data. This guide covers creating hierarchical aggregates (1-minute, hourly, daily, etc.), configuring refresh policies, and using aggregates in Ignition for fast queries over long time periods.

---

## Why Continuous Aggregates Matter

### Query Performance

**Without Continuous Aggregates:**
```sql
-- Query 1 year of 1-second data: 31.5M rows per tag
SELECT AVG(value) FROM sqlth_1_data 
WHERE tagid = 100 AND t_stamp >= NOW() - INTERVAL '1 year';
-- Execution time: 5-30 seconds
```

**With Continuous Aggregates:**
```sql
-- Query pre-aggregated daily data: 365 rows per tag
SELECT AVG(avg_value) FROM tag_history_1day
WHERE tagid = 100 AND bucket >= NOW() - INTERVAL '1 year';
-- Execution time: <100ms (50-300x faster)
```

### Key Benefits

| Benefit | Impact |
|---------|--------|
| **50-1000x faster queries** | Near-instant long-range queries |
| **Automatic maintenance** | No manual aggregation needed |
| **Always up-to-date** | Refresh policies keep data current |
| **Hierarchical downsampling** | Multiple resolutions for different needs |
| **Storage efficient** | Much smaller than raw data |
| **Transparent to queries** | Use like regular tables |

### How They Work

```
Raw Data (sqlth_1_data):
├─ 1-second samples
└─ Compressed after 7 days
    ↓
1-Minute Aggregates (tag_history_1min):
├─ 60x data reduction
├─ Auto-refreshed every 5 minutes
└─ Kept for 1 year
    ↓
Hourly Aggregates (tag_history_1hour):
├─ 3600x data reduction
├─ Auto-refreshed every hour
└─ Kept for 5 years
    ↓
Daily Aggregates (tag_history_1day):
├─ 86,400x data reduction
├─ Auto-refreshed daily
└─ Kept for 10+ years
```

---

## Understanding Continuous Aggregates

### What is a Continuous Aggregate?

A **continuous aggregate** is a materialized view that:

- **Automatically pre-computes** aggregations (AVG, MIN, MAX, COUNT, etc.)
- **Incrementally refreshes** only new/changed data
- **Maintains historical data** according to retention policies
- **Queries like a table** with standard SQL

### Continuous vs. Regular Materialized Views

| Feature | Continuous Aggregate | Regular Materialized View |
|---------|---------------------|--------------------------|
| **Refresh** | Incremental (only new data) | Full rebuild |
| **Performance** | Fast refresh | Slow for large tables |
| **Real-time** | Near real-time | Manual refresh |
| **Storage** | Hypertable (compressed) | Regular table |
| **Retention** | Automatic policies | Manual management |

### Time Bucket Concept

```sql
time_bucket(3600000, t_stamp)
```

**What it does:**
- Groups timestamps into fixed intervals
- Aligns to interval boundaries (e.g., 00:00, 01:00, 02:00)
- Enables efficient aggregation and querying

**Example:**
```
Timestamps:         time_bucket(3600000, t_stamp):
10:15:23  ───────►  10:00:00
10:42:17  ───────►  10:00:00
11:05:44  ───────►  11:00:00
11:58:02  ───────►  11:00:00
```

---

## Hierarchical Aggregate Strategy

### Standard Multi-Tier Setup (Recommended)

```
Resolution Pyramid:

Raw Data (1-second scan rate)
└─ Retention: 2 years
   └─ Query Use: Recent detailed analysis

1-Minute Aggregates
└─ Retention: 1 year
   └─ Query Use: Hourly to monthly trends

Hourly Aggregates  
└─ Retention: 5 years
   └─ Query Use: Monthly to yearly trends

Daily Aggregates
└─ Retention: 10 years
   └─ Query Use: Long-term trending, reports

Monthly Aggregates (optional)
└─ Retention: 20+ years
   └─ Query Use: Historical analysis, compliance
```

### When to Use Each Resolution

| Time Range | Use Aggregate | Reason |
|------------|---------------|--------|
| Last 24 hours | Raw data | Full detail available |
| Last week | 1-minute | Balance detail vs. performance |
| Last month | 1-minute or hourly | Trend analysis |
| Last year | Hourly or daily | Annual reports |
| Multi-year | Daily or monthly | Historical analysis |
| 10+ years | Monthly | Long-term trends only |

---

## Creating Continuous Aggregates

### Method 1: Automated Script (Recommended)

Use the provided SQL script for complete hierarchical setup:

```bash
# Run the continuous aggregates script
psql -U postgres -d historian -f sql/schema/03-continuous-aggregates.sql
```

**This script automatically creates:**
- ✅ 1-minute aggregates with refresh policy
- ✅ Hourly aggregates (from 1-minute data)
- ✅ Daily aggregates (from hourly data)
- ✅ Weekly aggregates (optional)
- ✅ Monthly aggregates (optional)
- ✅ Helper views with tag names
- ✅ Retention policies for each tier
- ✅ Appropriate permissions

**Skip to [Verification](#verification) section after running the script.**

---

### Method 2: Manual Step-by-Step

For learning or custom configurations, create aggregates manually.

#### Step 1: Create 1-Minute Aggregate

```sql
-- Connect to historian database
\c historian

-- Create 1-minute continuous aggregate
CREATE MATERIALIZED VIEW tag_history_1min
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(60000, t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS avg_value,
    MAX(COALESCE(intvalue, floatvalue)) AS max_value,
    MIN(COALESCE(intvalue, floatvalue)) AS min_value,
    STDDEV(COALESCE(intvalue, floatvalue)) AS stddev_value,
    COUNT(*) AS sample_count,
    SUM(CASE WHEN dataintegrity = 192 THEN 1 ELSE 0 END) AS good_count,
    MAX(dataintegrity) AS worst_quality
FROM sqlth_1_data
WHERE dataintegrity = 192  -- Only good quality data
GROUP BY bucket, tagid;
```

**Key components:**

- **`time_bucket(60000, t_stamp)`** - Groups data into 1-minute intervals
- **`COALESCE(intvalue, floatvalue)`** - Handles both integer and float values
- **`WHERE dataintegrity = 192`** - Filters to good quality only (configurable)
- **`GROUP BY bucket, tagid`** - Aggregates per tag per minute

#### Step 2: Add Refresh Policy (1-Minute)

```sql
-- Refresh every 5 minutes for data from last hour
SELECT add_continuous_aggregate_policy('tag_history_1min',
    start_offset => 3600000,
    end_offset => 60000,
    schedule_interval => INTERVAL '5 minutes'
);
```

**Parameters explained:**

- **`start_offset`**: How far back to refresh (1 hour = include last hour of data)
- **`end_offset`**: How close to "now" (1 minute = exclude most recent minute)
- **`schedule_interval`**: How often to run (every 5 minutes)

**Why exclude most recent minute?**
- Data may still be arriving
- Avoids partial aggregates
- Ensures complete minute buckets

#### Step 3: Add Retention Policy (1-Minute)

```sql
-- Keep 1-minute aggregates for 1 year
SELECT add_retention_policy('tag_history_1min', drop_after => BIGINT '31536000000');
```

#### Step 4: Create Hourly Aggregate (Hierarchical)

```sql
-- Create hourly aggregate FROM 1-minute data
CREATE MATERIALIZED VIEW tag_history_1hour
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(3600000, bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    AVG(stddev_value) AS avg_stddev,
    SUM(sample_count) AS total_samples,
    SUM(good_count) AS total_good_samples
FROM tag_history_1min
GROUP BY bucket, tagid;
```

**Note:** Building on 1-minute data (not raw data) creates a hierarchy.

#### Step 5: Add Policies (Hourly)

```sql
-- Refresh hourly for data from last 3 days
SELECT add_continuous_aggregate_policy('tag_history_1hour',
    start_offset => 259200000,
    end_offset => 3600000,
    schedule_interval => INTERVAL '1 hour'
);

-- Keep hourly data for 5 years
SELECT add_retention_policy('tag_history_1hour', drop_after => BIGINT '157680000000');
```

#### Step 6: Create Daily Aggregate

```sql
-- Create daily aggregate FROM hourly data
CREATE MATERIALIZED VIEW tag_history_1day
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(86400000, bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    SUM(total_samples) AS total_samples
FROM tag_history_1hour
GROUP BY bucket, tagid;
```

#### Step 7: Add Policies (Daily)

```sql
-- Refresh daily for data from last week
SELECT add_continuous_aggregate_policy('tag_history_1day',
    start_offset => 604800000,
    end_offset => 86400000,
    schedule_interval => INTERVAL '1 day'
);

-- Keep daily data for 10 years
SELECT add_retention_policy('tag_history_1day', drop_after => BIGINT '315360000000');
```

---

## Optional Aggregates

### Weekly Aggregates

For long-term trending:

```sql
CREATE MATERIALIZED VIEW tag_history_1week
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(604800000, bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    SUM(total_samples) AS total_samples
FROM tag_history_1day
GROUP BY bucket, tagid;

-- Policies
SELECT add_continuous_aggregate_policy('tag_history_1week',
    start_offset => 2419200000,
    end_offset => 604800000,
    schedule_interval => INTERVAL '1 week'
);
```

### Monthly Aggregates

For very long-term data:

```sql
CREATE MATERIALIZED VIEW tag_history_1month
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(2592000000, bucket) AS bucket,
    tagid,
    AVG(avg_value) AS avg_value,
    MAX(max_value) AS max_value,
    MIN(min_value) AS min_value,
    SUM(total_samples) AS total_samples
FROM tag_history_1day
GROUP BY bucket, tagid;

-- Policies
SELECT add_continuous_aggregate_policy('tag_history_1month',
    start_offset => 7776000000,
    end_offset => 2592000000,
    schedule_interval => INTERVAL '1 month'
);
```

---

## Creating Helper Views with Tag Names

### Why Helper Views?

Continuous aggregates use `tagid` for performance. Helper views add `tagpath` for convenience:

```sql
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
```

**Benefits:**
- Query by tag path instead of ID
- Excludes retired tags automatically
- User-friendly for ad-hoc queries

**Create for all resolutions:**

```sql
-- Hourly with names
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

-- Daily with names
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
```

---

## Refresh Policies

### Understanding Refresh Windows

```
Timeline:
│
├─ NOW ──────────────────────────────────────┤
│                                             │
│  ← end_offset (don't refresh most recent)  │
│                                             │
├─ Refresh Window End ───────────────────────┤
│                                             │
│  ← Data refreshed in this window           │
│                                             │
├─ Refresh Window Start ─────────────────────┤
│                                             │
│  ← start_offset (how far back to refresh)  │
│                                             │
└─ Older Data (already refreshed) ───────────┘
```

### Choosing Refresh Parameters

**General guidelines:**

```sql
-- For recent, frequently changing data
start_offset => 3600000   -- Refresh last hour
end_offset => 60000   -- Exclude most recent minute
schedule_interval => INTERVAL '5 minutes'  -- Run every 5 minutes

-- For stable historical data
start_offset => 604800000   -- Refresh last week
end_offset => 86400000      -- Exclude today
schedule_interval => INTERVAL '1 day'  -- Run daily
```

### Manual Refresh

Force immediate refresh:

```sql
-- Refresh specific time range
CALL refresh_continuous_aggregate('tag_history_1min', 
    timestamp '2025-11-01 00:00:00', 
    timestamp '2025-11-02 00:00:00'
);

-- Refresh all pending data
CALL refresh_continuous_aggregate('tag_history_1min', NULL, NULL);
```

### Modifying Refresh Policies

```sql
-- Remove existing policy
SELECT remove_continuous_aggregate_policy('tag_history_1min');

-- Add new policy with different parameters
SELECT add_continuous_aggregate_policy('tag_history_1min',
    start_offset => 7200000,
    end_offset => 300000,
    schedule_interval => INTERVAL '10 minutes'
);
```

---

## Using Aggregates in Ignition

### Method 1: Query Binding

Use aggregates directly in query bindings:

```sql
-- Last 30 days of hourly data
SELECT 
    bucket AS t_stamp,
    avg_value,
    max_value,
    min_value
FROM tag_history_1hour_named
WHERE tagpath = :tagPath
  AND bucket >= CURRENT_TIMESTAMP - INTERVAL '30 days'
ORDER BY bucket DESC
```

**Advantages:**
- 100x+ faster than raw data queries
- Returns manageable row counts
- Perfect for Power Chart and Easy Chart

### Method 2: Database Table Historian

Configure Ignition to query aggregates as a historian source:

**Gateway Configuration:**
1. Tag Historical Providers → Add Provider
2. Type: Database Table
3. Database: `historian` connection
4. Table name: `tag_history_1hour_named`
5. Time column: `bucket`
6. Value column: `avg_value`
7. Tag path column: `tagpath`

**Benefits:**
- Use aggregates in Power Chart natively
- Automatic tag binding
- Leverage Ignition's built-in trending

### Method 3: Named Query

Create named queries for different resolutions:

```python
# Named Query: getHourlyTrend
SELECT 
    bucket,
    tagpath,
    avg_value,
    max_value,
    min_value
FROM tag_history_1hour_named
WHERE tagpath = :tagPath
  AND bucket BETWEEN :startDate AND :endDate
ORDER BY bucket

# Use in script
data = system.db.runNamedQuery('getHourlyTrend', {
    'tagPath': '[default]Production/Temperature',
    'startDate': system.date.addMonths(system.date.now(), -1),
    'endDate': system.date.now()
})
```

### Choosing Resolution Based on Range

**Smart query pattern:**

```python
# Python script for adaptive resolution
def getHistoricalData(tagPath, startDate, endDate):
    duration = system.date.hoursBetween(startDate, endDate)
    
    if duration <= 24:
        # Use raw data for < 1 day
        query = "SELECT * FROM sqlth_1_data_named WHERE..."
    elif duration <= 168:  # 1 week
        # Use 1-minute aggregates
        query = "SELECT * FROM tag_history_1min_named WHERE..."
    elif duration <= 720:  # 1 month
        # Use hourly aggregates
        query = "SELECT * FROM tag_history_1hour_named WHERE..."
    else:
        # Use daily aggregates
        query = "SELECT * FROM tag_history_1day_named WHERE..."
    
    return system.db.runPrepQuery(query, [tagPath, startDate, endDate])
```

---

## Verification

### 1. List All Continuous Aggregates

```sql
-- View all continuous aggregates
SELECT 
    view_name,
    view_definition,
    materialization_hypertable_schema,
    materialization_hypertable_name,
    compression_enabled
FROM timescaledb_information.continuous_aggregates
ORDER BY view_name;
```

**Expected output:**
```
     view_name      | compression_enabled 
--------------------+--------------------
 tag_history_1day   | t
 tag_history_1hour  | t
 tag_history_1min   | t
 tag_history_1month | t
 tag_history_1week  | t
```

### 2. Check Refresh Policies

```sql
-- View refresh policy configuration
SELECT 
    view_name,
    schedule_interval,
    config,
    next_start,
    last_run_status
FROM timescaledb_information.jobs j
JOIN timescaledb_information.continuous_aggregates c 
    ON j.hypertable_name = c.materialization_hypertable_name
WHERE application_name = 'Continuous Aggregate Policy'
ORDER BY view_name;
```

### 3. Verify Data Exists

```sql
-- Check 1-minute aggregate data
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT tagid) as unique_tags,
    MIN(bucket) as earliest_bucket,
    MAX(bucket) as latest_bucket,
    pg_size_pretty(pg_total_relation_size('tag_history_1min')) as view_size
FROM tag_history_1min;
```

**Expected:** Rows should exist if raw data has been collected and refresh policy has run.

### 4. Compare Raw vs Aggregate

```sql
-- Compare query performance
-- Raw data query
EXPLAIN ANALYZE
SELECT tagid, AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
GROUP BY tagid;

-- Aggregate query
EXPLAIN ANALYZE
SELECT tagid, AVG(avg_value)
FROM tag_history_1hour
WHERE bucket >= NOW() - INTERVAL '30 days'
GROUP BY tagid;
```

**Compare execution times:** Aggregate should be 10-100x faster.

### 5. Test Helper Views

```sql
-- Query with tag name
SELECT 
    bucket,
    tagpath,
    avg_value,
    max_value,
    min_value
FROM tag_history_1hour_named
WHERE tagpath LIKE '%Temperature%'
  AND bucket >= NOW() - INTERVAL '7 days'
ORDER BY bucket DESC
LIMIT 100;
```

---

## Monitoring Continuous Aggregates

### Track Refresh Status

```sql
-- Check when aggregates were last refreshed
SELECT 
    ca.view_name,
    js.last_run_started_at,
    js.last_run_status,
    js.last_run_duration,
    js.next_start,
    js.total_runs,
    js.total_failures
FROM timescaledb_information.continuous_aggregates ca
JOIN timescaledb_information.jobs j 
    ON j.hypertable_name = ca.materialization_hypertable_name
JOIN timescaledb_information.job_stats js ON j.job_id = js.job_id
WHERE j.application_name = 'Continuous Aggregate Policy'
ORDER BY ca.view_name;
```

### Monitor Aggregate Size

```sql
-- Track storage usage of aggregates
SELECT 
    view_name,
    pg_size_pretty(pg_total_relation_size(
        materialization_hypertable_schema || '.' || materialization_hypertable_name
    )) as materialized_size,
    pg_size_pretty(pg_total_relation_size(view_name)) as view_size
FROM timescaledb_information.continuous_aggregates
ORDER BY pg_total_relation_size(
    materialization_hypertable_schema || '.' || materialization_hypertable_name
) DESC;
```

### Check Data Completeness

```sql
-- Verify continuous coverage (no gaps)
WITH time_series AS (
    SELECT 
        bucket,
        LAG(bucket) OVER (PARTITION BY tagid ORDER BY bucket) as prev_bucket,
        tagid
    FROM tag_history_1hour
    WHERE tagid = 100  -- Check specific tag
      AND bucket >= NOW() - INTERVAL '7 days'
)
SELECT 
    bucket,
    prev_bucket,
    bucket - prev_bucket as gap_duration
FROM time_series
WHERE bucket - prev_bucket > INTERVAL '1 hour'  -- Detect gaps
ORDER BY bucket DESC;
```

---

## Troubleshooting

### Aggregate Not Refreshing

**1. Check if policy exists:**

```sql
SELECT * FROM timescaledb_information.jobs
WHERE application_name = 'Continuous Aggregate Policy'
  AND view_name = 'tag_history_1min';
```

**2. Check for errors:**

```sql
SELECT 
    job_id,
    last_run_status,
    last_error_message
FROM timescaledb_information.job_stats
WHERE job_id IN (
    SELECT job_id FROM timescaledb_information.jobs
    WHERE application_name = 'Continuous Aggregate Policy'
);
```

**3. Manually trigger refresh:**

```sql
CALL refresh_continuous_aggregate('tag_history_1min', NULL, NULL);
```

### Empty Aggregate Views

**Verify raw data exists:**

```sql
SELECT COUNT(*) FROM sqlth_1_data;
```

**Check refresh window:**

```sql
-- Ensure refresh window covers existing data
SELECT 
    MIN(t_stamp) as min_timestamp,
    MAX(t_stamp) as max_timestamp,
    NOW() as current_time
FROM sqlth_1_data;
```

**Manually refresh historical data:**

```sql
-- Refresh from earliest data to now
CALL refresh_continuous_aggregate('tag_history_1min',
    (SELECT MIN(t_stamp) FROM sqlth_1_data),
    NOW()
);
```

### Poor Query Performance on Aggregates

**1. Check if compression enabled:**

```sql
SELECT 
    view_name,
    compression_enabled
FROM timescaledb_information.continuous_aggregates;
```

**Enable compression if not:**

```sql
ALTER MATERIALIZED VIEW tag_history_1hour SET (
    timescaledb.compress = true
);

SELECT add_compression_policy('tag_history_1hour', BIGINT '604800000');
```

**2. Add indexes:**

```sql
-- Add index on bucket and tagid
CREATE INDEX IF NOT EXISTS idx_tag_history_1hour_bucket_tagid
ON tag_history_1hour (bucket DESC, tagid);
```

### Error: "cannot create continuous aggregate"

**Full error:** `continuous aggregates not supported on hypertables with integer time`

**Solution:** Ensure `unix_now()` function is set:

```sql
-- Verify integer now function
SELECT * FROM timescaledb_information.hypertables
WHERE hypertable_name = 'sqlth_1_data';

-- If missing, add it
CREATE OR REPLACE FUNCTION unix_now() RETURNS BIGINT LANGUAGE SQL STABLE AS $$
    SELECT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
$$;

SELECT set_integer_now_func('sqlth_1_data', 'unix_now');
```

---

## Advanced Configurations

### Custom Aggregation Functions

Include additional statistics:

```sql
CREATE MATERIALIZED VIEW tag_history_1min_advanced
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(60000, t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS avg_value,
    MAX(COALESCE(intvalue, floatvalue)) AS max_value,
    MIN(COALESCE(intvalue, floatvalue)) AS min_value,
    STDDEV(COALESCE(intvalue, floatvalue)) AS stddev_value,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS median_value,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS p95_value,
    COUNT(*) AS sample_count,
    COUNT(DISTINCT COALESCE(intvalue, floatvalue)) AS unique_values
FROM sqlth_1_data
GROUP BY bucket, tagid;
```

### Tag-Specific Aggregates

Create aggregates for specific tag groups:

```sql
-- Aggregate only temperature tags
CREATE MATERIALIZED VIEW temperature_history_1hour
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(3600000, t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS avg_temp,
    MAX(COALESCE(intvalue, floatvalue)) AS max_temp,
    MIN(COALESCE(intvalue, floatvalue)) AS min_temp
FROM sqlth_1_data
WHERE tagid IN (
    SELECT id FROM sqlth_te WHERE tagpath LIKE '%Temperature%'
)
GROUP BY bucket, tagid;
```

### Real-Time Aggregates

For near real-time dashboards:

```sql
-- 10-second aggregates
CREATE MATERIALIZED VIEW tag_history_10sec
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(10000, t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS avg_value,
    COUNT(*) AS sample_count
FROM sqlth_1_data
GROUP BY bucket, tagid;

-- Refresh every 30 seconds
SELECT add_continuous_aggregate_policy('tag_history_10sec',
    start_offset => 300000,
    end_offset => 10000,
    schedule_interval => INTERVAL '30 seconds'
);

-- Keep only 7 days
SELECT add_retention_policy('tag_history_10sec', drop_after => BIGINT '604800000');
```

---

## Best Practices

### Design

✅ **Use hierarchical aggregates** (1min → 1hour → 1day)  
✅ **Match refresh to data update frequency**  
✅ **Include quality metrics** (good_count, worst_quality)  
✅ **Create helper views** for user-friendly queries  
✅ **Filter bad quality data** in base aggregates  
✅ **Plan retention by use case** (raw: 2yr, hourly: 5yr, daily: 10yr)

### Performance

✅ **Enable compression** on aggregate hypertables  
✅ **Use appropriate refresh windows** (don't over-refresh)  
✅ **Index common query patterns** (bucket, tagid)  
✅ **Build on aggregates** (hour from minute, not raw)  
✅ **Monitor refresh job performance**

### Operations

✅ **Test queries** on aggregates before deploying  
✅ **Document resolution strategy** for users  
✅ **Monitor storage growth**  
✅ **Set up alerting** on refresh failures  
✅ **Verify data completeness** regularly

❌ **Don't create too many resolutions** (3-5 is enough)  
❌ **Don't refresh too frequently** (wastes resources)  
❌ **Don't aggregate already-aggregated data** (use hierarchy)  
❌ **Don't forget retention policies** (aggregates grow too)

---

## Performance Comparison

### Storage Savings

**Example: 1000 tags, 1-second scan, 1 year:**

| Resolution | Row Count | Storage (uncompressed) | Storage (compressed) |
|------------|-----------|------------------------|----------------------|
| Raw (1-sec) | 31.5B | 2 TB | 100 GB |
| 1-minute | 525M | 35 GB | 3 GB |
| Hourly | 8.8M | 600 MB | 50 MB |
| Daily | 365K | 25 MB | 2 MB |
| Monthly | 12K | 1 MB | 100 KB |

### Query Performance

**Query: Average value over 1 year for 100 tags**

| Data Source | Rows Scanned | Execution Time | Speedup |
|-------------|--------------|----------------|---------|
| Raw data | 3.15B | 45 seconds | 1x |
| 1-minute agg | 52.5M | 8 seconds | 5.6x |
| Hourly agg | 876K | 0.5 seconds | 90x |
| Daily agg | 36.5K | 0.05 seconds | 900x |

---

## Example Use Cases

### Use Case 1: Operations Dashboard

**Requirement:** Last 24 hours, 1-minute resolution

```sql
SELECT 
    bucket,
    tagpath,
    avg_value,
    max_value,
    min_value
FROM tag_history_1min_named
WHERE tagpath IN ('[default]Production/Temperature', 
                  '[default]Production/Pressure')
  AND bucket >= NOW() - INTERVAL '24 hours'
ORDER BY bucket DESC;
```

### Use Case 2: Monthly Report

**Requirement:** Last month, daily aggregates

```sql
SELECT 
    bucket::date as report_date,
    tagpath,
    avg_value as daily_average,
    max_value as daily_peak,
    min_value as daily_low,
    total_samples as data_points
FROM tag_history_1day_named
WHERE tagpath LIKE '%Production%'
  AND bucket >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
  AND bucket < DATE_TRUNC('month', NOW())
ORDER BY tagpath, report_date;
```

### Use Case 3: Annual Trending

**Requirement:** 5 years, monthly aggregates

```sql
SELECT 
    DATE_TRUNC('month', bucket) as month,
    tagpath,
    AVG(avg_value) as monthly_average
FROM tag_history_1day_named
WHERE tagpath = '[default]Production/Temperature'
  AND bucket >= NOW() - INTERVAL '5 years'
GROUP BY DATE_TRUNC('month', bucket), tagpath
ORDER BY month;
```

### Use Case 4: Quality Report

**Requirement:** Data quality metrics

```sql
SELECT 
    bucket::date as date,
    tagpath,
    total_samples,
    total_good_samples,
    ROUND(100.0 * total_good_samples / NULLIF(total_samples, 0), 2) as quality_percent
FROM tag_history_1day_named
WHERE bucket >= NOW() - INTERVAL '30 days'
  AND tagpath LIKE '%Critical%'
ORDER BY quality_percent ASC
LIMIT 20;  -- Show worst quality tags
```

---

## Next Steps

✅ Continuous aggregates created and configured

**Continue to:**
- [Ignition Integration](../getting-started/03-ignition-setup.md) - Use aggregates in Ignition
- [Query Examples](../examples/01-basic-queries.md) - Learn to query aggregates effectively
- [Performance Tuning](../optimization/01-performance-tuning.md) - Optimize aggregate queries

**Or explore:**
- [Dashboard Design](../examples/03-dashboard-queries.md) - Build dashboards with aggregates
- [Reporting](../examples/04-reporting-queries.md) - Generate reports from aggregates

---

## Reference

### Common Commands

```sql
-- Create continuous aggregate
CREATE MATERIALIZED VIEW view_name
WITH (timescaledb.continuous) AS
SELECT time_bucket('interval', time_column), ...
FROM source_table
GROUP BY time_bucket('interval', time_column);

-- Add refresh policy
SELECT add_continuous_aggregate_policy('view_name',
    start_offset => INTERVAL 'X',
    end_offset => INTERVAL 'Y',
    schedule_interval => INTERVAL 'Z'
);

-- Manual refresh
CALL refresh_continuous_aggregate('view_name', start_time, end_time);

-- Remove policy
SELECT remove_continuous_aggregate_policy('view_name');

-- Drop aggregate
DROP MATERIALIZED VIEW view_name;

-- List all aggregates
SELECT * FROM timescaledb_information.continuous_aggregates;
```

### Time Bucket Examples

```sql
-- Various time bucket sizes
time_bucket('1 second', t_stamp)
time_bucket(10000, t_stamp)
time_bucket(60000, t_stamp)
time_bucket('5 minutes', t_stamp)
time_bucket('15 minutes', t_stamp)
time_bucket(3600000, t_stamp)
time_bucket(86400000, t_stamp)
time_bucket(604800000, t_stamp)
time_bucket(2592000000, t_stamp)
```

### Additional Resources

- [TimescaleDB Continuous Aggregates Documentation](https://docs.timescale.com/use-timescale/latest/continuous-aggregates/)
- [Hierarchical Aggregates Guide](https://docs.timescale.com/use-timescale/latest/continuous-aggregates/hierarchical-continuous-aggregates/)
- [Refresh Policies](https://docs.timescale.com/api/latest/continuous-aggregates/add_continuous_aggregate_policy/)
- [Ignition Database Table Historian](https://docs.inductiveautomation.com/docs/8.1/intro/ignition/ignition-modules/sql-bridge-module/database-table-historian)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
