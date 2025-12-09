# SQL Functions Reference

**Last Updated:** December 8, 2025  
**Difficulty:** Reference

## Overview

Comprehensive reference for SQL functions used with TimescaleDB and Ignition historian queries.

**Important:** Ignition's historian uses BIGINT for `t_stamp` (milliseconds since Unix epoch). All time-based queries must use millisecond values or convert INTERVAL to milliseconds.

---

## TimescaleDB Time-Series Functions

### time_bucket()

Group time-series data into buckets.

**Syntax:**
```sql
time_bucket(bucket_width BIGINT, timestamp BIGINT)
```

**Examples:**
```sql
-- Hourly buckets (3600000 milliseconds = 1 hour)
SELECT time_bucket(3600000, t_stamp) as hour, AVG(floatvalue)
FROM sqlth_1_data
GROUP BY hour;

-- Daily buckets (86400000 milliseconds = 1 day)
SELECT time_bucket(86400000, t_stamp) as day, AVG(floatvalue)
FROM sqlth_1_data
GROUP BY day;

-- 15-minute buckets (900000 milliseconds = 15 minutes)
SELECT time_bucket(900000, t_stamp) as bucket, COUNT(*)
FROM sqlth_1_data
GROUP BY bucket;
```

**Common Time Bucket Intervals (milliseconds):**
- 1 minute: `60000`
- 5 minutes: `300000`
- 15 minutes: `900000`
- 1 hour: `3600000`
- 1 day: `86400000`
- 1 week: `604800000`

---

### time_bucket_gapfill()

Fill missing time buckets with NULL or interpolated values.

```sql
SELECT 
    time_bucket_gapfill(3600000, t_stamp) as hour,
    tagid,
    AVG(floatvalue) as avg_value,
    interpolate(AVG(floatvalue)) as interpolated_value
FROM sqlth_1_data
WHERE t_stamp >= 1234567890000
  AND t_stamp < 1234654290000
GROUP BY hour, tagid;
```

---

### first() and last()

Get first/last values in aggregation.

```sql
-- Get first and last values for each tag in the last 24 hours
SELECT 
    tagid,
    first(floatvalue, t_stamp) as first_value,
    last(floatvalue, t_stamp) as last_value
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)::BIGINT
GROUP BY tagid;
```

---

## Compression Functions

### compress_chunk()

Manually compress a chunk.

```sql
-- Compress specific chunk
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Compress all chunks older than 7 days
SELECT compress_chunk(chunk) 
FROM show_chunks('sqlth_1_data', 
    older_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)::BIGINT) chunk;

-- Compress all chunks older than specific date
SELECT compress_chunk(chunk)
FROM show_chunks('sqlth_1_data', older_than => 1704067200000) chunk; -- Jan 1, 2024
```

### decompress_chunk()

Decompress a chunk for updates.

```sql
SELECT decompress_chunk('_timescaledb_internal._hyper_1_1_chunk');
```

---

## Chunk Management Functions

### show_chunks()

List chunks for a hypertable.

```sql
-- All chunks
SELECT show_chunks('sqlth_1_data');

-- Chunks older than 30 days
SELECT show_chunks('sqlth_1_data',
    older_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)::BIGINT);

-- Chunks in time range (between 30 and 60 days old)
SELECT show_chunks('sqlth_1_data',
    older_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)::BIGINT,
    newer_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '60 days') * 1000)::BIGINT);

-- Chunks older than specific date (milliseconds)
SELECT show_chunks('sqlth_1_data', older_than => 1704067200000); -- Jan 1, 2024
```

### drop_chunks()

Delete old chunks. **Use with caution - this permanently deletes data!**

```sql
-- Drop chunks older than 10 years
SELECT drop_chunks('sqlth_1_data', 
    older_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '10 years') * 1000)::BIGINT);

-- Preview what would be dropped (always check first!)
SELECT * FROM show_chunks('sqlth_1_data', 
    older_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '10 years') * 1000)::BIGINT);

-- Drop chunks before specific date
SELECT drop_chunks('sqlth_1_data', older_than => 1577836800000); -- Jan 1, 2020
```

---

## Retention and Compression Policies

### add_compression_policy()

Automatically compress chunks after a specified age.

```sql
-- Compress chunks older than 7 days
SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');

-- Compress chunks older than 1 day
SELECT add_compression_policy('sqlth_1_data', INTERVAL '1 day');
```

### add_retention_policy()

Automatically drop chunks after a specified age.

```sql
-- Drop chunks older than 10 years
SELECT add_retention_policy('sqlth_1_data', INTERVAL '10 years');

-- Drop chunks older than 1 year
SELECT add_retention_policy('sqlth_1_data', INTERVAL '1 year');
```

**Note:** Policy functions accept INTERVAL directly because they operate on schedules, not direct timestamp comparisons.

---

## Aggregate Functions

### Standard SQL Aggregates

