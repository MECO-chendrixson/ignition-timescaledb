# 04 best practices

**Last Updated:** December 8, 2025  
**Difficulty:** Reference  

## Overview

Comprehensive reference for 04 best practices.

## Ignition Historian Tables

### sqlth_1_data (Main Data Table)

| Column | Type | Description |
|--------|------|-------------|
| tagid | INTEGER | Foreign key to sqlth_te |
| intvalue | INTEGER | Integer tag values |
| floatvalue | DOUBLE PRECISION | Float tag values |
| stringvalue | TEXT | String tag values |
| datevalue | TIMESTAMP | Date tag values |
| dataintegrity | INTEGER | Quality code (192 = good) |
| t_stamp | BIGINT | Unix timestamp in milliseconds |

### sqlth_te (Tag Metadata)

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL | Tag ID (primary key) |
| tagpath | VARCHAR | Full tag path |
| datatype | INTEGER | Data type (1=int, 2=float, etc) |
| created | BIGINT | Creation timestamp |
| retired | BIGINT | Retirement timestamp (NULL if active) |

## TimescaleDB Functions

### time_bucket()
```sql
SELECT time_bucket('1 hour', t_stamp) as hour, 
       AVG(floatvalue) 
FROM sqlth_1_data 
GROUP BY hour;
```

### compress_chunk()
```sql
SELECT compress_chunk(chunk_name) 
FROM show_chunks('sqlth_1_data');
```

## Ignition Scripting Functions

### system.tag.queryTagHistory()
```python
# Query tag history
results = system.tag.queryTagHistory(
    paths=['[default]Production/Temperature'],
    startDate=system.date.addHours(system.date.now(), -24),
    endDate=system.date.now(),
    returnSize=1000,
    aggregationMode='Average',
    returnFormat='Wide'
)
```

## Best Practices

✅ **Use time_bucket for aggregations**
✅ **Filter by t_stamp for performance**
✅ **Enable compression after 7 days**
✅ **Use continuous aggregates for historical queries**
✅ **Set appropriate retention policies**
✅ **Regular maintenance (VACUUM, ANALYZE)**

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
