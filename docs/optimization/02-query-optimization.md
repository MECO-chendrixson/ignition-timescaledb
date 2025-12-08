# Query Optimization

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate to Advanced  
**Estimated Time:** 1-2 hours  
**Prerequisites:** 
- Understanding of SQL
- Familiarity with EXPLAIN plans
- Basic index knowledge

## Overview

This guide covers writing efficient queries for TimescaleDB historian data, understanding query plans, and optimizing common patterns used in Ignition applications.

---

## Understanding EXPLAIN

### Basic EXPLAIN

```sql
EXPLAIN
SELECT * FROM sqlth_1_data 
WHERE tagid = 100 
  AND t_stamp >= 1234567890000;
```

**Output shows:**
- Query plan steps
- Estimated costs
- Row estimates

### EXPLAIN ANALYZE

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM sqlth_1_data 
WHERE tagid = 100 
  AND t_stamp >= 1234567890000;
```

**Additional information:**
- Actual execution time
- Actual rows returned
- Buffer usage (cache hits/misses)
- I/O statistics

### Reading EXPLAIN Output

```
Seq Scan on sqlth_1_data  (cost=0.00..50000.00 rows=1000 width=32)
  Filter: (tagid = 100)
```

**Key metrics:**
- `cost=X..Y`: Startup cost .. Total cost
- `rows=N`: Estimated rows
- `width=N`: Average row size in bytes

**Node types:**
- **Seq Scan**: Full table scan (slow for large tables)
- **Index Scan**: Using index (good)
- **Index Only Scan**: Only index, no table (best)
- **Bitmap Heap Scan**: Multiple index conditions
- **Nested Loop**: Join method
- **Hash Join**: Join method (usually faster)

---

## Index Strategy

### Existing Indexes on sqlth_1_data

After hypertable setup, you should have:

```sql
-- Check indexes
\d sqlth_1_data

-- List all indexes
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'sqlth_1_data';
```

**Expected indexes:**
1. BRIN index on `t_stamp` (time-based queries)
2. B-tree index on `(tagid, t_stamp DESC)` (tag-specific queries)

### When to Add Indexes

**Add index when:**
- ✅ Query filters on column frequently
- ✅ Column has high cardinality
- ✅ Seq Scan appears in EXPLAIN for targeted queries
- ✅ Query is run often

**Don't add index when:**
- ❌ Table is small (<10K rows)
- ❌ Column has low cardinality (few unique values)
- ❌ Query rarely run
- ❌ Column frequently updated

### Creating Effective Indexes

**Composite index order matters:**

```sql
-- Good: (tagid, t_stamp) for queries filtering both
CREATE INDEX idx_tag_time ON sqlth_1_data (tagid, t_stamp DESC);

-- Less useful: (t_stamp, tagid) doesn't help tag-only queries
```

**Index on expressions:**

```sql
-- For queries using to_timestamp frequently
CREATE INDEX idx_timestamp_human 
ON sqlth_1_data (to_timestamp(t_stamp/1000));

-- For quality filtering
CREATE INDEX idx_quality 
ON sqlth_1_data (dataintegrity) 
WHERE dataintegrity != 192;  -- Partial index for bad quality only
```

### BRIN Indexes for Time-Series

**Why BRIN for t_stamp:**
- Extremely small (100x smaller than B-tree)
- Perfect for sequential data
- Fast for time-range queries

```sql
-- BRIN index on timestamp
CREATE INDEX idx_tstamp_brin ON sqlth_1_data USING BRIN (t_stamp);

-- Check BRIN effectiveness
SELECT * FROM brin_summarize_range('sqlth_1_data', 'idx_tstamp_brin');
```

---

## Query Patterns and Optimization

### Pattern 1: Time-Range Queries

**❌ Slow - Using DATE functions:**

```sql
SELECT * FROM sqlth_1_data
WHERE to_timestamp(t_stamp/1000) >= NOW() - INTERVAL '1 day';
-- Can't use index on t_stamp (function prevents it)
```

**✅ Fast - Filter on raw t_stamp:**

```sql
SELECT * FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000);
-- Uses BRIN index efficiently
```

### Pattern 2: Tag Filtering

**❌ Slow - Join every time:**

```sql
SELECT d.* 
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature';
-- Join overhead on every query
```

**✅ Fast - Cache tagid:**

```sql
-- First, get tagid once
SELECT id FROM sqlth_te WHERE tagpath = '[default]Production/Temperature';
-- Result: 100

