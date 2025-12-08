# Storage Optimization

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate  
**Estimated Time:** 45-60 minutes  
**Prerequisites:** 
- Hypertables configured
- Compression enabled
- Understanding of retention policies

## Overview

This guide covers strategies to minimize disk usage while maintaining query performance. TimescaleDB's compression can achieve 10-20x storage reduction, but proper configuration and maintenance are essential.

---

## Storage Breakdown

### Understanding Current Usage

```sql
-- Database size
SELECT pg_size_pretty(pg_database_size('historian')) as total_size;

-- Table breakdown
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as indexes_size
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename LIKE 'sqlth%'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Hypertable details
SELECT 
    hypertable_name,
    num_chunks,
    pg_size_pretty(total_bytes) as total_size,
    pg_size_pretty(total_bytes / num_chunks) as avg_chunk_size
FROM timescaledb_information.hypertables;
```

---

## Compression Strategies

### Compression Ratio Analysis

```sql
SELECT 
    hypertable_name,
    COUNT(*) as compressed_chunks,
    pg_size_pretty(SUM(before_compression_total_bytes)) as before_size,
    pg_size_pretty(SUM(after_compression_total_bytes)) as after_size,
    ROUND(
        SUM(before_compression_total_bytes)::numeric / 
        NULLIF(SUM(after_compression_total_bytes), 0),
        2
    ) as compression_ratio,
    pg_size_pretty(
        SUM(before_compression_total_bytes) - SUM(after_compression_total_bytes)
    ) as space_saved
FROM timescaledb_information.compressed_chunk_stats
GROUP BY hypertable_name;
```

### Optimal Compression Settings

**Standard configuration:**
```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);
```

**For better compression on high-cardinality data:**
```sql
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid, dataintegrity'
);
```

### Compression Policy Timing

```sql
-- Aggressive (compress after 1 day)
SELECT add_compression_policy('sqlth_1_data', INTERVAL '1 day');

-- Recommended (compress after 7 days)
SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');

-- Conservative (compress after 30 days)
SELECT add_compression_policy('sqlth_1_data', INTERVAL '30 days');
```

**Trade-offs:**
- **Early compression**: More space savings, but can't update compressed data
- **Late compression**: More flexibility, but higher disk usage

---

## Chunk Size Optimization

### Current Chunk Analysis

```sql
SELECT 
    chunk_name,
    range_start,
    range_end,
    to_timestamp(range_end/1000) - to_timestamp(range_start/1000) as time_span,
    is_compressed,
    pg_size_pretty(total_bytes) as size,
    total_bytes
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 20;
```

### Optimal Chunk Sizing

**Goal:** Chunks between 25MB and 500MB uncompressed

**Formula:**
```
Chunk interval = Target size / (Tags × Sample rate × Row size)

Example:
Target: 100MB
Tags: 1000
Sample rate: 1/second
Row size: ~32 bytes

Chunk interval = 100MB / (1000 × 1 × 32) = 3125 seconds ≈ 1 hour
```

**Adjust chunk size:**
```sql
-- For high-volume systems
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '12 hours');

-- For medium-volume systems
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '1 day');

-- For low-volume systems
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '7 days');
```

---

## Retention Policies

### Multi-Tier Retention

```sql
-- Raw data: Keep 1 year
SELECT add_retention_policy('sqlth_1_data', INTERVAL '1 year');

-- 1-minute aggregates: Keep 3 years
SELECT add_retention_policy('tag_history_1min', INTERVAL '3 years');

-- Hourly aggregates: Keep 7 years  
SELECT add_retention_policy('tag_history_1hour', INTERVAL '7 years');

-- Daily aggregates: Keep 20 years
SELECT add_retention_policy('tag_history_1day', INTERVAL '20 years');
```

**Storage impact:**
```
Without continuous aggregates: 10 years raw data = 10TB
With continuous aggregates:
  - 1 year raw: 1TB
  - 3 years 1-min: 50GB
  - 7 years hourly: 10GB
  - 20 years daily: 2GB
  Total: ~1.06TB (90% savings)
```

---

## Index Optimization

### Index Size Analysis

```sql
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    idx_scan as times_used,
    CASE 
        WHEN idx_scan = 0 THEN 'UNUSED - Consider dropping'
        WHEN idx_scan < 100 THEN 'Rarely used'
        ELSE 'Actively used'
    END as usage
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Drop Unused Indexes

```sql
-- Find and drop unused indexes
DO $$
DECLARE
    index_record RECORD;
