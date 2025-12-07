# Data Migration to TimescaleDB

**Last Updated:** December 7, 2025  
**Difficulty:** Intermediate to Advanced

## Overview

This guide covers migrating existing historical data from Ignition's tag historian or Transaction Group tables into TimescaleDB. This is essential for:

- **ML Training**: Backfill historical data for machine learning models
- **Platform Migration**: Moving from legacy historians to TimescaleDB
- **Data Consolidation**: Combining multiple data sources
- **System Upgrades**: Migrating during Ignition version upgrades

---

## Migration Scenarios

### Scenario 1: Tag Historian to TimescaleDB Hypertable

Migrate data from existing Ignition historian tables (partitioned or single table) to a TimescaleDB hypertable.

### Scenario 2: Transaction Group Tables to TimescaleDB

Migrate data from Transaction Group tables (custom schema) into TimescaleDB with continuous aggregates.

### Scenario 3: Cross-Database Migration

Migrate from MySQL/SQL Server historian to PostgreSQL/TimescaleDB.

---

## Pre-Migration Checklist

- [ ] Backup existing database
- [ ] Verify source data quality and completeness
- [ ] Calculate storage requirements
- [ ] Plan downtime window (if needed)
- [ ] Test migration on subset of data
- [ ] Verify TimescaleDB is configured and running
- [ ] Ensure sufficient disk space (2x source data size during migration)

---

## Migration Strategy 1: Same Database (PostgreSQL to TimescaleDB)

### Use Case
You're already using PostgreSQL for Ignition historian and want to convert to TimescaleDB hypertables.

### Step 1: Analyze Existing Data

```sql
-- Connect to existing historian database
\c historian

-- Check table structure
\d sqlth_1_data

-- Check data volume
SELECT 
    COUNT(*) as total_rows,
    MIN(t_stamp) as earliest_data,
    MAX(t_stamp) as latest_data,
    pg_size_pretty(pg_total_relation_size('sqlth_1_data')) as total_size
FROM sqlth_1_data;

-- Check tag distribution
SELECT 
    COUNT(DISTINCT tagid) as unique_tags,
    COUNT(*) as total_records,
    AVG(records_per_tag) as avg_records_per_tag
FROM (
    SELECT tagid, COUNT(*) as records_per_tag
    FROM sqlth_1_data
    GROUP BY tagid
) subquery;
```

### Step 2: Create Backup

```sql
-- Create backup table
CREATE TABLE sqlth_1_data_backup AS 
SELECT * FROM sqlth_1_data;

-- Verify backup
SELECT COUNT(*) FROM sqlth_1_data_backup;
```

### Step 3: Convert to Hypertable

```sql
-- If table already has data, use migrate_data
SELECT create_hypertable(
    'sqlth_1_data',
    't_stamp',
    chunk_time_interval => 86400000,  -- 24 hours
    migrate_data => TRUE
);

-- Enable compression
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);

-- Add compression policy
SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');

-- Add retention policy (optional)
SELECT add_retention_policy('sqlth_1_data', INTERVAL '10 years');
```

### Step 4: Verify Migration

```sql
-- Verify hypertable creation
SELECT * FROM timescaledb_information.hypertables 
WHERE hypertable_name = 'sqlth_1_data';

-- Verify data integrity
SELECT COUNT(*) FROM sqlth_1_data;
SELECT COUNT(*) FROM sqlth_1_data_backup;

-- Compare should match
SELECT 
    (SELECT COUNT(*) FROM sqlth_1_data) as current_count,
    (SELECT COUNT(*) FROM sqlth_1_data_backup) as backup_count,
    (SELECT COUNT(*) FROM sqlth_1_data) = (SELECT COUNT(*) FROM sqlth_1_data_backup) as counts_match;

-- Verify no data loss
SELECT 
    MIN(t_stamp) as min_timestamp,
    MAX(t_stamp) as max_timestamp,
    COUNT(DISTINCT tagid) as unique_tags
FROM sqlth_1_data;
```

---

## Migration Strategy 2: Transaction Group to TimescaleDB

