# Basic Query Examples

**Last Updated:** December 8, 2025  
**Difficulty:** Beginner  
**Prerequisites:** 
- Hypertable configured
- Data being collected
- Basic SQL knowledge

## Overview

This guide provides common SQL query patterns for querying Ignition historian data stored in TimescaleDB. These examples cover the most frequent use cases for retrieving and analyzing tag history.

---

## Time-Based Queries

### Last Hour of Data

```sql
-- Get all data from the last hour
SELECT 
    t.tagpath,
    d.t_stamp,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value,
    d.dataintegrity
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
ORDER BY d.t_stamp DESC;
```

### Specific Time Range

```sql
-- Get data for a specific date range
SELECT 
    t.tagpath,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM '2025-12-01 00:00:00'::timestamp) * 1000)
  AND d.t_stamp < (EXTRACT(EPOCH FROM '2025-12-02 00:00:00'::timestamp) * 1000)
  AND t.tagpath = '[default]Production/Temperature'
ORDER BY d.t_stamp;
```

### Last 7 Days

```sql
-- Weekly data summary
SELECT 
    DATE(to_timestamp(d.t_stamp / 1000)) as day,
    t.tagpath,
    COUNT(*) as sample_count,
    AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value,
    MIN(COALESCE(d.intvalue, d.floatvalue)) as min_value,
    MAX(COALESCE(d.intvalue, d.floatvalue)) as max_value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
  AND t.tagpath = '[default]Production/Temperature'
GROUP BY day, t.tagpath
ORDER BY day DESC;
```

---

## Tag Filtering

### Single Tag Query

```sql
-- Get data for one specific tag
SELECT 
    to_timestamp(t_stamp / 1000) as timestamp,
    COALESCE(intvalue, floatvalue) as value,
    dataintegrity as quality
FROM sqlth_1_data
WHERE tagid = (
    SELECT id FROM sqlth_te 
    WHERE tagpath = '[default]Production/Temperature'
)
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
ORDER BY t_stamp DESC;
```

### Multiple Tags

```sql
-- Query multiple tags at once
SELECT 
    t.tagpath,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath IN (
    '[default]Production/Temperature',
    '[default]Production/Pressure',
    '[default]Production/FlowRate'
)
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
ORDER BY d.t_stamp DESC, t.tagpath;
```

### Tag Path Pattern Matching

```sql
-- Get all tags matching a pattern
SELECT 
    t.tagpath,
    COUNT(*) as sample_count,
    AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath LIKE '[default]Production/%'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours') * 1000)
  AND d.dataintegrity = 192
GROUP BY t.tagpath
ORDER BY t.tagpath;
```

---

## Aggregations with time_bucket

### Hourly Averages

```sql
-- Calculate hourly averages using TimescaleDB's time_bucket
SELECT 
    time_bucket(3600000, t_stamp) as hour_bucket,
    to_timestamp(time_bucket(3600000, t_stamp) / 1000) as hour,
    t.tagpath,
    AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value,
    COUNT(*) as sample_count
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
  AND d.dataintegrity = 192
GROUP BY hour_bucket, t.tagpath
ORDER BY hour_bucket DESC;
```

### Daily Statistics

```sql
-- Daily min/max/avg with standard deviation
SELECT 
    time_bucket(86400000, t_stamp) as day_bucket,
    DATE(to_timestamp(time_bucket(86400000, t_stamp) / 1000)) as day,
    COUNT(*) as samples,
    AVG(COALESCE(intvalue, floatvalue)) as avg_value,
    STDDEV(COALESCE(intvalue, floatvalue)) as std_dev,
    MIN(COALESCE(intvalue, floatvalue)) as min_value,
    MAX(COALESCE(intvalue, floatvalue)) as max_value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
  AND dataintegrity = 192
GROUP BY day_bucket
ORDER BY day_bucket DESC;
```

---

## Latest Values

### Most Recent Value Per Tag

```sql
-- Get the latest value for each tag
SELECT DISTINCT ON (tagid)
    t.tagpath,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value,
    d.dataintegrity
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath LIKE '[default]Production/%'
ORDER BY tagid, t_stamp DESC;
```

---

## Performance Tips

✅ **Always filter by t_stamp** - Enables chunk exclusion  
✅ **Use continuous aggregates** for historical queries  
✅ **Filter by dataintegrity = 192** for good quality only  
✅ **Use time_bucket** instead of DATE_TRUNC for better performance  
✅ **Create indexes** on frequently queried tagids  

---

## Next Steps

- [Continuous Aggregate Examples](02-continuous-aggregates.md)
- [Scripting Examples](03-scripting-examples.md)
- [Query Optimization](../optimization/02-query-optimization.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
