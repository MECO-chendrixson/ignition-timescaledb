# Compression Configuration

**Last Updated:** December 8, 2025  
**Difficulty:** Beginner to Intermediate  
**Estimated Time:** 15-20 minutes  
**Prerequisites:** 
- Hypertable created and configured
- Data being collected in historian
- Understanding of retention requirements

## Overview

TimescaleDB's native compression can reduce storage by **10-20x** while maintaining query performance. This guide covers enabling, configuring, and monitoring compression for Ignition historian data.

---

## Why Compression Matters

### Storage Savings

**Without Compression:**
```
1 year of data: 1000 tags × 1 second scan = 500 GB
10 years of data: 5 TB
```

**With Compression:**
```
1 year of data: 25-50 GB (10-20x reduction)
10 years of data: 250-500 GB
```

### Key Benefits

| Benefit | Impact |
|---------|--------|
| **10-20x storage reduction** | Massive cost savings |
| **Maintained query performance** | Queries remain fast |
| **Automatic compression** | Set it and forget it |
| **Selective decompression** | Only decompress needed chunks |
| **No application changes** | Transparent to Ignition |

### How It Works

```
Uncompressed Chunk (Row-based):
┌─────────┬─────────┬──────────┬─────────┐
│ tagid   │ t_stamp │ value    │ quality │
├─────────┼─────────┼──────────┼─────────┤
│ 1       │ 100     │ 75.2     │ 192     │
│ 1       │ 200     │ 75.3     │ 192     │
│ 1       │ 300     │ 75.2     │ 192     │
│ 2       │ 100     │ 50.1     │ 192     │
└─────────┴─────────┴──────────┴─────────┘
Size: 1 GB

Compressed Chunk (Columnar):
┌────────────────────────────────┐
│ tagid: [1,1,1,2] → compressed  │
│ t_stamp: [100,200,300,100] →   │
│ value: [75.2,75.3,75.2,50.1]   │
│ quality: [192,192,192,192] →   │
└────────────────────────────────┘
Size: 50-100 MB (10-20x smaller)
```

---

## Understanding Compression Settings

### Order By (Critical)

Determines how data is sorted for compression:

```sql
timescaledb.compress_orderby = 't_stamp DESC'
```

**Why DESC (descending)?**
- Most queries request recent data first
- Faster decompression for recent queries
- Power Chart and Easy Chart query patterns

**Alternative:** `t_stamp ASC` for historical analysis workflows.

### Segment By (Critical)

Groups data for independent compression:

```sql
timescaledb.compress_segmentby = 'tagid'
```

**Why segment by tagid?**
- Each tag compressed separately
- Query one tag = decompress only that tag's data
- Ignition typically queries specific tags
- Better compression ratios for similar data

**Alternative:** Add multiple columns: `'tagid, dataintegrity'` for quality-based segmentation.

---

## Enabling Compression

### Method 1: Automated (Recommended)

The provided script enables compression automatically:

```bash
psql -U postgres -d historian -f sql/schema/02-configure-hypertables.sql
```