### Use Case
You have custom Transaction Group tables with time-series data that you want to integrate into TimescaleDB.

### Example: Transaction Group Table Structure

```sql
-- Typical Transaction Group table
CREATE TABLE production_data (
    t_stamp TIMESTAMP NOT NULL,
    line_id INTEGER,
    temperature DOUBLE PRECISION,
    pressure DOUBLE PRECISION,
    flow_rate DOUBLE PRECISION,
    quality_code INTEGER
);
```

### Option A: Direct Hypertable Conversion

```sql
-- Convert existing table to hypertable
SELECT create_hypertable(
    'production_data',
    't_stamp',
    migrate_data => TRUE
);

-- Add compression
ALTER TABLE production_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'line_id'
);

SELECT add_compression_policy('production_data', INTERVAL '7 days');
```

### Option B: Migrate to Standard Historian Schema

If you want to integrate with Ignition's historian tables:

```sql
-- Create mapping function
CREATE OR REPLACE FUNCTION migrate_transaction_to_historian()
RETURNS void AS $$
DECLARE
    tag_record RECORD;
    new_tagid INTEGER;
BEGIN
    -- Create tag entries for each column
    FOR tag_record IN 
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'production_data' 
        AND column_name NOT IN ('t_stamp', 'line_id', 'quality_code')
    LOOP
        -- Insert tag metadata
        INSERT INTO sqlth_te (tagpath, scid, datatype, querymode, created)
        VALUES (
            '[default]Production/Line1/' || tag_record.column_name,
            1,  -- scan class id
            1,  -- float datatype
            0,  -- discrete query mode
            EXTRACT(EPOCH FROM NOW()) * 1000
        )
        RETURNING id INTO new_tagid;
        
        -- Migrate data for this tag
        INSERT INTO sqlth_1_data (tagid, floatvalue, dataintegrity, t_stamp)
        SELECT 
            new_tagid,
            CASE tag_record.column_name
                WHEN 'temperature' THEN temperature
                WHEN 'pressure' THEN pressure
                WHEN 'flow_rate' THEN flow_rate
            END,
            COALESCE(quality_code, 192),  -- Default to good quality
            EXTRACT(EPOCH FROM t_stamp) * 1000  -- Convert to Unix milliseconds
        FROM production_data
        WHERE CASE tag_record.column_name
            WHEN 'temperature' THEN temperature IS NOT NULL
            WHEN 'pressure' THEN pressure IS NOT NULL
            WHEN 'flow_rate' THEN flow_rate IS NOT NULL
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Execute migration
SELECT migrate_transaction_to_historian();
```

---

## Migration Strategy 3: Cross-Database Migration

### Use Case
Migrating from MySQL or SQL Server to PostgreSQL/TimescaleDB.

### Step 1: Export Source Data

**MySQL Export:**
```bash
mysqldump -u ignition -p \
  --databases historian \
  --tables sqlth_1_data sqlth_te sqlth_partitions \
  --tab=/tmp/mysql_export \
  --fields-terminated-by=',' \
  --fields-enclosed-by='"' \
  --lines-terminated-by='\n'
```

**SQL Server Export:**
```sql
-- Use BCP utility
bcp "SELECT * FROM historian.dbo.sqlth_1_data" queryout "C:\temp\sqlth_1_data.csv" -c -t"," -T -S localhost
```

### Step 2: Import to PostgreSQL

```sql
-- Create temporary staging table
CREATE TABLE sqlth_1_data_staging (
    tagid INTEGER,
    intvalue INTEGER,
    floatvalue DOUBLE PRECISION,
    stringvalue TEXT,
    datevalue TIMESTAMP,
    dataintegrity INTEGER,
    t_stamp BIGINT
);

-- Import CSV data
\COPY sqlth_1_data_staging FROM '/tmp/sqlth_1_data.csv' WITH CSV HEADER;

-- Verify import
SELECT COUNT(*) FROM sqlth_1_data_staging;
```

### Step 3: Transform and Load

