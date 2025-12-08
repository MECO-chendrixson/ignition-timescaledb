# Performance Issues Troubleshooting

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate to Advanced

## Overview

Comprehensive guide for diagnosing and resolving performance issues in TimescaleDB with Ignition historian.

---

## Slow Query Performance

### Symptoms
- Queries taking >5 seconds
- Power Chart loading slowly
- Dashboard timeouts
- High CPU usage during queries

### Diagnosis

**Step 1: Identify slow queries**
```sql
-- Find currently running slow queries
SELECT 
    pid,
    now() - pg_stat_activity.query_start AS duration,
    state,
    LEFT(query, 100) as query_preview
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - pg_stat_activity.query_start > interval '5 seconds'
ORDER BY duration DESC;
```

**Step 2: Analyze query plan**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM sqlth_1_data 
WHERE tagid = 100 
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000);
```

### Solutions

**1. Add missing indexes:**
```sql
-- If seeing Seq Scan on tagid
CREATE INDEX idx_tagid_tstamp ON sqlth_1_data (tagid, t_stamp DESC);

-- If seeing Seq Scan on t_stamp
CREATE INDEX idx_tstamp_brin ON sqlth_1_data USING BRIN (t_stamp);
```

**2. Use continuous aggregates:**
```sql
-- Instead of aggregating raw data
SELECT bucket::date, avg_value
FROM tag_history_1day
WHERE tagid = 100;
```

**3. Increase work_mem:**
```sql
-- For session only
SET work_mem = '256MB';

-- Or in postgresql.conf
work_mem = 128MB
```

---

## High CPU Usage

### Diagnosis

```bash
# Linux - check CPU usage
top -u postgres

# Check which queries are using CPU
SELECT 
    pid,
    state,
    query_start,
    LEFT(query, 80)
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY query_start;
```

### Solutions

**1. Enable parallel queries:**
```conf
# postgresql.conf
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
```

**2. Optimize aggregations:**
```sql
-- Use continuous aggregates instead of raw aggregation
-- See docs/configuration/04-continuous-aggregates.md
```

**3. Limit concurrent queries:**
```python
# In Ignition, use connection pooling
# Limit Power Chart refresh rates
# Stagger dashboard loads
```

---

## High Memory Usage

### Diagnosis

```sql
-- Check memory usage per connection
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    LEFT(query, 60)
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- Check overall memory
SHOW shared_buffers;
SHOW work_mem;
```

### Solutions

**1. Reduce work_mem:**
```conf
work_mem = 64MB  # Down from higher value
```

**2. Reduce connections:**
```conf
max_connections = 150  # Down from 300
```

**3. Use connection pooling:**
```ini
# PgBouncer configuration
pool_mode = transaction
default_pool_size = 25
```

---

## I/O Bottlenecks

### Diagnosis

```bash
# Check I/O wait
iostat -x 5

# PostgreSQL I/O stats
SELECT * FROM pg_stat_io;
```

### Solutions

**1. Tune checkpoint settings:**
```conf
checkpoint_completion_target = 0.9
min_wal_size = 2GB
max_wal_size = 8GB
```

**2. Enable compression:**
```sql
-- Reduces I/O for reads
SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');
```

**3. Use faster storage:**
- Upgrade to SSD/NVMe
- Use RAID 10 for performance

---

## Connection Pool Exhaustion

### Diagnosis

```sql
-- Check connection count
SELECT 
    count(*) as active_connections,
    (SELECT setting::int FROM pg_settings WHERE name='max_connections') as max_connections
FROM pg_stat_activity;
```

### Solutions

**1. Increase max_connections:**
```conf
max_connections = 300
```

**2. Implement PgBouncer:**
```ini
[databases]
historian = host=localhost dbname=historian

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

---

## Best Practices

✅ Monitor query performance regularly  
✅ Use EXPLAIN ANALYZE for slow queries  
✅ Enable pg_stat_statements  
✅ Keep PostgreSQL updated  
✅ Use appropriate indexes  
✅ Implement compression  
✅ Use continuous aggregates  

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
