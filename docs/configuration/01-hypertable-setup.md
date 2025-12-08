# Hypertable Setup and Configuration

**Last Updated:** December 8, 2025  
**Difficulty:** Beginner to Intermediate  
**Estimated Time:** 20-30 minutes  
**Prerequisites:** 
- TimescaleDB extension installed
- Ignition configured and creating historian tables
- Database connection verified

## Overview

This guide covers converting Ignition's historian tables to TimescaleDB hypertables, which enables automatic partitioning, compression, and time-series optimizations. This is the foundational step for unlocking TimescaleDB's performance benefits.

---

## What is a Hypertable?

A **hypertable** is TimescaleDB's abstraction over standard PostgreSQL tables that:

- **Automatically partitions** data into time-based chunks
- **Optimizes** time-series queries
- **Enables** native compression
- **Supports** continuous aggregates
- **Maintains** full SQL compatibility

### Key Benefits

| Feature | Benefit |
|---------|---------|
| **Automatic Partitioning** | No manual partition management required |
| **Query Performance** | 10-100x faster for time-range queries |
| **Compression** | 10-20x storage reduction |
| **Chunk Management** | Easy data lifecycle policies |
| **Index Efficiency** | Optimized indexes per chunk |

### How Hypertables Work

```
Regular PostgreSQL Table:
┌─────────────────────────────────────┐
│     sqlth_1_data (single table)     │
│   [All data in one large table]     │
└─────────────────────────────────────┘

TimescaleDB Hypertable:
┌─────────────────────────────────────┐
│   sqlth_1_data (hypertable view)    │
├─────────────────────────────────────┤
│ Chunk 1 │ Chunk 2 │ Chunk 3 │ ...  │
│ Day 1-2 │ Day 3-4 │ Day 5-6 │      │
└─────────────────────────────────────┘
    ↓ Compressed  ↓ Compressed
```

---

## Prerequisites Check

Before creating hypertables, verify these conditions:

### 1. TimescaleDB Extension Enabled

```sql
-- Connect to historian database
\c historian

-- Check if TimescaleDB is installed
SELECT * FROM pg_extension WHERE extname = 'timescaledb';
```

**Expected:** One row showing the timescaledb extension.

### 2. Ignition Tables Created

```sql
-- List Ignition historian tables
\dt sqlth*
```

**Expected tables:**
- `sqlth_1_data` - Main historical data (required)
- `sqlth_te` - Tag metadata
- `sqlth_partitions` - Partition information
- `sqlth_drv` - Driver information

**If tables don't exist:**
1. Verify Ignition historian is configured and running
2. Wait 1-2 minutes for Ignition to create tables
3. Check Ignition Gateway logs for errors

### 3. Data in Tables (Optional but Recommended)

```sql
-- Check for existing data
SELECT COUNT(*) as row_count FROM sqlth_1_data;
```

**Note:** You can create hypertables on empty tables, but having sample data helps verify the migration.

---

## Creating the Hypertable

### Method 1: Automated Script (Recommended)

Use the provided SQL script for a complete, automated setup:

```bash
# Run the hypertable configuration script
psql -U postgres -d historian -f sql/schema/02-configure-hypertables.sql
```

**This script automatically:**
- ✅ Verifies prerequisites
- ✅ Creates hypertable with optimal chunk size
- ✅ Configures compression settings
- ✅ Sets up retention policies
- ✅ Creates performance indexes
- ✅ Analyzes tables
- ✅ Displays verification summary

