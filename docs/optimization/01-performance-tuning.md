# Performance Tuning

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate to Advanced  
**Estimated Time:** 1-2 hours  
**Prerequisites:** 
- PostgreSQL and TimescaleDB installed
- Basic understanding of database configuration
- Root/sudo access to server

## Overview

This guide covers PostgreSQL and TimescaleDB performance tuning specifically for Ignition historian workloads. Proper configuration can dramatically improve query performance, reduce I/O load, and optimize resource utilization.

---

## Understanding the Workload

### Ignition Historian Characteristics

**Write Pattern:**
- High volume inserts (1000s of tags × scan rate)
- Minimal updates/deletes
- Sequential timestamp writes
- Batch inserts from Ignition

**Read Pattern:**
- Time-range queries (last hour, day, week)
- Aggregation queries (hourly, daily averages)
- Multiple concurrent users
- Dashboard refresh queries

**Optimal Configuration:**
- Favor writes over reads initially
- Optimize for time-series access patterns
- Large shared buffers for caching
- Efficient WAL management

---

## PostgreSQL Memory Configuration

### shared_buffers

**Purpose:** PostgreSQL's main cache for data pages

```conf
# postgresql.conf

# Recommended: 25% of total RAM
# Example for 32GB RAM server:
shared_buffers = 8GB

# Minimum (small systems):
shared_buffers = 2GB

# Maximum (large systems):
shared_buffers = 16GB
```

**Why 25%?**
- TimescaleDB benefits from larger shared_buffers
- Leaves room for OS file cache
- Balances PostgreSQL and system needs

**Verification:**
```sql
SHOW shared_buffers;
```

### effective_cache_size

**Purpose:** Hints to query planner about available OS cache

```conf
# Recommended: 50-75% of total RAM
effective_cache_size = 24GB  # For 32GB RAM

# This is NOT allocated memory, just a hint
# Set to: RAM - shared_buffers - OS overhead (2GB)
```

**Formula:**
```
effective_cache_size = Total RAM × 0.75
```

### work_mem

**Purpose:** Memory for sorting and hash operations per operation

```conf
# Start conservative
work_mem = 64MB

# For systems with many connections:
work_mem = 32MB

# For systems with few connections and complex queries:
work_mem = 256MB
```

**⚠️ Warning:** 
- This is PER operation, not per connection
- Formula: `work_mem × max_connections × avg_operations` should stay under RAM
- A complex query might use 5-10× work_mem

**Find optimal value:**
```sql
-- Check if queries are spilling to disk
SELECT 
    query,
    temp_blks_written,
    temp_blks_written * 8192 / 1024 / 1024 as temp_mb
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

If you see temp writes, consider increasing work_mem.

### maintenance_work_mem

**Purpose:** Memory for VACUUM, CREATE INDEX, ALTER TABLE

```conf
# Recommended: 1-2GB
maintenance_work_mem = 2GB

# For large databases:
maintenance_work_mem = 4GB

# Don't exceed 8GB (diminishing returns)
```

**Use Case:**
- Speeds up VACUUM operations
- Faster index creation
- Quicker ALTER TABLE operations

---

## Connection Management

### max_connections

```conf
# Default is often 100, but Ignition uses many connections

# Small installation (< 10 users):
max_connections = 100

# Medium installation (10-50 users):
max_connections = 200

# Large installation (50+ users):
max_connections = 300
```

**Consider Connection Pooling:**
Use PgBouncer to reduce actual database connections:

```ini
# pgbouncer.ini
[databases]
historian = host=localhost port=5432 dbname=historian

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = md5
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

**Benefits:**
- Reduce connection overhead
- Better resource utilization
- Support more concurrent users

### Connection Timeout Settings

```conf
# Kill idle connections after 10 minutes
idle_in_transaction_session_timeout = 600000  # milliseconds

# Statement timeout (prevent runaway queries)
statement_timeout = 300000  # 5 minutes

# Lock timeout
lock_timeout = 30000  # 30 seconds
```

---

## Write Performance

### WAL (Write-Ahead Log) Configuration

```conf
# WAL buffer size (increase for high write loads)
wal_buffers = 16MB

# Checkpoint settings (balance durability vs. performance)
min_wal_size = 2GB
max_wal_size = 8GB

# Checkpoint completion target (spread I/O)
checkpoint_completion_target = 0.9

# Checkpoint timeout
checkpoint_timeout = 15min
```

**For High-Volume Writes:**

```conf
# Reduce fsync frequency (more performance, less durability)
synchronous_commit = off  # ⚠️ Use with caution

# Or use async commit with group commit
synchronous_commit = local
commit_delay = 100  # microseconds
commit_siblings = 5
```

**⚠️ Warning:** Setting `synchronous_commit = off`:
- ✅ Much faster writes (2-3x improvement)
- ❌ Risk of data loss in crash (up to 1 second)
- ✅ Acceptable for historian data (Ignition has store & forward)
- ❌ NOT acceptable for alarm/audit logs