```sql
-- Statistical aggregates
SELECT 
    tagid,
    AVG(floatvalue) as average,
    STDDEV(floatvalue) as std_deviation,
    VARIANCE(floatvalue) as variance,
    MIN(floatvalue) as minimum,
    MAX(floatvalue) as maximum,
    SUM(floatvalue) as total,
    COUNT(*) as sample_count
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)::BIGINT
GROUP BY tagid;
```

### PERCENTILE_CONT()

Calculate percentiles.

```sql
SELECT 
    tagid,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY floatvalue) as median,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY floatvalue) as p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY floatvalue) as p99
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)::BIGINT
GROUP BY tagid;
```

---

## Window Functions

### ROW_NUMBER()

```sql
SELECT 
    t_stamp,
    floatvalue,
    ROW_NUMBER() OVER (PARTITION BY tagid ORDER BY t_stamp) as row_num
FROM sqlth_1_data
WHERE tagid = 100;
```

### LAG() and LEAD()

```sql
SELECT 
    t_stamp,
    floatvalue,
    LAG(floatvalue) OVER (ORDER BY t_stamp) as prev_value,
    LEAD(floatvalue) OVER (ORDER BY t_stamp) as next_value,
    floatvalue - LAG(floatvalue) OVER (ORDER BY t_stamp) as delta
FROM sqlth_1_data
WHERE tagid = 100
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)::BIGINT
ORDER BY t_stamp;
```

---

## Date/Time Functions

### EXTRACT()

```sql
-- Convert milliseconds to timestamp components
SELECT 
    t_stamp,
    EXTRACT(YEAR FROM to_timestamp(t_stamp/1000)) as year,
    EXTRACT(MONTH FROM to_timestamp(t_stamp/1000)) as month,
    EXTRACT(DAY FROM to_timestamp(t_stamp/1000)) as day,
    EXTRACT(DOW FROM to_timestamp(t_stamp/1000)) as day_of_week,
    EXTRACT(HOUR FROM to_timestamp(t_stamp/1000)) as hour
FROM sqlth_1_data
LIMIT 100;
```

### DATE_TRUNC()

```sql
-- Group by day
SELECT 
    DATE_TRUNC('day', to_timestamp(t_stamp/1000)) as day,
    COUNT(*) as record_count,
    AVG(floatvalue) as avg_value
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)::BIGINT
GROUP BY day
ORDER BY day;
```

---

## String Functions

### Pattern Matching

```sql
-- Find tags by pattern
SELECT tagpath, tagid 
FROM sqlth_te 
WHERE tagpath LIKE '[default]Production/%'
  AND retired IS NULL;

-- Regular expression
SELECT tagpath, tagid
FROM sqlth_te
WHERE tagpath ~ '\[default\]Production/Line[0-9]+/Temperature'
  AND retired IS NULL;
```

---

## Mathematical Functions

```sql
SELECT 
    tagid,
    t_stamp,
    floatvalue,
    ROUND(floatvalue, 2) as rounded,
    CEIL(floatvalue) as ceiling,
    FLOOR(floatvalue) as floor,
    ABS(floatvalue) as absolute,
    POWER(floatvalue, 2) as squared,
    SQRT(ABS(floatvalue)) as square_root
FROM sqlth_1_data
WHERE tagid = 100
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)::BIGINT
LIMIT 100;
```

---

## Working with Millisecond Timestamps

### Converting INTERVAL to Milliseconds

When using `show_chunks()`, `drop_chunks()`, or time comparisons, convert INTERVAL to milliseconds:

```sql
-- Template
(EXTRACT(EPOCH FROM NOW() - INTERVAL 'X units') * 1000)::BIGINT

-- Examples
(EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)::BIGINT
(EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)::BIGINT
(EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)::BIGINT
(EXTRACT(EPOCH FROM NOW() - INTERVAL '1 year') * 1000)::BIGINT
(EXTRACT(EPOCH FROM NOW() - INTERVAL '10 years') * 1000)::BIGINT
```

### Common Millisecond Values

```sql
-- 1 second = 1,000
-- 1 minute = 60,000
-- 1 hour = 3,600,000
-- 1 day = 86,400,000
-- 1 week = 604,800,000
-- 30 days = 2,592,000,000
-- 1 year (365 days) = 31,536,000,000
-- 10 years = 315,360,000,000
```

### Converting Dates to Milliseconds

```sql
-- Convert specific date to milliseconds
SELECT EXTRACT(EPOCH FROM '2024-01-01'::timestamp) * 1000; -- Result: 1704067200000

-- Use in queries
SELECT * FROM sqlth_1_data
WHERE t_stamp >= 1704067200000; -- All data since Jan 1, 2024
```

---

## Additional Resources

- [TimescaleDB Functions](https://www.tigerdata.com/docs/api/latest/)
- [PostgreSQL Functions](https://www.postgresql.org/docs/current/functions.html)
- [TimescaleDB Compression](https://www.tigerdata.com/docs/use-timescale/latest/compression/)
- [TimescaleDB Data Retention](https://www.tigerdata.com/docs/use-timescale/latest/data-retention/)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.2