**Skip to [Verification](#verification) section after running the script.**

---

### Method 2: Manual Step-by-Step

For learning or custom configurations, follow these manual steps.

#### Step 1: Determine Chunk Size

Chunk size determines how data is partitioned. Best practices:

| Data Volume | Recommended Chunk Size | Milliseconds |
|-------------|------------------------|--------------|
| Low (<1000 tags) | 7 days | 604800000 |
| Medium (1000-5000 tags) | 3 days | 259200000 |
| High (5000-10000 tags) | 1 day | 86400000 |
| Very High (>10000 tags) | 12 hours | 43200000 |

**Default recommendation:** 24 hours (86400000 ms) - works for most use cases.

**Why these sizes?**
- Chunk size affects query performance
- Too small: Excessive chunk overhead
- Too large: Less parallelization benefit
- Target: ~10-25 chunks for typical queries

#### Step 2: Check Existing Data

```sql
-- Analyze current data distribution
SELECT 
    COUNT(*) as total_records,
    MIN(t_stamp) as earliest_timestamp,
    MAX(t_stamp) as latest_timestamp,
    to_timestamp(MIN(t_stamp)/1000) as earliest_date,
    to_timestamp(MAX(t_stamp)/1000) as latest_date,
    COUNT(DISTINCT tagid) as unique_tags,
    pg_size_pretty(pg_total_relation_size('sqlth_1_data')) as current_size
FROM sqlth_1_data;
```

**Save this output** - you'll compare it after conversion.

#### Step 3: Create Hypertable

**If table is EMPTY (no data yet):**

```sql
SELECT create_hypertable(
    'sqlth_1_data',           -- table name
    't_stamp',                -- time column
    chunk_time_interval => 86400000,  -- 24 hours in milliseconds
    if_not_exists => TRUE
);
```

**If table has EXISTING DATA:**

```sql
SELECT create_hypertable(
    'sqlth_1_data',           
    't_stamp',                
    chunk_time_interval => 86400000,  
    if_not_exists => TRUE,
    migrate_data => TRUE      -- ⚠️ Required for existing data
);
```

**⚠️ IMPORTANT:** The `migrate_data => TRUE` parameter:
- Migrates all existing data into chunks
- May take several minutes for large tables
- Locks the table during migration
- Plan for brief downtime if Ignition is actively writing

**Expected output:**
```
           create_hypertable            
----------------------------------------
 (1,public,sqlth_1_data,t)
(1 row)
```

#### Step 4: Create Integer Now Function

TimescaleDB needs a function to understand the current time in your timestamp format (milliseconds):

```sql
CREATE OR REPLACE FUNCTION unix_now() 
RETURNS BIGINT 
LANGUAGE SQL 
STABLE 
AS $$ 
    SELECT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
$$;
```

#### Step 5: Set Integer Now Function

```sql
SELECT set_integer_now_func('sqlth_1_data', 'unix_now');
```

This tells TimescaleDB how to interpret "now" for your hypertable.

---

## Configuring Compression

### Enable Compression on Hypertable

The first step is to enable compression and configure how data should be compressed:

```sql
-- Enable compression with optimal settings for Ignition historian
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);
```

**Valid compression parameters:**
- `timescaledb.compress` - Enables compression (required)
- `timescaledb.compress_orderby` - Sort order within compressed batches
- `timescaledb.compress_segmentby` - Columns that partition compressed data

**What these settings do:**
- **compress_orderby = 't_stamp DESC'**: Stores most recent data first in compressed batches (optimal for time-series queries)
- **compress_segmentby = 'tagid'**: Each tag's data is compressed separately (enables efficient tag-specific queries)

### Add Compression Policy

After enabling compression, create a policy to automatically compress old chunks:

```sql
-- Compress chunks older than 7 days (7 days in milliseconds)
SELECT add_compression_policy('sqlth_1_data', compress_after => 604800000);
```

**This creates a background job that:**
- Runs periodically (default: every 12 hours)
- Finds chunks older than 7 days (604800000 milliseconds = 7 days)
- Compresses them automatically
- Requires no manual intervention

**Common compression intervals:**
- 7 days: `604800000` milliseconds
- 14 days: `1209600000` milliseconds
- 30 days: `2592000000` milliseconds
- 90 days: `7776000000` milliseconds

**Note:** Because the time column is BIGINT (milliseconds since epoch), compression intervals must be specified as integers in milliseconds, not INTERVAL types.

### View Compression Settings

```sql
-- Check current compression configuration
SELECT * FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'sqlth_1_data';
```

### View Compression Policies

```sql
-- Check active compression policy
SELECT * FROM timescaledb_information.jobs
WHERE application_name = 'Compression Policy'
  AND hypertable_name = 'sqlth_1_data';
```

### View Chunk Information

```sql
-- List all chunks for the hypertable
SELECT 
    chunk_schema,
    chunk_name,
    range_start,
    range_end,
    to_timestamp(range_start/1000) as start_time,
    to_timestamp(range_end/1000) as end_time,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC;
```

---

## Understanding Ignition Partition Settings

### Important: Disable Ignition Partitioning

In Ignition Gateway configuration for the SQL Historian:

| Setting | Value | Why |
|---------|-------|-----|
| **Enable Partitioning** | ❌ Unchecked | TimescaleDB handles this |
| **Enable Data Pruning** | ❌ Unchecked | Use TimescaleDB retention policies instead |

**Why disable Ignition partitioning?**

1. **Double partitioning overhead** - Both systems would try to partition
2. **Naming conflicts** - Ignition creates `sqlth_1_data_pYYYY_MM` tables
3. **Continuous aggregate issues** - Can't work with Ignition's partitions
4. **Management complexity** - Single system is simpler

### Update Partition Flags

For optimal performance with TimescaleDB:

```sql
-- Disable seed queries (improves performance)
UPDATE sqlth_partitions 
SET flags = 1 
WHERE pname = 'sqlth_1_data';
```

**What this does:**
- Disables automatic value interpolation at trend start
- Improves query performance significantly
- Trade-off: Trends start with first actual value, not interpolated

---

## Creating Performance Indexes

### BRIN Index for Time Column

Best for time-series data:

```sql
CREATE INDEX IF NOT EXISTS idx_sqlth_data_tstamp_brin 
ON sqlth_1_data USING BRIN (t_stamp);
```

**BRIN (Block Range Index) benefits:**
- Extremely small index size (~1% of data)
- Fast for time-range queries
- Minimal maintenance overhead
- Perfect for time-series data

### Composite Index for Tag Queries

```sql
CREATE INDEX IF NOT EXISTS idx_sqlth_data_tagid_tstamp 
ON sqlth_1_data (tagid, t_stamp DESC);
```

**Benefits:**
- Fast queries filtering by specific tags
- Descending time order (most recent first)
- Supports Power Chart and Easy Chart queries

### Data Integrity Index (Optional)

If you frequently filter by data quality:

```sql
CREATE INDEX IF NOT EXISTS idx_sqlth_data_quality
ON sqlth_1_data (dataintegrity) 
WHERE dataintegrity != 192;  -- Index only bad quality data
```

---

## Verification

### 1. Verify Hypertable Creation

```sql
-- Check hypertable configuration
SELECT 
    hypertable_schema,
    hypertable_name,
    num_dimensions,
    num_chunks,
    compression_enabled,
    replication_factor
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'sqlth_1_data';
```

**Expected output:**
```
 hypertable_schema | hypertable_name | num_dimensions | num_chunks | compression_enabled | replication_factor 
-------------------+-----------------+----------------+------------+---------------------+--------------------
 public            | sqlth_1_data    |              1 |          3 | t                   |                  1
```

### 2. Verify Data Integrity

```sql
-- Compare before/after counts
SELECT 
    COUNT(*) as current_count,
    COUNT(DISTINCT tagid) as unique_tags,
    MIN(t_stamp) as min_timestamp,
    MAX(t_stamp) as max_timestamp
FROM sqlth_1_data;
```

**Compare with your pre-conversion query results.**

### 3. Verify Chunks Created

```sql
-- List chunks with size information
SELECT 
    chunk_name,
    range_start,
    range_end,
    to_timestamp(range_start/1000) as start_date,
    to_timestamp(range_end/1000) as end_date,
    pg_size_pretty(total_bytes) as chunk_size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 10;
```

### 4. Verify Indexes

```sql
-- List all indexes on hypertable
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'sqlth_1_data'
ORDER BY indexname;
```

### 5. Test Query Performance

```sql
-- Time a typical query
EXPLAIN ANALYZE
SELECT 
    tagid,
    COUNT(*) as sample_count,
    AVG(COALESCE(intvalue, floatvalue)) as avg_value
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
GROUP BY tagid;
```

**Look for:**
- Execution time (should be fast)
- "Chunks excluded by constraints" (showing chunk elimination)
- Index usage in query plan

---

## Troubleshooting

### Error: "table has already been converted to a hypertable"

**Solution:** Table is already a hypertable. Verify with:

```sql
SELECT * FROM timescaledb_information.hypertables 
WHERE hypertable_name = 'sqlth_1_data';
```

### Error: "cannot create a unique index without the column"

**Cause:** Trying to create a unique index that doesn't include the time column.

**Solution:** Don't use UNIQUE constraints on hypertables, or include the time column:

```sql
-- If you need uniqueness
CREATE UNIQUE INDEX ON sqlth_1_data (tagid, t_stamp);
```

### Slow Migration (migrate_data taking too long)

**If migration exceeds 5 minutes:**

1. Check table size:
```sql
SELECT pg_size_pretty(pg_total_relation_size('sqlth_1_data'));
```

2. Cancel and use batch migration:
```sql
-- See Data Migration guide for batch strategies
```

3. Or increase maintenance_work_mem:
```sql
SET maintenance_work_mem = '1GB';
```

### Chunks Not Being Created

**Verify time values are in correct format:**

```sql
-- Check timestamp format
SELECT 
    t_stamp,
    to_timestamp(t_stamp/1000) as human_readable,
    t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000) as is_recent
FROM sqlth_1_data
LIMIT 5;
```

**Expected:** `human_readable` should show actual dates, not 1970 or far future.

---

## Advanced Configuration

### Custom Chunk Sizes by Time Period

For varying data patterns:

```sql
-- Not recommended for beginners, but possible:
-- You can change chunk interval (affects future chunks only)
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '12 hours');
```

### Multiple Time Dimensions (Advanced)

For specialized use cases:

```sql
-- Add space partitioning by tagid (expert-level)
SELECT add_dimension(
    'sqlth_1_data',
    'tagid',
    number_partitions => 4
);
```

**⚠️ Warning:** Space partitioning adds complexity. Only use if you have >10,000 tags.

---

## Monitoring and Maintenance

### Monitor Chunk Growth

```sql
-- Track chunk creation over time
SELECT 
    DATE_TRUNC('day', to_timestamp(range_start/1000)) as chunk_day,
    COUNT(*) as chunks_created,
    SUM(total_bytes) as total_size_bytes,
    pg_size_pretty(SUM(total_bytes)) as total_size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
GROUP BY chunk_day
ORDER BY chunk_day DESC;
```

### Analyze Table Regularly

```sql
-- Update statistics for query planner
ANALYZE sqlth_1_data;
```

**Recommendation:** Run ANALYZE after significant data changes or weekly.

### Check Hypertable Health

```sql
-- Comprehensive health check
SELECT 
    h.hypertable_name,
    h.num_chunks,
    pg_size_pretty(SUM(c.total_bytes)) as total_size,
    pg_size_pretty(SUM(c.total_bytes) / h.num_chunks) as avg_chunk_size,
    COUNT(CASE WHEN c.is_compressed THEN 1 END) as compressed_chunks,
    COUNT(CASE WHEN NOT c.is_compressed THEN 1 END) as uncompressed_chunks
FROM timescaledb_information.hypertables h
LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
WHERE h.hypertable_name = 'sqlth_1_data'
GROUP BY h.hypertable_name, h.num_chunks;
```

---

## Next Steps

✅ Hypertable created and verified

**Continue to:**
- [Compression Configuration](02-compression.md) - Enable 10-20x storage reduction
- [Retention Policies](03-retention-policies.md) - Automatic data lifecycle management
- [Continuous Aggregates](04-continuous-aggregates.md) - Multi-resolution downsampling

**Or explore:**
- [Performance Tuning](../optimization/01-performance-tuning.md) - Optimize query performance
- [Basic Queries](../examples/01-basic-queries.md) - Query your hypertable

---

## Reference

### Common Commands

```sql
-- List all hypertables
SELECT * FROM timescaledb_information.hypertables;

-- Show chunks for a hypertable
SELECT * FROM show_chunks('sqlth_1_data');

-- Get hypertable statistics
SELECT * FROM hypertable_detailed_size('sqlth_1_data');

-- Drop a specific chunk (careful!)
SELECT drop_chunks('sqlth_1_data', older_than => INTERVAL '2 years');
```

### Additional Resources

- [TimescaleDB Hypertables Documentation](https://docs.timescale.com/use-timescale/latest/hypertables/)
- [Chunk Configuration Best Practices](https://docs.timescale.com/use-timescale/latest/hypertables/about-hypertables/)
- [Ignition Tag Historian](https://docs.inductiveautomation.com/docs/8.3/intro)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