### Ignition-Specific Write Optimization

In Ignition database connection properties:

```
reWriteBatchedInserts=true;defaultRowFetchSize=10000;
```

**Effect:**
- Batches INSERT statements
- Reduces round trips
- 2-5x faster bulk inserts

---

## Query Performance

### Query Planner Settings

```conf
# Encourage use of indexes
random_page_cost = 1.1  # For SSDs (default is 4.0)
seq_page_cost = 1.0

# Parallel query settings
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_worker_processes = 8

# Effective I/O concurrency (for SSDs)
effective_io_concurrency = 200
```

**Why lower random_page_cost for SSDs?**
- Traditional HDDs: Random access is 4× slower than sequential
- SSDs: Random and sequential access nearly equal speed
- Lower value encourages index usage

### JIT Compilation (PostgreSQL 13+)

```conf
# Enable JIT for complex queries
jit = on
jit_above_cost = 100000
jit_inline_above_cost = 500000
jit_optimize_above_cost = 500000
```

**When JIT Helps:**
- ✅ Complex aggregations
- ✅ Large result sets
- ✅ Joins with many rows
- ❌ Simple index lookups (adds overhead)

**Check JIT usage:**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT ... FROM sqlth_1_data ...;
-- Look for "JIT:" in output
```

---

## Autovacuum Tuning

### Why Autovacuum Matters

TimescaleDB hypertables generate table bloat from:
- Updates to tag metadata
- Recompression operations
- Index maintenance

### Configuration

```conf
# Enable autovacuum (should always be on)
autovacuum = on

# Autovacuum workers
autovacuum_max_workers = 4

# Reduce autovacuum cost delay (more aggressive)
autovacuum_vacuum_cost_delay = 10ms  # Default is 20ms

# Increase cost limit (allow more work before sleeping)
autovacuum_vacuum_cost_limit = 1000  # Default is 200

# Lower threshold to vacuum more frequently
autovacuum_vacuum_scale_factor = 0.05  # Default is 0.2 (20%)
autovacuum_analyze_scale_factor = 0.02  # Default is 0.1
```

**For TimescaleDB:**

```conf
# Vacuum settings for hypertables
autovacuum_vacuum_threshold = 1000
autovacuum_analyze_threshold = 500
```

**Per-table tuning:**

```sql
-- More aggressive autovacuum for frequently updated tables
ALTER TABLE sqlth_te SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_analyze_scale_factor = 0.005
);

-- Less aggressive for append-only tables
ALTER TABLE sqlth_1_data SET (
    autovacuum_vacuum_scale_factor = 0.1
);
```

---

## I/O Performance

### Background Writer

```conf
# Background writer settings
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0
```

### Asynchronous I/O

```conf
# Enable asynchronous I/O (if supported)
wal_sync_method = fdatasync  # or open_datasync

# For high-end SSDs
full_page_writes = off  # ⚠️ Only with battery-backed cache or ZFS
```

---

## TimescaleDB-Specific Settings

### Background Workers

```conf
# TimescaleDB background job workers
timescaledb.max_background_workers = 8

# Compression workers
max_parallel_workers_per_gather = 4
```

### Chunk Sizing

Optimal chunk size affects query performance:

```sql
-- For high-frequency data (1-second scan rate)
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '12 hours');

-- For medium-frequency data
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '1 day');

-- For low-frequency data
SELECT set_chunk_time_interval('sqlth_1_data', INTERVAL '7 days');
```

**Goal:** 10-25 chunks for typical time-range queries

---

## Monitoring Performance

### Key Metrics to Track

```sql
-- 1. Cache hit ratio (should be > 99%)
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit) as heap_hit,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;

-- 2. Table bloat
SELECT 
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- 3. Slow queries
SELECT 
    query,
    calls,
    mean_exec_time,
    max_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 4. Connection count
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';
```

### Enable pg_stat_statements

```conf
# postgresql.conf
shared_preload_libraries = 'timescaledb,pg_stat_statements'

# Track all statements
pg_stat_statements.track = all
pg_stat_statements.max = 10000
```

```sql
-- Enable extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

---

## Complete Configuration Example

### For Small System (8GB RAM, SSD)

```conf
# Memory
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 32MB
maintenance_work_mem = 512MB

# Connections
max_connections = 100

# WAL
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB
checkpoint_completion_target = 0.9

# Query Planner
random_page_cost = 1.1
effective_io_concurrency = 200

# Parallelism
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_worker_processes = 4

# Autovacuum
autovacuum_max_workers = 2
autovacuum_vacuum_cost_delay = 10ms
autovacuum_vacuum_cost_limit = 1000

# TimescaleDB
timescaledb.max_background_workers = 4
```

### For Medium System (32GB RAM, SSD)