```sql
-- Insert into target hypertable
INSERT INTO sqlth_1_data (
    tagid, intvalue, floatvalue, stringvalue, 
    datevalue, dataintegrity, t_stamp
)
SELECT 
    tagid,
    intvalue,
    floatvalue,
    stringvalue,
    datevalue,
    dataintegrity,
    t_stamp
FROM sqlth_1_data_staging
ON CONFLICT DO NOTHING;  -- Skip duplicates

-- Verify migration
SELECT 
    (SELECT COUNT(*) FROM sqlth_1_data_staging) as source_count,
    (SELECT COUNT(*) FROM sqlth_1_data) as target_count;

-- Drop staging table
DROP TABLE sqlth_1_data_staging;
```

---

## Migration Strategy 4: Incremental Migration (Zero Downtime)

### Use Case
Migrate historical data while Ignition continues to write new data.

### Step 1: Create Migration Table

```sql
CREATE TABLE migration_progress (
    migration_id SERIAL PRIMARY KEY,
    start_timestamp BIGINT,
    end_timestamp BIGINT,
    records_migrated INTEGER,
    migration_date TIMESTAMP DEFAULT NOW(),
    status TEXT
);
```

### Step 2: Batch Migration Script

```sql
CREATE OR REPLACE FUNCTION migrate_batch(
    batch_start BIGINT,
    batch_end BIGINT,
    batch_size INTEGER DEFAULT 100000
)
RETURNS INTEGER AS $$
DECLARE
    records_migrated INTEGER := 0;
    current_batch INTEGER;
BEGIN
    -- Migrate in chunks
    FOR current_batch IN 
        SELECT generate_series(batch_start, batch_end, batch_size)
    LOOP
        INSERT INTO sqlth_1_data_new (
            tagid, intvalue, floatvalue, stringvalue,
            datevalue, dataintegrity, t_stamp
        )
        SELECT 
            tagid, intvalue, floatvalue, stringvalue,
            datevalue, dataintegrity, t_stamp
        FROM sqlth_1_data_old
        WHERE t_stamp >= current_batch 
          AND t_stamp < current_batch + batch_size
        ON CONFLICT (tagid, t_stamp) DO NOTHING;
        
        GET DIAGNOSTICS records_migrated = ROW_COUNT;
        
        -- Log progress
        INSERT INTO migration_progress (
            start_timestamp, end_timestamp, 
            records_migrated, status
        ) VALUES (
            current_batch, current_batch + batch_size,
            records_migrated, 'completed'
        );
        
        -- Commit after each batch
        COMMIT;
        
        -- Brief pause to avoid overwhelming the system
        PERFORM pg_sleep(0.1);
    END LOOP;
    
    RETURN records_migrated;
END;
$$ LANGUAGE plpgsql;

-- Execute migration in batches
SELECT migrate_batch(
    (SELECT MIN(t_stamp) FROM sqlth_1_data_old),
    (SELECT MAX(t_stamp) FROM sqlth_1_data_old),
    100000  -- Batch size
);
```

### Step 3: Monitor Progress

```sql
-- Check migration progress
SELECT 
    COUNT(*) as total_batches,
    SUM(records_migrated) as total_records,
    MIN(migration_date) as started,
    MAX(migration_date) as last_update,
    (SELECT COUNT(*) FROM sqlth_1_data_new) as current_record_count
FROM migration_progress
WHERE status = 'completed';
```

---

## Data Quality and Validation

### Pre-Migration Data Quality Check

```sql
-- Check for NULL timestamps
SELECT COUNT(*) as null_timestamps
FROM sqlth_1_data
WHERE t_stamp IS NULL;

-- Check for duplicate records
SELECT tagid, t_stamp, COUNT(*)
FROM sqlth_1_data
GROUP BY tagid, t_stamp
HAVING COUNT(*) > 1;

-- Check for bad quality data
SELECT 
    dataintegrity,
    COUNT(*) as record_count,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage
FROM sqlth_1_data
GROUP BY dataintegrity
ORDER BY record_count DESC;

-- Check timestamp distribution
SELECT 
    DATE_TRUNC('month', to_timestamp(t_stamp/1000)) as month,
    COUNT(*) as record_count,
    COUNT(DISTINCT tagid) as unique_tags
FROM sqlth_1_data
GROUP BY month
ORDER BY month;
```

