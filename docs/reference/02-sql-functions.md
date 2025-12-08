# SQL Functions Reference

**Last Updated:** December 8, 2025  
**Difficulty:** Reference

## Overview

Comprehensive reference for SQL functions used with TimescaleDB and Ignition historian queries.

---

## TimescaleDB Time-Series Functions

### time_bucket()

Group time-series data into buckets.

**Syntax:**
```sql
time_bucket(bucket_width INTERVAL, timestamp TIMESTAMP)
time_bucket(bucket_width BIGINT, timestamp BIGINT)
```

**Examples:**
```sql
-- Hourly buckets (milliseconds)
SELECT time_bucket(3600000, t_stamp) as hour, AVG(floatvalue)
FROM sqlth_1_data
GROUP BY hour;

-- Daily buckets
SELECT time_bucket(86400000, t_stamp) as day, AVG(floatvalue)
FROM sqlth_1_data
GROUP BY day;

-- 15-minute buckets
SELECT time_bucket(900000, t_stamp) as bucket, COUNT(*)
FROM sqlth_1_data
GROUP BY bucket;
```

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
SELECT 
    tagid,
    first(floatvalue, t_stamp) as first_value,
    last(floatvalue, t_stamp) as last_value
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY tagid;
```

---

## Compression Functions

### compress_chunk()

Manually compress a chunk.

```sql
-- Compress specific chunk
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Compress all eligible chunks
SELECT compress_chunk(chunk) 
FROM show_chunks('sqlth_1_data', older_than => INTERVAL '7 days') chunk;
```

### decompress_chunk()

Decompress for updates.

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

-- Chunks in time range
SELECT show_chunks('sqlth_1_data',
    older_than => NOW() - INTERVAL '30 days',
    newer_than => NOW() - INTERVAL '60 days');
```

### drop_chunks()

Delete old chunks.

```sql
-- Drop chunks older than 10 years
SELECT drop_chunks('sqlth_1_data', older_than => INTERVAL '10 years');

-- Preview what would be dropped
SELECT * FROM show_chunks('sqlth_1_data', older_than => INTERVAL '10 years');
```

---

## Aggregate Functions

### Standard SQL Aggregates

```sql
-- Statistical aggregates
SELECT 
    AVG(floatvalue) as average,
    STDDEV(floatvalue) as std_deviation,
    VARIANCE(floatvalue) as variance,
    MIN(floatvalue) as minimum,
    MAX(floatvalue) as maximum,
    SUM(floatvalue) as total,
    COUNT(*) as sample_count
FROM sqlth_1_data;
```

### PERCENTILE_CONT()

Calculate percentiles.

```sql
SELECT 
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY floatvalue) as median,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY floatvalue) as p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY floatvalue) as p99
FROM sqlth_1_data;
```

---

## Window Functions

### ROW_NUMBER()

```sql
SELECT 
    t_stamp,
    floatvalue,
    ROW_NUMBER() OVER (PARTITION BY tagid ORDER BY t_stamp) as row_num
FROM sqlth_1_data;
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
WHERE tagid = 100;
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
    EXTRACT(DOW FROM to_timestamp(t_stamp/1000)) as day_of_week,
    EXTRACT(HOUR FROM to_timestamp(t_stamp/1000)) as hour
FROM sqlth_1_data;
```

### DATE_TRUNC()

```sql
SELECT 
    DATE_TRUNC('day', to_timestamp(t_stamp/1000)) as day,
    COUNT(*)
FROM sqlth_1_data
GROUP BY day;
```

---

## String Functions

### Pattern Matching

```sql
-- Find tags by pattern
SELECT tagpath FROM sqlth_te 
WHERE tagpath LIKE '[default]Production/%';

-- Regular expression
SELECT tagpath FROM sqlth_te
WHERE tagpath ~ '\[default\]Production/Line[0-9]+/Temperature';
```

---

## Mathematical Functions

```sql
SELECT 
    ROUND(floatvalue, 2) as rounded,
    CEIL(floatvalue) as ceiling,
    FLOOR(floatvalue) as floor,
    ABS(floatvalue) as absolute,
    POWER(floatvalue, 2) as squared,
    SQRT(floatvalue) as square_root
FROM sqlth_1_data;
```

---

## Additional Resources

- [TimescaleDB Functions](https://docs.timescale.com/api/latest/)
- [PostgreSQL Functions](https://www.postgresql.org/docs/current/functions.html)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
