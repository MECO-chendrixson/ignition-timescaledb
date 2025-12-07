# Data Migration Quick Reference

**Last Updated:** December 7, 2025

## Migration Decision Matrix

| Source | Target | Method | Complexity | Downtime |
|--------|--------|--------|------------|----------|
| PostgreSQL Historian → TimescaleDB (same DB) | Same hypertable | `migrate_data => TRUE` | Low | None |
| Partitioned tables → Single hypertable | Merge partitions | SQL INSERT | Medium | Minimal |
| Transaction Groups → Historian schema | Transform & load | Custom SQL | Medium | None |
| MySQL/MSSQL → PostgreSQL/TimescaleDB | Export/Import | ETL pipeline | High | Planned |
| Active historian → TimescaleDB | Incremental batches | Python script | Medium | None |

---

## Quick Migration Commands

### Simple In-Place Conversion

```sql
-- Already on PostgreSQL, just add TimescaleDB
SELECT create_hypertable('sqlth_1_data', 't_stamp', 
    migrate_data => TRUE);
```

### Merge Partitioned Tables

```sql
-- Create unified hypertable
CREATE TABLE sqlth_unified AS 
SELECT * FROM sqlth_1_data 
WHERE 1=0;  -- Structure only

-- Insert from all partitions
INSERT INTO sqlth_unified
SELECT * FROM sqlt_data_1_2023_01
UNION ALL
SELECT * FROM sqlt_data_1_2023_02
UNION ALL
-- ... continue for all partitions
SELECT * FROM sqlt_data_1_2024_12;

-- Convert to hypertable
SELECT create_hypertable('sqlth_unified', 't_stamp');
```

### Transaction Group to Historian Format

```sql
-- Map custom columns to historian schema
INSERT INTO sqlth_1_data (tagid, floatvalue, dataintegrity, t_stamp)
SELECT 
    (SELECT id FROM sqlth_te WHERE tagpath = '[default]Prod/Temp' LIMIT 1),
    temperature,
    192,  -- Good quality
    EXTRACT(EPOCH FROM timestamp) * 1000
FROM transaction_group_table;
```

---

## Backfill Strategy for ML Training

### Option 1: Migrate All Historical Data

**Pros:** Complete dataset, no data gaps  
**Cons:** Time-consuming, storage-intensive  

```python
# Use migration script
python3 scripts/migration/migrate_historian_data.py \
  --host localhost \
  --database historian \
  --user ignition \
  --password your_password
```

### Option 2: Migrate Recent Data Only

**Pros:** Faster, less storage  
**Cons:** Limited historical context  

```sql
-- Migrate last 2 years only
INSERT INTO sqlth_1_data_timescale
SELECT * FROM sqlth_1_data
WHERE t_stamp >= EXTRACT(EPOCH FROM NOW() - INTERVAL '2 years') * 1000;
```

### Option 3: Migrate Sampled Data

**Pros:** Very fast, minimal storage  
**Cons:** Reduced data fidelity  

```sql
-- Migrate every 10th record
INSERT INTO sqlth_1_data_timescale
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY tagid ORDER BY t_stamp) as rn
    FROM sqlth_1_data
) subquery
WHERE rn % 10 = 0;
```

### Option 4: Migrate Aggregated Data Only

**Pros:** Smallest storage, pre-computed features  
**Cons:** Loss of raw data granularity  

```sql
-- Create hourly aggregates during migration
INSERT INTO tag_history_1hour
SELECT
    time_bucket('1 hour', t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS avg_value,
    MAX(COALESCE(intvalue, floatvalue)) AS max_value,
    MIN(COALESCE(intvalue, floatvalue)) AS min_value,
    STDDEV(COALESCE(intvalue, floatvalue)) AS stddev_value
FROM sqlth_1_data
GROUP BY bucket, tagid;
```

---

## ML Training Data Queries

### Extract Training Dataset

```sql
-- Get 1 year of data with features
SELECT 
    to_timestamp(d.t_stamp / 1000) as timestamp,
    t.tagpath,
    COALESCE(d.intvalue, d.floatvalue) as value,
    
    -- Derived features
    EXTRACT(HOUR FROM to_timestamp(d.t_stamp / 1000)) as hour,
    EXTRACT(DOW FROM to_timestamp(d.t_stamp / 1000)) as day_of_week,
    
    -- Lag features
    LAG(COALESCE(d.intvalue, d.floatvalue), 1) OVER w as prev_1,
    LAG(COALESCE(d.intvalue, d.floatvalue), 12) OVER w as prev_12,  -- 12 hours ago if hourly
    
    -- Rolling stats
    AVG(COALESCE(d.intvalue, d.floatvalue)) OVER (
        PARTITION BY d.tagid ORDER BY d.t_stamp 
        ROWS BETWEEN 24 PRECEDING AND CURRENT ROW
    ) as rolling_avg_24h

FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.tagpath IN (
    '[default]Production/Temperature',
    '[default]Production/Pressure',
    '[default]Production/FlowRate'
)
AND d.t_stamp >= EXTRACT(EPOCH FROM NOW() - INTERVAL '1 year') * 1000
AND d.dataintegrity = 192
WINDOW w AS (PARTITION BY d.tagid ORDER BY d.t_stamp);
```