### Post-Migration Validation

```sql
-- Comprehensive validation query
WITH source_stats AS (
    SELECT 
        COUNT(*) as total_records,
        COUNT(DISTINCT tagid) as unique_tags,
        MIN(t_stamp) as earliest,
        MAX(t_stamp) as latest,
        AVG(COALESCE(intvalue, floatvalue)) as avg_value
    FROM sqlth_1_data_backup
),
target_stats AS (
    SELECT 
        COUNT(*) as total_records,
        COUNT(DISTINCT tagid) as unique_tags,
        MIN(t_stamp) as earliest,
        MAX(t_stamp) as latest,
        AVG(COALESCE(intvalue, floatvalue)) as avg_value
    FROM sqlth_1_data
)
SELECT 
    s.total_records as source_records,
    t.total_records as target_records,
    t.total_records - s.total_records as difference,
    s.unique_tags as source_tags,
    t.unique_tags as target_tags,
    s.earliest = t.earliest as earliest_match,
    s.latest = t.latest as latest_match,
    ABS(s.avg_value - t.avg_value) < 0.01 as avg_value_match
FROM source_stats s, target_stats t;
```

---

## Performance Optimization During Migration

### 1. Disable Triggers and Constraints Temporarily

```sql
-- Disable triggers during migration
ALTER TABLE sqlth_1_data DISABLE TRIGGER ALL;

-- Re-enable after migration
ALTER TABLE sqlth_1_data ENABLE TRIGGER ALL;
```

### 2. Adjust PostgreSQL Settings for Bulk Insert

```sql
-- Temporarily increase work_mem for migration session
SET work_mem = '256MB';
SET maintenance_work_mem = '1GB';

-- Disable WAL archiving during migration (if using)
SET wal_level = minimal;

-- Increase checkpoint segments
SET checkpoint_segments = 64;
```

### 3. Create Indexes After Migration

```sql
-- Drop indexes before migration
DROP INDEX IF EXISTS idx_sqlth_data_tstamp;
DROP INDEX IF EXISTS idx_sqlth_data_tagid_tstamp;

-- Perform migration

-- Recreate indexes after migration
CREATE INDEX idx_sqlth_data_tstamp_brin 
ON sqlth_1_data USING BRIN (t_stamp);

CREATE INDEX idx_sqlth_data_tagid_tstamp 
ON sqlth_1_data (tagid, t_stamp DESC);

-- Analyze table
ANALYZE sqlth_1_data;
```

---

## ML Training Data Preparation

### Create ML-Optimized Views

```sql
-- Create view for ML feature extraction
CREATE OR REPLACE VIEW ml_training_data AS
SELECT 
    t.tagpath,
    d.t_stamp,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value,
    d.dataintegrity,
    -- Time-based features
    EXTRACT(HOUR FROM to_timestamp(d.t_stamp / 1000)) as hour_of_day,
    EXTRACT(DOW FROM to_timestamp(d.t_stamp / 1000)) as day_of_week,
    EXTRACT(MONTH FROM to_timestamp(d.t_stamp / 1000)) as month,
    -- Lag features (previous values)
    LAG(COALESCE(d.intvalue, d.floatvalue), 1) OVER (
        PARTITION BY d.tagid ORDER BY d.t_stamp
    ) as prev_value_1,
    LAG(COALESCE(d.intvalue, d.floatvalue), 2) OVER (
        PARTITION BY d.tagid ORDER BY d.t_stamp
    ) as prev_value_2
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE t.retired IS NULL
  AND d.dataintegrity = 192;  -- Good quality only
```

### Export for ML Training

```sql
-- Export to CSV for Python ML libraries
\COPY (
    SELECT * FROM ml_training_data 
    WHERE timestamp >= NOW() - INTERVAL '1 year'
) TO '/tmp/ml_training_data.csv' WITH CSV HEADER;
```

