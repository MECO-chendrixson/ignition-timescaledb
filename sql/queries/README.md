# SQL Query Library

**Version:** 1.3.0  
**Last Updated:** December 8, 2025

## Overview

This directory contains pre-built SQL queries for common operations with Ignition TimescaleDB historian data.

---

## Available Query Files

### common_queries.sql

**Purpose:** Frequently used queries for tag history analysis and reporting

**Contents:**
- Time-based queries (last hour, specific ranges, date filters)
- Aggregation queries (hourly, daily, monthly statistics)
- Multi-tag queries (comparisons, pattern matching)
- Data quality analysis
- Performance monitoring
- Advanced analytics (moving averages, rate of change, percentiles)
- Tag metadata queries

**Total Queries:** 20 ready-to-use queries

**Usage:**
```bash
# Run all queries
psql -U postgres -d historian -f common_queries.sql

# Run specific query (copy from file)
psql -U postgres -d historian -c "SELECT ..."
```

---

## Query Categories

### Time-Based Queries (1-3)
- Last hour of data
- Specific date ranges
- Recent history with quality filtering

### Aggregation Queries (4-6)
- Hourly averages using time_bucket
- Daily statistics with standard deviation
- Monthly summaries for long-term trending

### Multi-Tag Queries (7-9)
- Multiple tag comparisons
- Tag group pattern matching
- Latest value per tag

### Data Quality Queries (10-12)
- Quality code distribution
- Missing data gap detection
- Bad quality sample identification

### Performance Queries (13-14)
- Sample rate analysis
- Tag activity monitoring

### Advanced Analytics (15-17)
- Moving averages
- Rate of change calculations
- Percentile analysis

### Tag Metadata Queries (18-20)
- Active tags listing
- History enablement verification
- Storage usage per tag

---

## Example Usage

### Get Last Hour of Temperature Data

```sql
SELECT 
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000)
  AND d.dataintegrity = 192
ORDER BY d.t_stamp;
```

### Calculate Hourly Averages

```sql
SELECT 
    time_bucket(3600000, d.t_stamp) as hour_bucket,
    to_timestamp(time_bucket(3600000, d.t_stamp) / 1000) as hour,
    AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value,
    COUNT(*) as sample_count
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = '[default]Production/Temperature'
  AND d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
  AND d.dataintegrity = 192
GROUP BY hour_bucket
ORDER BY hour_bucket DESC;
```

---

## Best Practices

✅ **Always filter by t_stamp** for efficient chunk exclusion  
✅ **Use time_bucket** instead of DATE_TRUNC for better performance  
✅ **Filter by dataintegrity = 192** for good quality data only  
✅ **Join with sqlth_te** to get human-readable tag paths  
✅ **Use COALESCE** to handle different data types  
✅ **Add LIMIT** clauses to large queries during testing  

---

## Integration with Ignition

### Named Queries

Create named queries in Ignition Designer:

1. Open Designer → Database → Named Queries
2. Create New Named Query
3. Copy SQL from this library
4. Add parameters (e.g., :tagPath, :startTime)
5. Save and test

**Example Named Query:**
```sql
SELECT 
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath = :tagPath
  AND d.t_stamp >= :startTime
  AND d.dataintegrity = 192
ORDER BY d.t_stamp;
```

### Scripting

Use in Ignition scripts:

```python
# Gateway or Vision script
tagPath = '[default]Production/Temperature'
startTime = system.date.addHours(system.date.now(), -24)

query = """
    SELECT 
        to_timestamp(t_stamp/1000) as timestamp,
        COALESCE(intvalue, floatvalue) as value
    FROM sqlth_1_data d
    JOIN sqlth_te t ON d.tagid = t.id
    WHERE t.tagpath = ?
      AND t_stamp >= ?
"""

results = system.db.runPrepQuery(
    query, 
    [tagPath, int(startTime.getTime())],
    'Historian'
)
```

---

## Performance Tips

### Use Continuous Aggregates

For historical queries, use continuous aggregates instead of raw data:

```sql
-- Instead of this (slow on large datasets):
SELECT 
    DATE(to_timestamp(t_stamp/1000)) as day,
    AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
WHERE tagid = 100
GROUP BY day;

-- Use this (much faster):
SELECT 
    bucket::date as day,
    avg_value
FROM tag_history_1day
WHERE tagid = 100;
```

### Index Usage

Ensure queries use appropriate indexes:

```sql
-- Good - uses index on (tagid, t_stamp)
EXPLAIN ANALYZE
SELECT * FROM sqlth_1_data 
WHERE tagid = 100 
  AND t_stamp >= 1234567890000;

-- Check for "Index Scan" or "Bitmap Index Scan" in output
```

---

## Related Documentation

- [Basic Query Examples](../../docs/examples/01-basic-queries.md)
- [Query Optimization](../../docs/optimization/02-query-optimization.md)
- [Continuous Aggregates](../../docs/examples/02-continuous-aggregates.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