-- Then use directly
SELECT * FROM sqlth_1_data WHERE tagid = 100;
-- Direct index lookup, no join
```

**✅ Alternative - Use CTE:**

```sql
WITH target_tag AS (
    SELECT id FROM sqlth_te WHERE tagpath = '[default]Production/Temperature'
)
SELECT d.* 
FROM sqlth_1_data d
WHERE tagid = (SELECT id FROM target_tag)
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000);
```

### Pattern 3: Aggregations

**❌ Slow - Aggregate raw data:**

```sql
-- Aggregating 30 days of second-level data
SELECT 
    DATE(to_timestamp(t_stamp/1000)) as day,
    AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
WHERE tagid = 100
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
GROUP BY day;
-- Scans millions of rows
```

**✅ Fast - Use continuous aggregates:**

```sql
-- Query pre-aggregated data
SELECT 
    bucket::date as day,
    avg_value
FROM tag_history_1day
WHERE tagid = 100
  AND bucket >= NOW() - INTERVAL '30 days';
-- Scans only 30 rows
```

### Pattern 4: Multiple Tags

**❌ Slow - Separate queries:**

```sql
-- Query 1
SELECT * FROM sqlth_1_data WHERE tagid = 100;
-- Query 2
SELECT * FROM sqlth_1_data WHERE tagid = 101;
-- Query 3
SELECT * FROM sqlth_1_data WHERE tagid = 102;
-- Multiple round trips
```

**✅ Fast - Single query with IN:**

```sql
SELECT * FROM sqlth_1_data 
WHERE tagid IN (100, 101, 102)
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000);
-- Single query, single scan
```

**✅ Better - Use ANY for larger lists:**

```sql
SELECT * FROM sqlth_1_data 
WHERE tagid = ANY(ARRAY[100, 101, 102, ...])
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000);
-- More efficient for large tag lists
```

---

## Advanced Optimization Techniques

### Use time_bucket Instead of DATE_TRUNC

**❌ Slower:**

```sql
SELECT 
    DATE_TRUNC('hour', to_timestamp(t_stamp/1000)) as hour,
    AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
GROUP BY hour;
```

**✅ Faster (TimescaleDB optimized):**

```sql
SELECT 
    time_bucket(3600000, t_stamp) as hour_bucket,
    AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
GROUP BY hour_bucket;
-- TimescaleDB optimizes time_bucket for chunk exclusion
```

### Chunk Exclusion

TimescaleDB automatically excludes chunks outside time range:

```sql
EXPLAIN (ANALYZE)
SELECT * FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000);

-- Look for:
-- "Chunks excluded during startup: N"
```

**To maximize chunk exclusion:**
- Always filter on t_stamp
- Use >= and < operators (not BETWEEN)
- Avoid functions on t_stamp in WHERE clause

### Parallel Query Execution

Enable parallelism for large scans:

```sql
-- Check if parallel workers are used
EXPLAIN (ANALYZE)
SELECT COUNT(*) FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000);

-- Look for "Parallel Seq Scan" or "Parallel Index Scan"
```

**Force parallel query:**

```sql
SET max_parallel_workers_per_gather = 4;
SET parallel_setup_cost = 100;
SET parallel_tuple_cost = 0.001;
```

### Window Functions Optimization

**❌ Slow - Subquery for each row:**

```sql
SELECT 
    t_stamp,
    value,
    (SELECT AVG(value) FROM sqlth_1_data AS s 
     WHERE s.t_stamp BETWEEN d.t_stamp - 3600000 AND d.t_stamp) as rolling_avg
FROM sqlth_1_data AS d;
```

**✅ Fast - Window function:**

```sql
SELECT 
    t_stamp,
    COALESCE(intvalue, floatvalue) as value,
    AVG(COALESCE(intvalue, floatvalue)) OVER (
        ORDER BY t_stamp 
        ROWS BETWEEN 3600 PRECEDING AND CURRENT ROW
    ) as rolling_avg
FROM sqlth_1_data
WHERE tagid = 100;
```

---

## Join Optimization

### Join Order Matters

**❌ Poor join order:**

```sql
SELECT d.*, t.tagpath
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= 1234567890000;
-- Joins ALL rows then filters
```

**✅ Filter first:**

```sql
SELECT d.*, t.tagpath
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= 1234567890000
  AND d.tagid IN (SELECT id FROM sqlth_te WHERE retired IS NULL);
-- Filters before join
```

### Join Methods

**Nested Loop:** Good for small result sets
**Hash Join:** Good for medium result sets
**Merge Join:** Good for sorted data

**Control join method:**

```sql
-- Disable nested loop if suboptimal
SET enable_nestloop = off;