### Create Time-Series Features with Continuous Aggregates

```sql
-- Statistical features for ML
CREATE MATERIALIZED VIEW ml_features_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', t_stamp) AS bucket,
    tagid,
    AVG(COALESCE(intvalue, floatvalue)) AS mean,
    STDDEV(COALESCE(intvalue, floatvalue)) AS stddev,
    MIN(COALESCE(intvalue, floatvalue)) AS min_val,
    MAX(COALESCE(intvalue, floatvalue)) AS max_val,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS q1,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS q3,
    COUNT(*) AS sample_count
FROM sqlth_1_data
WHERE dataintegrity = 192
GROUP BY bucket, tagid;

-- Add refresh policy
SELECT add_continuous_aggregate_policy('ml_features_hourly',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');
```

---

## Troubleshooting Migration Issues

### Issue: Out of Memory During Migration

**Solution:**
```sql
-- Use smaller batch sizes
SELECT migrate_batch(start_ts, end_ts, 10000);  -- Reduce from 100000

-- Or increase PostgreSQL memory settings temporarily
SET work_mem = '512MB';
```

### Issue: Duplicate Key Violations

**Solution:**
```sql
-- Use ON CONFLICT to skip duplicates
INSERT INTO sqlth_1_data (...)
SELECT ... FROM source_table
ON CONFLICT (tagid, t_stamp) DO NOTHING;

-- Or update on conflict
ON CONFLICT (tagid, t_stamp) DO UPDATE
SET floatvalue = EXCLUDED.floatvalue;
```

### Issue: Slow Migration Performance

**Solution:**
```sql
-- Disable autovacuum during migration
ALTER TABLE sqlth_1_data SET (autovacuum_enabled = false);

-- Re-enable after migration
ALTER TABLE sqlth_1_data SET (autovacuum_enabled = true);

-- Run manual vacuum
VACUUM ANALYZE sqlth_1_data;
```

---

## Post-Migration Steps

### 1. Update Statistics

```sql
ANALYZE sqlth_1_data;
ANALYZE sqlth_te;
ANALYZE sqlth_partitions;
```

### 2. Verify Compression

```sql
-- Check compression status
SELECT * FROM timescaledb_information.compressed_chunk_stats;

-- Manually compress if needed
SELECT compress_chunk(i, if_not_compressed => true)
FROM show_chunks('sqlth_1_data', older_than => INTERVAL '7 days') i;
```

### 3. Test Queries

```sql
-- Test query performance
EXPLAIN ANALYZE
SELECT tagid, AVG(COALESCE(intvalue, floatvalue))
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days') * 1000)
GROUP BY tagid;
```

### 4. Update Ignition Configuration

After migration, verify:
- [ ] Tag history queries work correctly
- [ ] Power Chart displays historical data
- [ ] Easy Chart shows migrated data
- [ ] Named queries return expected results
- [ ] Continuous aggregates are populating

---

## Rollback Plan

If migration fails:

```sql
-- Restore from backup
DROP TABLE IF EXISTS sqlth_1_data;
ALTER TABLE sqlth_1_data_backup RENAME TO sqlth_1_data;

-- Recreate indexes
CREATE INDEX idx_sqlth_data_tstamp ON sqlth_1_data(t_stamp);
CREATE INDEX idx_sqlth_data_tagid ON sqlth_1_data(tagid);

-- Restart Ignition historian
```

---

## Best Practices

✅ **Always backup before migration**  
✅ **Test on subset of data first**  
✅ **Monitor disk space during migration**  
✅ **Use batch processing for large datasets**  
✅ **Validate data integrity after migration**  
✅ **Document tag mappings and transformations**  
✅ **Plan for minimal downtime window**  
✅ **Have rollback procedure ready**  

---

## Next Steps

- [ML Integration Examples](04-ml-integration.md)
- [Performance Tuning](../optimization/01-performance-tuning.md)
- [Continuous Aggregates](../configuration/04-continuous-aggregates.md)

**Last Updated:** December 7, 2025
