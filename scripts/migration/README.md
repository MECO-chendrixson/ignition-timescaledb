# Migration Scripts

This directory contains scripts for migrating historical data to TimescaleDB.

## Available Scripts

### migrate_historian_data.py

Migrate Ignition Tag Historian data to TimescaleDB hypertables.

**Features:**
- Batch processing for large datasets
- Automatic backup creation
- Progress tracking and logging
- Data validation
- Support for partitioned and single-partition tables

**Usage:**

```bash
# Basic migration
python3 migrate_historian_data.py \
  --host localhost \
  --database historian \
  --user ignition \
  --password your_password

# With custom batch size
python3 migrate_historian_data.py \
  --host 192.168.1.100 \
  --database historian \
  --user ignition \
  --password your_password \
  --batch-size 50000

# Validate only (no migration)
python3 migrate_historian_data.py \
  --host localhost \
  --database historian \
  --user ignition \
  --password your_password \
  --validate-only

# Skip backup (faster, but risky)
python3 migrate_historian_data.py \
  --host localhost \
  --database historian \
  --user ignition \
  --password your_password \
  --no-backup
```

**Parameters:**
- `--host`: Database server hostname (default: localhost)
- `--port`: Database port (default: 5432)
- `--database`: Database name (default: historian)
- `--user`: Database user (default: ignition)
- `--password`: Database password (required)
- `--source-table`: Source table name (default: sqlth_1_data)
- `--target-table`: Target table name (default: sqlth_1_data)
- `--batch-size`: Records per batch (default: 100000)
- `--no-backup`: Skip backup creation
- `--validate-only`: Only validate, don't migrate

**Requirements:**
```bash
pip install psycopg2-binary
```

---

## Migration Workflow

### 1. Pre-Migration Checklist

- [ ] Backup existing database
- [ ] Test script on small dataset
- [ ] Verify disk space (2x current size)
- [ ] Schedule during maintenance window
- [ ] Notify users of potential downtime

### 2. Run Migration

```bash
# Test with validate-only first
python3 migrate_historian_data.py \
  --host localhost \
  --database historian \
  --user ignition \
  --password your_password \
  --validate-only

# If validation passes, run actual migration
python3 migrate_historian_data.py \
  --host localhost \
  --database historian \
  --user ignition \
  --password your_password
```

### 3. Post-Migration Steps

```sql
-- Verify hypertable
SELECT * FROM timescaledb_information.hypertables 
WHERE hypertable_name = 'sqlth_1_data';

-- Check data integrity
SELECT COUNT(*) FROM sqlth_1_data;

-- Update statistics
ANALYZE sqlth_1_data;

-- Enable compression
SELECT compress_chunk(i, if_not_compressed => true)
FROM show_chunks('sqlth_1_data', older_than => INTERVAL '7 days') i;
```

---

## Troubleshooting

### Migration Fails with Memory Error

Reduce batch size:
```bash
python3 migrate_historian_data.py ... --batch-size 10000
```

### Migration Very Slow

Check:
1. Network latency (if cross-server)
2. Disk I/O (use `iostat -x 1`)
3. PostgreSQL configuration (work_mem, maintenance_work_mem)

### Validation Shows Mismatches

Review migration.log for details:
```bash
tail -f migration.log
```

---

## Advanced Usage

### Migrate Specific Time Range

Modify the script or use SQL directly:

```sql
-- Create migration function
CREATE OR REPLACE FUNCTION migrate_time_range(
    start_date TIMESTAMP,
    end_date TIMESTAMP
)
RETURNS INTEGER AS $$
DECLARE
    start_ms BIGINT;
    end_ms BIGINT;
    migrated INTEGER;
BEGIN
    start_ms := EXTRACT(EPOCH FROM start_date) * 1000;
    end_ms := EXTRACT(EPOCH FROM end_date) * 1000;
    
    INSERT INTO sqlth_1_data_new
    SELECT * FROM sqlth_1_data_old
    WHERE t_stamp >= start_ms AND t_stamp < end_ms;
    
    GET DIAGNOSTICS migrated = ROW_COUNT;
    RETURN migrated;
END;
$$ LANGUAGE plpgsql;

-- Execute
SELECT migrate_time_range('2024-01-01'::timestamp, '2024-12-31'::timestamp);
```

---

## See Also

- [Data Migration Documentation](../../docs/examples/05-data-migration.md)
- [ML Integration Guide](../../docs/examples/04-ml-integration.md)

**Last Updated:** December 7, 2025