### Export for Python ML Libraries

```python
import pandas as pd
from sqlalchemy import create_engine

# Connect
engine = create_engine('postgresql://ignition:password@localhost:5432/historian')

# Query
query = """
SELECT * FROM ml_features
WHERE timestamp >= NOW() - INTERVAL '1 year'
"""

# Load into DataFrame
df = pd.read_sql(query, engine, parse_dates=['timestamp'])

# Export to CSV
df.to_csv('ml_training_data.csv', index=False)

# Or Parquet for better performance
df.to_parquet('ml_training_data.parquet')
```

---

## Performance Tips

### Speed Up Migration

```sql
-- Disable autovacuum temporarily
ALTER TABLE sqlth_1_data SET (autovacuum_enabled = false);

-- Drop indexes before migration
DROP INDEX idx_sqlth_data_tagid_tstamp;

-- Perform migration

-- Recreate indexes
CREATE INDEX idx_sqlth_data_tagid_tstamp 
ON sqlth_1_data (tagid, t_stamp DESC);

-- Re-enable autovacuum
ALTER TABLE sqlth_1_data SET (autovacuum_enabled = true);
VACUUM ANALYZE sqlth_1_data;
```

### Parallel Migration

```sql
-- Create function for parallel workers
CREATE OR REPLACE FUNCTION migrate_tag_range(
    start_tagid INTEGER,
    end_tagid INTEGER
)
RETURNS INTEGER AS $$
BEGIN
    INSERT INTO sqlth_1_data_new
    SELECT * FROM sqlth_1_data_old
    WHERE tagid >= start_tagid AND tagid < end_tagid;
    
    RETURN (SELECT COUNT(*) FROM sqlth_1_data_new 
            WHERE tagid >= start_tagid AND tagid < end_tagid);
END;
$$ LANGUAGE plpgsql;

-- Run in parallel (from different sessions)
-- Session 1: SELECT migrate_tag_range(1, 100);
-- Session 2: SELECT migrate_tag_range(100, 200);
-- Session 3: SELECT migrate_tag_range(200, 300);
```

---

## Validation Queries

### Data Integrity Check

```sql
-- Compare source and target
WITH source_check AS (
    SELECT 
        COUNT(*) as records,
        COUNT(DISTINCT tagid) as tags,
        MIN(t_stamp) as min_ts,
        MAX(t_stamp) as max_ts
    FROM sqlth_1_data_backup
),
target_check AS (
    SELECT 
        COUNT(*) as records,
        COUNT(DISTINCT tagid) as tags,
        MIN(t_stamp) as min_ts,
        MAX(t_stamp) as max_ts
    FROM sqlth_1_data
)
SELECT 
    s.records = t.records as records_match,
    s.tags = t.tags as tags_match,
    s.min_ts = t.min_ts as min_timestamp_match,
    s.max_ts = t.max_ts as max_timestamp_match,
    s.records as source_records,
    t.records as target_records
FROM source_check s, target_check t;
```

### Find Missing Data

```sql
-- Find timestamps in source but not in target
SELECT s.tagid, s.t_stamp
FROM sqlth_1_data_backup s
LEFT JOIN sqlth_1_data t ON s.tagid = t.tagid AND s.t_stamp = t.t_stamp
WHERE t.tagid IS NULL
LIMIT 100;
```

---

## Rollback Procedures

### Restore from Backup

```sql
-- Drop current table
DROP TABLE sqlth_1_data;

-- Restore from backup
ALTER TABLE sqlth_1_data_backup_20251207_102600 
RENAME TO sqlth_1_data;

-- Recreate indexes
CREATE INDEX idx_sqlth_data_tstamp ON sqlth_1_data(t_stamp);
CREATE INDEX idx_sqlth_data_tagid ON sqlth_1_data(tagid);

-- Analyze
ANALYZE sqlth_1_data;
```

---

## See Also

- [Data Migration Guide](../../docs/examples/05-data-migration.md)
- [ML Integration Guide](../../docs/examples/04-ml-integration.md)
- [Performance Tuning](../../docs/optimization/01-performance-tuning.md)

**Last Updated:** December 7, 2025