**Skip to [Verification](#verification) if you used the script.**

---

### Method 2: Manual Configuration

#### Step 1: Enable Compression on Hypertable

```sql
-- Connect to historian database
\c historian

-- Enable compression with optimal settings
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);
```

**What this does:**
- ✅ Enables compression on the hypertable
- ✅ Sets compression order (most recent first)
- ✅ Segments by tag for efficient queries

#### Step 2: Verify Compression Settings

```sql
-- Check compression configuration
SELECT 
    h.hypertable_name,
    c.attname as segment_by_column,
    c.orderby_column_name,
    c.orderby_asc
FROM timescaledb_information.hypertables h
LEFT JOIN timescaledb_information.compression_settings c 
    ON h.hypertable_name = c.hypertable_name
WHERE h.hypertable_name = 'sqlth_1_data';
```

---

## Compression Policies

### What is a Compression Policy?

An automated background job that compresses chunks older than a specified age.

### Adding a Compression Policy

```sql
-- Compress chunks older than 7 days (604800000 milliseconds = 7 days)
-- For BIGINT time columns, must use BIGINT type casting
SELECT add_compression_policy('sqlth_1_data', BIGINT '604800000');
```

**Why 7 days?**
- Recent data frequently modified (tag updates, corrections)
- After 7 days, data typically stable
- Balances compression benefit vs. operational flexibility

**Alternative schedules:**

```sql
-- Conservative: Compress after 14 days (1209600000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '1209600000');

-- Aggressive: Compress after 3 days (259200000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '259200000');

-- Immediate: Compress after 1 day (86400000 ms - only if data never changes)
SELECT add_compression_policy('sqlth_1_data', BIGINT '86400000');
```

### Policy Scheduling

Compression policies run automatically in the background:

```sql
-- Check policy schedule
SELECT 
    application_name,
    schedule_interval,
    config,
    next_start
FROM timescaledb_information.jobs
WHERE application_name = 'Compression Policy'
  AND hypertable_name = 'sqlth_1_data';
```

**Default behavior:**
- Runs every ~30 minutes
- Processes chunks eligible for compression
- Non-blocking (database remains responsive)
- Automatic retry on failure

---

## Manual Compression

### Compress Specific Chunks

```sql
-- List uncompressed chunks
SELECT 
    chunk_schema || '.' || chunk_name as chunk,
    range_start,
    range_end,
    to_timestamp(range_start/1000) as start_date,
    pg_size_pretty(total_bytes) as size,
    is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
  AND NOT is_compressed
ORDER BY range_start DESC;

-- Compress a specific chunk
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Compress all eligible chunks older than 7 days
-- For BIGINT time columns, use milliseconds: 604800000 ms = 7 days
SELECT compress_chunk(i, if_not_compressed => true)
FROM show_chunks('sqlth_1_data', older_than => 604800000) i;
```

### Decompress Chunks

If you need to modify compressed data:

```sql
-- Decompress a specific chunk
SELECT decompress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Query to find chunk name for a specific date
SELECT show_chunks('sqlth_1_data', 
    older_than => timestamp '2025-11-01',
    newer_than => timestamp '2025-10-01'
);
```

**⚠️ Warning:** Decompression:
- Takes time proportional to chunk size
- Increases storage temporarily
- Locks chunk during decompression

---

## Compression Strategies by Use Case

### Strategy 1: Standard Historian (Recommended)

**Characteristics:**
- General tag history
- Occasional data corrections
- Standard retention (1-10 years)

**Configuration:**
```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);

-- Compress after 7 days (604800000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '604800000');
```

### Strategy 2: Read-Only Archive

**Characteristics:**
- Historical data never modified
- Long-term retention (10+ years)
- Compliance/regulatory storage

**Configuration:**
```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);

-- Compress aggressively after 1 day (86400000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '86400000');
```

### Strategy 3: High-Frequency Data

**Characteristics:**
- Many tags (>5000)
- High sample rates (sub-second)
- Need to segment by additional columns

**Configuration:**
```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid, dataintegrity'
);

-- Compress after 3 days (259200000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '259200000');
```

### Strategy 4: Analytical Workload

**Characteristics:**
- Primarily querying old data
- Time-series analytics
- Machine learning training

**Configuration:**
```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp ASC',  -- Ascending for historical queries
    timescaledb.compress_segmentby = 'tagid'
);

-- Compress after 14 days (1209600000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '1209600000');
```

---

## Verification

### 1. Check Compression Settings

```sql
-- View compression configuration
SELECT 
    hypertable_name,
    attname as segmented_by,
    orderby_column_name as ordered_by,
    orderby_asc
FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'sqlth_1_data';
```

**Expected output:**
```
 hypertable_name | segmented_by | ordered_by | orderby_asc 
-----------------+--------------+------------+-------------
 sqlth_1_data    | tagid        | t_stamp    | f
```

### 2. Check Compression Status

```sql
-- Summary of compressed vs uncompressed chunks
SELECT 
    hypertable_name,
    num_chunks,
    COUNT(CASE WHEN is_compressed THEN 1 END) as compressed_chunks,
    COUNT(CASE WHEN NOT is_compressed THEN 1 END) as uncompressed_chunks
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
GROUP BY hypertable_name, num_chunks;
```

### 3. Check Compression Ratio

```sql
-- Detailed compression statistics
SELECT 
    pg_size_pretty(SUM(before_compression_total_bytes)) as uncompressed_size,
    pg_size_pretty(SUM(after_compression_total_bytes)) as compressed_size,
    ROUND(
        (SUM(before_compression_total_bytes)::numeric / 
         NULLIF(SUM(after_compression_total_bytes), 0))::numeric, 
        2
    ) as compression_ratio
FROM timescaledb_information.compressed_chunk_stats
WHERE hypertable_name = 'sqlth_1_data';
```

**Expected output:**
```
 uncompressed_size | compressed_size | compression_ratio 
-------------------+-----------------+-------------------
 10 GB             | 500 MB          | 20.00
```

### 4. Verify Compression Policy

```sql
-- Check that policy is scheduled
SELECT 
    job_id,
    application_name,
    schedule_interval,
    config,
    next_start,
    last_run_status
FROM timescaledb_information.jobs
WHERE application_name LIKE '%Compression%'
  AND hypertable_name = 'sqlth_1_data';
```

### 5. Test Query Performance

```sql
-- Time a query on compressed data
EXPLAIN ANALYZE
SELECT 
    tagid,
    COUNT(*) as samples,
    AVG(COALESCE(intvalue, floatvalue)) as avg_value
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
  AND t_stamp < (EXTRACT(EPOCH FROM NOW() - INTERVAL '8 days') * 1000)
GROUP BY tagid;
```

**Look for:**
- "Decompress Chunk" nodes in plan (shows compression working)
- Fast execution despite compressed data
- Selective decompression (only needed chunks)

---

## Monitoring Compression

### Track Compression Progress

```sql
-- Monitor compression over time
SELECT 
    chunk_name,
    CASE 
        WHEN is_compressed THEN 'Compressed'
        ELSE 'Uncompressed'
    END as status,
    range_start,
    to_timestamp(range_start/1000) as chunk_start_date,
    pg_size_pretty(before_compression_total_bytes) as original_size,
    pg_size_pretty(after_compression_total_bytes) as compressed_size,
    ROUND(
        before_compression_total_bytes::numeric / 
        NULLIF(after_compression_total_bytes, 0),
        2
    ) as ratio
FROM timescaledb_information.compressed_chunk_stats
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 20;
```

### Daily Compression Report

```sql
-- Daily summary of compression savings
WITH chunk_stats AS (
    SELECT 
        DATE(to_timestamp(range_start/1000)) as chunk_date,
        SUM(before_compression_total_bytes) as original,
        SUM(after_compression_total_bytes) as compressed,
        COUNT(*) as chunks
    FROM timescaledb_information.compressed_chunk_stats
    WHERE hypertable_name = 'sqlth_1_data'
      AND is_compressed = true
    GROUP BY DATE(to_timestamp(range_start/1000))
)
SELECT 
    chunk_date,
    chunks,
    pg_size_pretty(original) as original_size,
    pg_size_pretty(compressed) as compressed_size,
    pg_size_pretty(original - compressed) as space_saved,
    ROUND((original::numeric / NULLIF(compressed, 0))::numeric, 2) as ratio
FROM chunk_stats
ORDER BY chunk_date DESC
LIMIT 30;
```

### Check Compression Job Logs

```sql
-- View recent compression job executions
SELECT 
    job_id,
    last_run_started_at,
    last_run_status,
    last_run_duration,
    total_runs,
    total_successes,
    total_failures
FROM timescaledb_information.job_stats
WHERE job_id IN (
    SELECT job_id 
    FROM timescaledb_information.jobs 
    WHERE application_name LIKE '%Compression%'
);
```

---

## Troubleshooting

### Compression Not Happening

**1. Check if policy exists:**

```sql
SELECT * FROM timescaledb_information.jobs
WHERE application_name LIKE '%Compression%'
  AND hypertable_name = 'sqlth_1_data';
```

**If no results:** Add compression policy:
```sql
-- Add compression policy (7 days = 604800000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '604800000');
```

**2. Check if chunks are old enough:**

```sql
-- List chunks that should be compressed
SELECT 
    chunk_name,
    to_timestamp(range_end/1000) as chunk_end,
    NOW() - to_timestamp(range_end/1000) as age,
    is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
  AND NOT is_compressed
  AND range_end < (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
ORDER BY range_end DESC;
```

**3. Manually trigger compression:**

```sql
-- Force compression of eligible chunks
CALL run_job((
    SELECT job_id FROM timescaledb_information.jobs 
    WHERE application_name = 'Compression Policy' 
      AND hypertable_name = 'sqlth_1_data'
));
```

### Poor Compression Ratio (<5x)

**Possible causes:**

1. **Data not repetitive:** Random data compresses poorly
2. **Wrong segment_by:** Not segmenting appropriately
3. **Wrong order_by:** Data not sorted optimally

**Diagnosis:**

```sql
-- Check data variability
SELECT 
    tagid,
    COUNT(DISTINCT COALESCE(intvalue, floatvalue)) as unique_values,
    COUNT(*) as total_samples,
    ROUND(
        COUNT(DISTINCT COALESCE(intvalue, floatvalue))::numeric / 
        COUNT(*)::numeric * 100,
        2
    ) as uniqueness_percent
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY tagid
ORDER BY uniqueness_percent DESC
LIMIT 20;
```

**If uniqueness > 80%:** Data is highly variable (expected for some tags)

### Error: "cannot compress chunk"

**Full error:** `cannot compress a chunk with update/delete trigger`

**Cause:** Triggers prevent compression

**Solution:**
```sql
-- List triggers
SELECT * FROM pg_trigger WHERE tgrelid = 'sqlth_1_data'::regclass;

-- Disable trigger temporarily
ALTER TABLE sqlth_1_data DISABLE TRIGGER trigger_name;

-- Compress chunk
SELECT compress_chunk('chunk_name');

-- Re-enable trigger
ALTER TABLE sqlth_1_data ENABLE TRIGGER trigger_name;
```

### Compression Causing Performance Issues

**Symptoms:** Queries slower on compressed data

**Diagnosis:**

```sql
-- Compare query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM sqlth_1_data 
WHERE tagid = 100 
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000);
```

**Solutions:**

1. **Adjust segment_by to match query patterns:**
```sql
-- If querying by multiple tags together
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress_segmentby = 'tagid, dataintegrity'
);
```

2. **Change order_by to match access pattern:**
```sql
-- If querying oldest data first
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress_orderby = 't_stamp ASC'
);
```

---

## Advanced Configurations

### Multiple Segment Columns

For complex query patterns:

```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid, dataintegrity'
);
```

**Trade-offs:**
- ✅ Better query performance for specific quality levels
- ❌ Slightly larger compressed size
- ❌ More segments to decompress

### Custom Compression Algorithms

TimescaleDB uses gorilla compression by default (optimized for time-series):

```sql
-- View compression algorithms
SELECT 
    attname,
    compression_algorithm_id
FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'sqlth_1_data';
```

**Default algorithms:**
- Timestamps: Delta-of-delta + Gorilla
- Floats: Gorilla compression
- Integers: Simple8b
- Strings: Dictionary + LZ

---

## Best Practices

✅ **Compress after data stabilizes** (7-14 days)  
✅ **Segment by most common query filter** (usually tagid)  
✅ **Order by query access pattern** (DESC for recent data)  
✅ **Monitor compression ratios** (target 10x+)  
✅ **Use compression policies** (don't manually compress)  
✅ **Test query performance** on compressed data  
✅ **Allow headroom** for uncompressed recent data  

❌ **Don't compress actively modified data**  
❌ **Don't compress with aggressive retention** (decompress overhead)  
❌ **Don't use too many segment_by columns** (>3)  

---

## Next Steps

✅ Compression enabled and configured

**Continue to:**
- [Retention Policies](03-retention-policies.md) - Automatic data lifecycle management
- [Continuous Aggregates](04-continuous-aggregates.md) - Multi-resolution downsampling

**Or explore:**
- [Storage Optimization](../optimization/03-storage-optimization.md) - Advanced storage techniques
- [Performance Tuning](../optimization/01-performance-tuning.md) - Optimize compressed queries

---

## Reference

### Useful Queries

```sql
-- Total compression savings
SELECT 
    hypertable_name,
    pg_size_pretty(SUM(before_compression_total_bytes)) as before,
    pg_size_pretty(SUM(after_compression_total_bytes)) as after,
    ROUND(AVG(before_compression_total_bytes::numeric / 
              NULLIF(after_compression_total_bytes, 0)), 2) as avg_ratio
FROM timescaledb_information.compressed_chunk_stats
GROUP BY hypertable_name;

-- Compression policy details
SELECT * FROM timescaledb_information.jobs
WHERE application_name LIKE '%Compression%';

-- Modify compression policy
SELECT remove_compression_policy('sqlth_1_data');
-- Add new policy with 14 days (1209600000 ms)
SELECT add_compression_policy('sqlth_1_data', BIGINT '1209600000');
```

### Additional Resources

- [TimescaleDB Compression Documentation](https://www.tigerdata.com/docs/use-timescale/latest/compression/)
- [Compression Best Practices](https://www.tigerdata.com/docs/use-timescale/latest/compression/about-compression/)
- [Performance Tuning Guide](../optimization/01-performance-tuning.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
