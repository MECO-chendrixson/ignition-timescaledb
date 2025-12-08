# Diagnostic Tools and Queries

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate

## Overview

Collection of diagnostic queries and tools for monitoring TimescaleDB historian health and performance.

---

## PostgreSQL Diagnostic Queries

### Database Overview

```sql
-- Database size and statistics
SELECT 
    datname as database,
    pg_size_pretty(pg_database_size(datname)) as size,
    numbackends as connections,
    xact_commit as commits,
    xact_rollback as rollbacks,
    blks_read as disk_reads,
    blks_hit as cache_hits,
    ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname IN ('historian', 'alarmlog', 'auditlog');
```

### Table Statistics

```sql
-- Table sizes and activity
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    last_vacuum,
    last_autovacuum,
    last_analyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Index Health

```sql
-- Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

### Active Connections

```sql
-- Current connections by state
SELECT 
    datname,
    usename,
    application_name,
    state,
    COUNT(*) as count
FROM pg_stat_activity
GROUP BY datname, usename, application_name, state
ORDER BY count DESC;
```

---

## TimescaleDB Diagnostics

### Hypertable Health

```sql
-- Hypertable overview
SELECT 
    hypertable_schema,
    hypertable_name,
    num_dimensions,
    num_chunks,
    compression_enabled,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.hypertables;
```

### Chunk Status

```sql
-- Detailed chunk analysis
SELECT 
    chunk_name,
    hypertable_name,
    is_compressed,
    range_start,
    range_end,
    to_timestamp(range_start/1000) as start_date,
    to_timestamp(range_end/1000) as end_date,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 20;
```

### Compression Status

```sql
-- Compression effectiveness
SELECT 
    hypertable_name,
    chunk_name,
    pg_size_pretty(before_compression_total_bytes) as before_size,
    pg_size_pretty(after_compression_total_bytes) as after_size,
    ROUND(
        before_compression_total_bytes::numeric / 
        NULLIF(after_compression_total_bytes, 0),
        2
    ) as compression_ratio
FROM timescaledb_information.compressed_chunk_stats
ORDER BY before_compression_total_bytes DESC
LIMIT 20;
```

### Background Jobs

```sql
-- Job execution status
SELECT 
    job_id,
    application_name,
    schedule_interval,
    last_run_started_at,
    last_run_status,
    last_run_duration,
    next_start,
    total_runs,
    total_successes,
    total_failures
FROM timescaledb_information.job_stats
ORDER BY job_id;
```

---

## Performance Monitoring

### Cache Hit Ratio

```sql
-- Should be >99%
SELECT 
    'Cache Hit Ratio' as metric,
    ROUND(
        100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0),
        2
    ) as value,
    '%' as unit
FROM pg_statio_user_tables;
```

### Slow Queries (requires pg_stat_statements)

```sql
-- Top 10 slowest queries
SELECT 
    LEFT(query, 80) as query_preview,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_ms,
    ROUND(max_exec_time::numeric, 2) as max_ms,
    ROUND(total_exec_time::numeric, 2) as total_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
  AND query NOT LIKE '%COMMIT%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

---

## System Monitoring Tools

### Command Line Tools

**psql:**
```bash
# Interactive monitoring
psql -U postgres -d historian

# Run specific query
psql -U postgres -d historian -c "SELECT COUNT(*) FROM sqlth_1_data;"

# Export results
psql -U postgres -d historian -c "SELECT * FROM tag_history_1hour" -o report.txt
```

**pg_top:**
```bash
# Real-time query monitoring
pg_top -U postgres -d historian
```

**pgbadger (log analysis):**
```bash
# Analyze PostgreSQL logs
pgbadger /var/log/postgresql/postgresql-15-main.log -o report.html
```

---

## Diagnostic Functions

### Create Health Check Function

```sql
CREATE OR REPLACE FUNCTION check_database_health()
RETURNS TABLE (
    check_name text,
    status text,
    details text
) AS $$
BEGIN
    -- Check 1: Data freshness
    RETURN QUERY
    SELECT 
        'Data Freshness'::text,
        CASE 
            WHEN MAX(to_timestamp(t_stamp/1000)) > NOW() - INTERVAL '5 minutes' 
                THEN 'OK'
            ELSE 'STALE'
        END,
        'Last data: ' || MAX(to_timestamp(t_stamp/1000))::text
    FROM sqlth_1_data;
    
    -- Check 2: Compression
    RETURN QUERY
    SELECT 
        'Compression Ratio'::text,
        CASE 
            WHEN AVG(before_compression_total_bytes::numeric / after_compression_total_bytes) > 10 
                THEN 'GOOD'
            WHEN AVG(before_compression_total_bytes::numeric / after_compression_total_bytes) > 5 
                THEN 'FAIR'
            ELSE 'POOR'
        END,
        'Avg ratio: ' || ROUND(AVG(before_compression_total_bytes::numeric / after_compression_total_bytes), 2)::text
    FROM timescaledb_information.compressed_chunk_stats;
    
    -- Check 3: Cache hit ratio
    RETURN QUERY
    SELECT 
        'Cache Hit Ratio'::text,
        CASE 
            WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) > 99 
                THEN 'EXCELLENT'
            WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) > 95 
                THEN 'GOOD'
            ELSE 'POOR'
        END,
        ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2)::text || '%'
    FROM pg_stat_database
    WHERE datname = 'historian';
END;
$$ LANGUAGE plpgsql;

-- Run health check
SELECT * FROM check_database_health();
```

---

## Automated Monitoring Script

See `scripts/maintenance/monitor_historian.sh` for comprehensive automated monitoring.

**Usage:**
```bash
# Run monitoring report
./scripts/maintenance/monitor_historian.sh

# Schedule hourly
0 * * * * /path/to/monitor_historian.sh >> /var/log/timescaledb_monitor.log 2>&1
```

---

## Third-Party Tools

### pgAdmin 4
- Visual query tool
- Server monitoring dashboard
- Query explain visualization

### PgHero
- Query performance insights
- Index recommendations
- Space usage analysis

### Grafana + Prometheus
- Real-time metrics dashboards
- Historical trending
- Alerting

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