```conf
# Memory
shared_buffers = 8GB
effective_cache_size = 24GB
work_mem = 64MB
maintenance_work_mem = 2GB

# Connections
max_connections = 200

# WAL
wal_buffers = 16MB
min_wal_size = 2GB
max_wal_size = 8GB
checkpoint_completion_target = 0.9

# Query Planner
random_page_cost = 1.1
effective_io_concurrency = 200

# Parallelism
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_worker_processes = 8

# Autovacuum
autovacuum_max_workers = 4
autovacuum_vacuum_cost_delay = 10ms
autovacuum_vacuum_cost_limit = 1000

# TimescaleDB
timescaledb.max_background_workers = 8
```

### For Large System (128GB RAM, NVMe SSD)

```conf
# Memory
shared_buffers = 32GB
effective_cache_size = 96GB
work_mem = 128MB
maintenance_work_mem = 4GB

# Connections
max_connections = 300

# WAL
wal_buffers = 64MB
min_wal_size = 4GB
max_wal_size = 16GB
checkpoint_completion_target = 0.9

# Query Planner
random_page_cost = 1.0
effective_io_concurrency = 300

# Parallelism
max_parallel_workers_per_gather = 8
max_parallel_workers = 16
max_worker_processes = 16

# Autovacuum
autovacuum_max_workers = 8
autovacuum_vacuum_cost_delay = 5ms
autovacuum_vacuum_cost_limit = 2000

# TimescaleDB
timescaledb.max_background_workers = 16
```

---

## Applying Configuration Changes

### Linux

```bash
# Edit configuration
sudo nano /etc/postgresql/15/main/postgresql.conf

# Restart PostgreSQL
sudo systemctl restart postgresql

# Or reload for non-restart changes
sudo systemctl reload postgresql
```

### Windows

```powershell
# Edit configuration
notepad "C:\Program Files\PostgreSQL\15\data\postgresql.conf"

# Restart service
Restart-Service postgresql-x64-15
```

### Verify Changes

```sql
-- Check specific setting
SHOW shared_buffers;
SHOW work_mem;

-- Show all settings
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'effective_cache_size',
    'work_mem',
    'maintenance_work_mem',
    'max_connections'
);
```

---

## Performance Testing

### Baseline Test

```bash
# Install pgbench
sudo apt-get install postgresql-contrib

# Initialize test database
pgbench -i -s 50 testdb

# Run benchmark
pgbench -c 10 -j 2 -t 1000 testdb
```

### Real Query Testing

```sql
-- Time a typical query
\timing on

SELECT 
    time_bucket(3600000, t_stamp) as hour,
    AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
WHERE tagid = 100
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
GROUP BY hour;

-- Compare performance before/after changes
```

---

## Troubleshooting Performance Issues

### Slow Queries

**Diagnosis:**
```sql
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - pg_stat_activity.query_start > interval '1 minute';
```

**Solutions:**
- Add indexes
- Increase work_mem
- Use continuous aggregates
- Enable parallelism

### High Memory Usage

**Check:**
```sql
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    backend_type,
    state,
    pg_size_pretty(pg_backend_memory_contexts.total_bytes) as memory_used
FROM pg_stat_activity
LEFT JOIN pg_backend_memory_contexts USING (pid)
ORDER BY pg_backend_memory_contexts.total_bytes DESC NULLS LAST;
```

**Solutions:**
- Reduce work_mem
- Reduce max_connections
- Use connection pooling

### I/O Bottlenecks

**Check:**
```bash
# Linux
iostat -x 5

# Windows
perfmon (monitor Disk I/O)
```

**Solutions:**
- Increase WAL buffers
- Tune checkpoint settings
- Use faster storage (SSD/NVMe)
- Enable compression

---

## Best Practices

✅ **Start conservative** - Tune incrementally  
✅ **Monitor before and after** - Measure impact  
✅ **Document changes** - Keep change log  
✅ **Test on non-production** - Verify first  
✅ **Review logs** - Check for warnings  
✅ **Use pg_stat_statements** - Identify slow queries  
✅ **Enable autovacuum** - Never disable it  
✅ **Regular VACUUM ANALYZE** - Weekly schedule  

❌ **Don't allocate all RAM** - Leave room for OS  
❌ **Don't set work_mem too high** - Can cause OOM  
❌ **Don't disable fsync** - Unless you understand risks  
❌ **Don't ignore warnings** - PostgreSQL logs errors for a reason  

---

## Next Steps

- [Query Optimization](02-query-optimization.md) - Optimize specific queries
- [Storage Optimization](03-storage-optimization.md) - Reduce disk usage
- [Scaling Strategies](04-scaling.md) - Handle growth

---

## Additional Resources

- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [TimescaleDB Performance](https://www.tigerdata.com/docs/use-timescale/latest/performance/)
- [pgtune Configuration Generator](https://pgtune.leopard.in.ua/)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