-- Force hash join
SET enable_hashjoin = on;
```

---

## Common Anti-Patterns

### Anti-Pattern 1: SELECT *

**❌ Don't:**

```sql
SELECT * FROM sqlth_1_data WHERE tagid = 100;
-- Returns all columns, wastes bandwidth
```

**✅ Do:**

```sql
SELECT t_stamp, floatvalue, dataintegrity 
FROM sqlth_1_data 
WHERE tagid = 100;
-- Only needed columns
```

### Anti-Pattern 2: OR Conditions

**❌ Don't:**

```sql
SELECT * FROM sqlth_1_data
WHERE tagid = 100 OR tagid = 101 OR tagid = 102;
-- Can't use index efficiently
```

**✅ Do:**

```sql
SELECT * FROM sqlth_1_data
WHERE tagid IN (100, 101, 102);
-- Single index scan
```

### Anti-Pattern 3: Implicit Type Conversions

**❌ Don't:**

```sql
SELECT * FROM sqlth_1_data WHERE tagid = '100';
-- String '100' converted to int, may prevent index use
```

**✅ Do:**

```sql
SELECT * FROM sqlth_1_data WHERE tagid = 100;
-- Correct type, uses index
```

### Anti-Pattern 4: DISTINCT Without Need

**❌ Don't:**

```sql
SELECT DISTINCT tagid FROM sqlth_1_data;
-- Expensive sort/hash operation
```

**✅ Do (if you know data is unique):**

```sql
SELECT tagid FROM sqlth_1_data GROUP BY tagid;
-- Or better, query tag metadata
SELECT id FROM sqlth_te WHERE retired IS NULL;
```

---

## Query Rewriting Examples

### Example 1: Pivot Query

**❌ Original (slow):**

```sql
SELECT 
    t_stamp,
    (SELECT floatvalue FROM sqlth_1_data WHERE tagid=100 AND t_stamp=d.t_stamp LIMIT 1) as temp,
    (SELECT floatvalue FROM sqlth_1_data WHERE tagid=101 AND t_stamp=d.t_stamp LIMIT 1) as press
FROM sqlth_1_data d
WHERE t_stamp >= 1234567890000;
```

**✅ Optimized:**

```sql
SELECT 
    t_stamp,
    MAX(CASE WHEN tagid = 100 THEN floatvalue END) as temp,
    MAX(CASE WHEN tagid = 101 THEN floatvalue END) as press
FROM sqlth_1_data
WHERE tagid IN (100, 101)
  AND t_stamp >= 1234567890000
GROUP BY t_stamp;
```

### Example 2: Latest Values

**❌ Original (slow):**

```sql
SELECT tagid, MAX(t_stamp) as latest
FROM sqlth_1_data
GROUP BY tagid;
-- Scans entire table
```

**✅ Optimized:**

```sql
SELECT DISTINCT ON (tagid) 
    tagid, 
    t_stamp, 
    COALESCE(intvalue, floatvalue) as value
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '5 minutes') * 1000)
ORDER BY tagid, t_stamp DESC;
-- Only scans recent data
```

---

## Monitoring Query Performance

### Find Slow Queries

```sql
-- Enable pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Top 10 slowest queries by average time
SELECT 
    LEFT(query, 60) as query_start,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_ms,
    ROUND(total_exec_time::numeric, 2) as total_ms,
    ROUND((100 * total_exec_time / SUM(total_exec_time) OVER())::numeric, 2) as pct_total
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Analyze Table Statistics

```sql
-- Update statistics for better query plans
ANALYZE sqlth_1_data;

-- Check statistics age
SELECT 
    schemaname,
    tablename,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE tablename = 'sqlth_1_data';
```

---

## Query Optimization Checklist

**Before running query:**
- [ ] Filter on t_stamp to enable chunk exclusion
- [ ] Use tagid directly (not JOIN every time)
- [ ] Select only needed columns
- [ ] Use IN or ANY instead of OR
- [ ] Use continuous aggregates for historical data
- [ ] Use time_bucket instead of DATE_TRUNC

**After slow query:**
- [ ] Run EXPLAIN ANALYZE
- [ ] Check for Seq Scan (should be Index Scan)
- [ ] Verify chunk exclusion is working
- [ ] Check if parallel workers are used
- [ ] Review buffer hits vs reads
- [ ] Consider adding index
- [ ] Consider creating continuous aggregate

---

## Next Steps

- [Storage Optimization](03-storage-optimization.md)
- [Scaling Strategies](04-scaling.md)
- [Performance Tuning](01-performance-tuning.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
