# Continuous Aggregate Examples

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate  
**Prerequisites:** Continuous aggregates configured

## Overview

Real-world examples of using continuous aggregates for efficient multi-resolution queries.

## Query Performance Comparison

**Without Continuous Aggregates (Raw Data):**
```sql
-- Query takes 45 seconds for 1 year of data
SELECT 
    DATE_TRUNC('hour', to_timestamp(t_stamp/1000)) as hour,
    AVG(COALESCE(intvalue, floatvalue)) as avg_value
FROM sqlth_1_data
WHERE tagid = 100
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 year') * 1000)
GROUP BY hour;
-- Execution time: 45 seconds
-- Scans: 31 million rows
```

**With Continuous Aggregates:**
```sql
-- Same query takes 0.4 seconds
SELECT 
    bucket as hour,
    avg_value
FROM tag_history_1hour
WHERE tagid = 100
  AND bucket >= NOW() - INTERVAL '1 year';
-- Execution time: 0.4 seconds  
-- Scans: 8,760 rows (100x faster!)
```

## Using Aggregates in Queries

### Hourly Trends

```sql
SELECT 
    bucket,
    tagpath,
    avg_value,
    max_value,
    min_value
FROM tag_history_1hour_named
WHERE tagpath = '[default]Production/Temperature'
  AND bucket >= NOW() - INTERVAL '30 days'
ORDER BY bucket DESC;
```

### Daily Reports

```sql
SELECT 
    bucket::date as day,
    AVG(avg_value) as daily_avg,
    MAX(max_value) as daily_max,
    MIN(min_value) as daily_min
FROM tag_history_1hour
WHERE tagid IN (100, 101, 102)
  AND bucket >= NOW() - INTERVAL '90 days'
GROUP BY day
ORDER BY day DESC;
```

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