BEGIN
    FOR index_record IN 
        SELECT indexrelid::regclass as index_name
        FROM pg_stat_user_indexes
        WHERE schemaname = 'public'
          AND idx_scan = 0
          AND indexrelid::text NOT LIKE '%_pkey'
    LOOP
        EXECUTE 'DROP INDEX ' || index_record.index_name;
        RAISE NOTICE 'Dropped unused index: %', index_record.index_name;
    END LOOP;
END $$;
```

---

## VACUUM and Space Reclamation

### Identify Bloat

```sql
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    n_dead_tup as dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### Reclaim Space

```sql
-- Regular VACUUM
VACUUM sqlth_1_data;

-- VACUUM FULL (locks table, reclaims maximum space)
VACUUM FULL sqlth_1_data;

-- Specific attention to metadata tables
VACUUM FULL sqlth_te;
VACUUM FULL sqlth_partitions;
```

---

## Data Archival Strategies

### Export Old Data

```sql
-- Export data before deletion
\COPY (
    SELECT * FROM sqlth_1_data 
    WHERE t_stamp < (EXTRACT(EPOCH FROM NOW() - INTERVAL '5 years') * 1000)
) TO '/backup/archive_5years_old.csv' WITH CSV HEADER;
```

### Compressed Backups

```bash
# Backup and compress
pg_dump -U postgres -d historian -t sqlth_1_data \
  --data-only \
  --where="t_stamp < extract(epoch from now() - interval '5 years') * 1000" \
  | gzip > historian_archive_$(date +%Y%m%d).sql.gz
```

---

## Storage Monitoring

### Set Up Alerts

```sql
-- Create monitoring function
CREATE OR REPLACE FUNCTION check_disk_usage()
RETURNS TABLE (
    database_name text,
    size_gb numeric,
    alert_level text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'historian'::text,
        ROUND(pg_database_size('historian') / 1024.0^3, 2),
        CASE 
            WHEN pg_database_size('historian') > 1024^3 * 500 THEN 'CRITICAL'
            WHEN pg_database_size('historian') > 1024^3 * 400 THEN 'WARNING'
            ELSE 'OK'
        END;
END;
$$ LANGUAGE plpgsql;

-- Check usage
SELECT * FROM check_disk_usage();
```

### Track Growth Rate

```sql
-- Store daily snapshots
CREATE TABLE IF NOT EXISTS storage_metrics (
    measurement_date DATE DEFAULT CURRENT_DATE,
    database_size BIGINT,
    table_size BIGINT,
    compressed_chunks INT,
    uncompressed_chunks INT
);

-- Daily snapshot
INSERT INTO storage_metrics (database_size, table_size, compressed_chunks, uncompressed_chunks)
SELECT 
    pg_database_size('historian'),
    pg_total_relation_size('sqlth_1_data'),
    COUNT(*) FILTER (WHERE is_compressed),
    COUNT(*) FILTER (WHERE NOT is_compressed)
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data';

-- Analyze growth
SELECT 
    measurement_date,
    pg_size_pretty(database_size) as size,
    pg_size_pretty(database_size - LAG(database_size) OVER (ORDER BY measurement_date)) as daily_growth
FROM storage_metrics
ORDER BY measurement_date DESC
LIMIT 30;
```

---

## Best Practices

✅ **Enable compression** after 7 days (balances flexibility and savings)  
✅ **Use multi-tier retention** (raw + aggregates)  
✅ **Right-size chunks** (25-500MB uncompressed)  
✅ **Regular VACUUM** (weekly for metadata tables)  
✅ **Monitor growth** (track daily size)  
✅ **Archive before delete** (export old data)  
✅ **Drop unused indexes** (monthly review)  
✅ **Use BRIN indexes** for timestamp columns  

❌ **Don't compress actively modified data** (can't update compressed chunks)  
❌ **Don't make chunks too small** (overhead increases)  
❌ **Don't skip retention policies** (disk fills up)  
❌ **Don't ignore bloat** (wastes space)  

---

## Next Steps

- [Scaling Strategies](04-scaling.md)
- [Performance Tuning](01-performance-tuning.md)
- [Compression Configuration](../configuration/02-compression.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
