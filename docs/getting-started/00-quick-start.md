# Quick Start Guide

**Estimated Time:** 30-45 minutes  
**Difficulty:** Intermediate  
**Prerequisites:** PostgreSQL and TimescaleDB installed

## Overview

This quick start guide provides a streamlined setup process for experienced users familiar with PostgreSQL and Ignition. For detailed explanations, refer to the complete installation guides.

## Step-by-Step Setup

### 1. Create Database and User

```sql
-- Connect to PostgreSQL as superuser
psql -U postgres

-- Create Ignition user
CREATE ROLE ignition WITH
  LOGIN
  SUPERUSER
  CREATEDB
  CREATEROLE
  PASSWORD 'your_secure_password';

-- Create historian database
CREATE DATABASE historian
  WITH OWNER = ignition
  ENCODING = 'UTF8'
  CONNECTION LIMIT = -1;

-- Exit psql
\q
```

### 2. Enable TimescaleDB Extension

```sql
-- Connect to historian database
psql -U postgres -d historian

-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Exit psql
\q
```

### 3. Configure Ignition Database Connection

1. Open Ignition Gateway: `http://your-gateway:8088`
2. Navigate to **Config → Database → Connections**
3. Click **Create new Database Connection**
4. Configure:
   - **Name:** `Historian`
   - **Database Type:** `PostgreSQL`
   - **Connect URL:** `jdbc:postgresql://localhost:5432/historian`
   - **Username:** `ignition`
   - **Password:** `your_secure_password`
   - **Extra Connection Properties:** `reWriteBatchedInserts=true;`
5. Click **Create New Database Connection**
6. Verify connection shows **Valid**

### 4. Create SQL Historian Provider

1. Navigate to **Services → Historians → Historians**
2. Click **Create Historian +**
3. Select **SQL Historian** and click **Next**
4. Configure:
   - **Name:** `Historian`
   - **Enabled:** ✅ Checked
   - **Data Source:** `Historian`
   - **Enable Partitioning:** ❌ **Unchecked**
   - **Enable Data Pruning:** ❌ **Unchecked**
5. Click **Create Historian**

### 5. Wait for Table Creation

Ignition will automatically create the necessary tables. Wait 1-2 minutes, then verify:

```sql
psql -U postgres -d historian -c "\dt sqlth*"
```

You should see tables including `sqlth_1_data`, `sqlth_te`, `sqlth_partitions`, etc.

### 6. Convert to TimescaleDB Hypertable

```sql
-- Connect to historian database
psql -U postgres -d historian

-- Create hypertable (24-hour chunks)
SELECT * FROM create_hypertable(
  'sqlth_1_data',
  't_stamp',
  if_not_exists => True,
  chunk_time_interval => 86400000,
  migrate_data => True
);
```

### 7. Enable Compression

```sql
-- Configure compression
ALTER TABLE sqlth_1_data SET (
  timescaledb.compress,
  timescaledb.compress_orderby = 't_stamp DESC',
  timescaledb.compress_segmentby = 'tagid'
);

-- Create timestamp function
CREATE OR REPLACE FUNCTION unix_now() 
RETURNS BIGINT 
LANGUAGE SQL STABLE 
AS $$ 
  SELECT (extract(epoch from now())*1000)::bigint 
$$;

-- Set integer now function
SELECT * FROM set_integer_now_func('sqlth_1_data', 'unix_now');

-- Add compression policy (compress after 7 days)
CALL add_columnstore_policy('sqlth_1_data', 604800000);
```

### 8. Configure Retention Policy

```sql
-- Keep data for 10 years (example)
SELECT * FROM add_retention_policy('sqlth_1_data', 315360000000);

-- Or keep for 1 year
-- SELECT * FROM add_retention_policy('sqlth_1_data', 31536000000);
```

### 9. Optimize Performance

```sql
-- Disable seed queries for better performance
UPDATE sqlth_partitions 
SET flags = 1 
WHERE pname = 'sqlth_1_data';

-- Create BRIN index
CREATE INDEX idx_sqlth_data_tstamp_brin 
ON sqlth_1_data 
USING BRIN (t_stamp);

-- Create composite index
CREATE INDEX idx_sqlth_data_tagid_tstamp 
ON sqlth_1_data (tagid, t_stamp DESC);
```

### 10. Enable Tag History in Ignition

1. Open Ignition Designer
2. Navigate to a tag in the Tag Browser
3. Edit the tag
4. Under **Tag History** section:
   - **History Enabled:** ✅ Checked
   - **Historical Tag Provider:** `Historian`
   - **Sample Mode:** `On Change` (or as needed)
   - **Storage Provider:** `Historian`
5. Save the tag

### 11. Verify Data Collection

Wait a few minutes, then check:

```sql
-- View recent data
SELECT 
  t.tagpath,
  d.t_stamp,
  COALESCE(d.intvalue, d.floatvalue) as value,
  d.dataintegrity
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
ORDER BY d.t_stamp DESC
LIMIT 10;
```

## Verification Checklist

- [ ] Database connection shows **Valid** in Ignition Gateway
- [ ] Historian provider shows **Status: Running**
- [ ] `sqlth_1_data` table exists and is a hypertable
- [ ] Compression policy is active
- [ ] Retention policy is configured
- [ ] Indexes are created
- [ ] Tag history is enabled on test tags
- [ ] Data is being written to database

## Next Steps

### For Production Deployment
1. Review [Performance Tuning](../optimization/01-performance-tuning.md)
2. Configure [Continuous Aggregates](../configuration/04-continuous-aggregates.md)
3. Set up [Backup Procedures](../troubleshooting/04-diagnostic-tools.md#backup)
4. Enable [Monitoring](../troubleshooting/04-diagnostic-tools.md#monitoring)

### For Development
1. Explore [Query Examples](../examples/01-basic-queries.md)
2. Try [Scripting Examples](../examples/03-scripting-examples.md)
3. Experiment with [Continuous Aggregates](../examples/02-continuous-aggregates.md)

## Common Issues

### Connection Failed
- Verify PostgreSQL is running: `systemctl status postgresql`
- Check `pg_hba.conf` allows connections from Ignition server
- Verify firewall allows port 5432

### Tables Not Created
- Ensure historian is enabled and started
- Check Ignition logs: `Gateway → Status → Diagnostics → Logs`
- Verify database permissions for `ignition` user

### No Data Being Stored
- Confirm tags have history enabled
- Check tag quality (must be Good quality)
- Verify Store and Forward isn't backed up
- Review historian diagnostics in Gateway

## Performance Quick Tips

```sql
-- Check compression status
SELECT * FROM timescaledb_information.compressed_chunk_stats;

-- Check retention policy
SELECT * FROM timescaledb_information.jobs 
WHERE proc_name = 'policy_retention';

-- View chunk information
SELECT * FROM timescaledb_information.chunks 
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 5;
```

## Quick Reference Commands

```bash
# Check TimescaleDB version
psql -U postgres -d historian -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';"

# View database size
psql -U postgres -d historian -c "SELECT pg_size_pretty(pg_database_size('historian'));"

# Count rows in main table
psql -U postgres -d historian -c "SELECT COUNT(*) FROM sqlth_1_data;"

# Show active tags
psql -U postgres -d historian -c "SELECT COUNT(*) FROM sqlth_te WHERE retired IS NULL;"
```

---

**Related Documentation:**
- [Full Installation Guide](01-installation.md)
- [Database Setup Details](02-database-setup.md)
- [Ignition Configuration](03-ignition-configuration.md)
- [Performance Tuning](../optimization/01-performance-tuning.md)

**Last Updated:** December 7, 2025
