# 04 diagnostic tools

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate to Advanced  

## Overview

Troubleshooting guide for 04 diagnostic tools in TimescaleDB with Ignition.

## Common Issues

### Slow Query Performance

**Symptoms:**
- Queries taking >5 seconds
- High CPU usage
- Timeouts in Ignition

**Diagnosis:**
```sql
-- Check query performance
EXPLAIN ANALYZE
SELECT * FROM sqlth_1_data 
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000);
```

**Solutions:**
✅ Add indexes on t_stamp and tagid
✅ Enable compression for old data
✅ Use continuous aggregates
✅ Increase work_mem in PostgreSQL

### Missing Data

**Check for gaps:**
```sql
SELECT 
    time_bucket(3600000, t_stamp) as hour,
    COUNT(*) as samples
FROM sqlth_1_data
WHERE tagid = 100
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
GROUP BY hour
HAVING COUNT(*) < 3600;  -- Less than expected samples
```

### Data Quality Issues

**Check quality distribution:**
```sql
SELECT 
    dataintegrity,
    COUNT(*) as count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER() * 100, 2) as percentage
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY dataintegrity
ORDER BY count DESC;
```

## Diagnostic Queries

### Check Chunk Health
```sql
SELECT 
    chunk_name,
    is_compressed,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 10;
```

### Check Active Connections
```sql
SELECT 
    datname,
    usename,
    state,
    COUNT(*)
FROM pg_stat_activity
WHERE datname = 'historian'
GROUP BY datname, usename, state;
```

### Check Table Bloat
```sql
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE tablename LIKE 'sqlth%'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## Monitoring Tools

### pgAdmin
- Query Tool for interactive queries
- Server monitoring dashboard
- Query history and explain plans

### psql Commands
```bash
# Check database size
psql -U postgres -d historian -c "SELECT pg_size_pretty(pg_database_size('historian'));"

# List tables
psql -U postgres -d historian -c "\dt sqlth*"

# Check compression status
psql -U postgres -d historian -c "SELECT * FROM timescaledb_information.compressed_chunk_stats;"
```

## Performance Monitoring

### Track Query Performance
```sql
-- Enable query logging
ALTER DATABASE historian SET log_min_duration_statement = 1000; -- Log queries >1s

-- View slow queries
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;
```

## Next Steps

- [Common Issues](01-common-issues.md)
- [Performance Tuning](../optimization/01-performance-tuning.md)
- [Query Optimization](../optimization/02-query-optimization.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
