# Quick Reference Guide

**Target Audience:** Experienced users who need quick copy-paste commands  
**Time to Complete:** 15-20 minutes  
**For Detailed Instructions:** See [Full Documentation](../INDEX.md)

---

## Version Compatibility

This guide supports both:
- **Ignition 8.1.x** - Legacy path (Config → Tags → History)
- **Ignition 8.3.x** - Current path (Services → Historians → Historians)

Version-specific differences are marked with 📌 icons.

---

## Table of Contents

1. [Database Setup](#1-database-setup)
2. [Ignition Configuration](#2-ignition-configuration)
   - [8.1 vs 8.3 Differences](#ignition-version-differences)
3. [TimescaleDB Setup](#3-timescaledb-setup)
4. [Verification Commands](#4-verification-commands)
5. [Connection URLs](#5-connection-urls)

---

## 1. Database Setup

### Create User and Databases

**Run as postgres user:**

```sql
-- Create Ignition user with full privileges
CREATE ROLE ignition WITH
    LOGIN
    SUPERUSER
    CREATEDB
    CREATEROLE
    INHERIT
    REPLICATION
    BYPASSRLS
    CONNECTION LIMIT -1
    PASSWORD 'ignition';  -- ⚠️ CHANGE THIS PASSWORD!

-- Create Historian database
CREATE DATABASE historian
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

-- Create Alarm Log database
CREATE DATABASE alarmlog
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

-- Create Audit Log database
CREATE DATABASE auditlog
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
```

**📚 Detailed Instructions:** [Database Setup Guide](02-database-setup.md)

### Enable TimescaleDB Extension

```sql
-- Connect to historian database
\c historian

-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

---

## 2. Ignition Configuration

### Ignition Version Differences

| Configuration Area | Ignition 8.1 | Ignition 8.3+ |
|-------------------|--------------|---------------|
| **Database Connections** | Config → Database → Connections | Config → Database → Connections ✅ Same |
| **Tag Historian Setup** | Config → Tags → History | Services → Historians → Historians 📌 **CHANGED** |
| **Alarm Journal** | Alarming → Journal | Alarming → Journal ✅ Same |
| **Audit Log** | Security → Auditing | Security → Auditing ✅ Same |

### Step 1: Create Database Connections

**Navigate to:** `Config → Database → Connections`

**Create 3 connections with these settings:**

#### Connection 1: Historian

| Setting | Value |
|---------|-------|
| **Name** | `Historian` |
| **Database Type** | `PostgreSQL` |
| **Connect URL** | `jdbc:postgresql://localhost:5432/historian` |
| **Username** | `ignition` |
| **Password** | `your_password` |
| **Extra Connection Properties** | `reWriteBatchedInserts=true;` |

#### Connection 2: AlarmLog

| Setting | Value |
|---------|-------|
| **Name** | `AlarmLog` |
| **Connect URL** | `jdbc:postgresql://localhost:5432/alarmlog` |
| **Username** | `ignition` |
| **Password** | `your_password` |
| **Extra Properties** | `reWriteBatchedInserts=true;` |

#### Connection 3: AuditLog

| Setting | Value |
|---------|-------|
| **Name** | `AuditLog` |
| **Connect URL** | `jdbc:postgresql://localhost:5432/auditlog` |
| **Username** | `ignition` |
| **Password** | `your_password` |
| **Extra Properties** | `reWriteBatchedInserts=true;` |

### Step 2: Configure Tag Historian

#### 📌 For Ignition 8.1.x

**Navigate to:** `Config → Tags → History`

1. Click **Create new SQL Tag History Provider**
2. Configure:

| Setting | Value |
|---------|-------|
| **Name** | `Historian` |
| **Database** | `Historian` |
| **Enable Partitioning** | ❌ **UNCHECKED** (TimescaleDB handles this) |
| **Enable Data Pruning** | ❌ **UNCHECKED** (TimescaleDB handles this) |

#### 📌 For Ignition 8.3.x

**Navigate to:** `Services → Historians → Historians`

1. Click **Create Historian +**
2. Select **SQL Historian**
3. Configure:

| Setting | Value |
|---------|-------|
| **Name** | `Historian` |
| **Data Source** | `Historian` |
| **Enable Partitioning** | ❌ **UNCHECKED** (TimescaleDB handles this) |
| **Enable Data Pruning** | ❌ **UNCHECKED** (TimescaleDB handles this) |

**📚 Detailed Instructions:** [Ignition Configuration Guide](03-ignition-configuration.md)

### Step 3: Configure Alarm Journal

**Navigate to:** `Alarming → Journal` (Same for 8.1 and 8.3)

| Setting | Value |
|---------|-------|
| **Name** | `AlarmLog` |
| **Datasource** | `AlarmLog` |
| **Enable Data Pruning** | ✅ **CHECKED** |
| **Prune Age** | `90 Days` (adjust as needed) |

### Step 4: Configure Audit Log

**Navigate to:** `Security → Auditing` (Same for 8.1 and 8.3)

| Setting | Value |
|---------|-------|
| **Name** | `AuditLog` |
| **Datasource** | `AuditLog` |
| **Audit Gateway Events** | ✅ Checked |
| **Audit Designer Events** | ✅ Checked |
| **Enable Data Pruning** | ✅ **CHECKED** |
| **Prune Age** | `365 Days` |

---

## 3. TimescaleDB Setup

### Wait for Ignition to Create Tables

⏱️ **Wait 2-5 minutes** for Ignition to create the `sqlth_1_data` table.

**Verify table exists:**

```bash
psql -U postgres -d historian -c "\dt sqlth_1_data"
```

### Convert to Hypertable (24-hour chunks)

```sql
-- Connect to historian
\c historian

-- Create hypertable with 24-hour chunks
SELECT create_hypertable('sqlth_1_data', 't_stamp', 
    chunk_time_interval => 86400000, 
    if_not_exists => TRUE,
    migrate_data => TRUE);
```

### Enable Compression (compress after 7 days)

```sql
-- Enable compression
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);

-- Create helper function for integer timestamps
CREATE OR REPLACE FUNCTION unix_now() 
RETURNS BIGINT LANGUAGE SQL STABLE AS 
$$ SELECT (extract(epoch from now())*1000)::bigint $$;

-- Set integer now function
SELECT set_integer_now_func('sqlth_1_data', 'unix_now');

-- Add compression policy (compress chunks older than 7 days)
SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');
```

### Set Retention Policy

**Choose one based on your requirements:**

```sql
-- 1 Month retention
SELECT add_retention_policy('sqlth_1_data', INTERVAL '1 month');

-- 1 Year retention
SELECT add_retention_policy('sqlth_1_data', INTERVAL '1 year');

-- 2 Years retention
SELECT add_retention_policy('sqlth_1_data', INTERVAL '2 years');

-- 5 Years retention
SELECT add_retention_policy('sqlth_1_data', INTERVAL '5 years');

-- 10 Years retention
SELECT add_retention_policy('sqlth_1_data', INTERVAL '10 years');
```

### Disable Ignition Seed Queries

```sql
-- Prevent Ignition from managing partitions
UPDATE sqlth_partitions SET flags = 1;
```

### Add Performance Indexes

```sql
-- Composite index for tag queries
CREATE INDEX IF NOT EXISTS idx_sqlth_tagid_tstamp 
ON sqlth_1_data (tagid, t_stamp DESC);

-- BRIN index for time-based queries
CREATE INDEX IF NOT EXISTS idx_sqlth_tstamp_brin 
ON sqlth_1_data USING BRIN(t_stamp) 
WITH (pages_per_range = 128);
```

**📚 Detailed Instructions:** [Hypertable Configuration](../configuration/01-hypertable-setup.md)

---

## 4. Verification Commands

### Check TimescaleDB Installation

```sql
-- Connect to historian
\c historian

-- Check TimescaleDB version
SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';
```

### Verify Hypertable Creation

```sql
-- Check hypertable status
SELECT * FROM timescaledb_information.hypertables 
WHERE hypertable_name = 'sqlth_1_data';
```

### Check Compression Status

```sql
-- View compression stats
SELECT * FROM timescaledb_information.compression_settings 
WHERE hypertable_name = 'sqlth_1_data';
```

### Check Data is Being Stored

```sql
-- Count recent records
SELECT 
    COUNT(*) as total_records,
    MAX(t_stamp) as latest_timestamp,
    to_timestamp(MAX(t_stamp)/1000) as latest_time
FROM sqlth_1_data;
```

### Check Active Policies

```sql
-- View all policies
SELECT * FROM timescaledb_information.jobs
WHERE hypertable_name = 'sqlth_1_data';
```

**📚 More Diagnostics:** [Troubleshooting Guide](../troubleshooting/01-common-issues.md)

---

## 5. Connection URLs

### Local Installation (Same Server)

```
jdbc:postgresql://localhost:5432/historian
jdbc:postgresql://localhost:5432/alarmlog
jdbc:postgresql://localhost:5432/auditlog
```

### Remote Installation

**Replace `192.168.1.100` with your PostgreSQL server IP:**

```
jdbc:postgresql://192.168.1.100:5432/historian
jdbc:postgresql://192.168.1.100:5432/alarmlog
jdbc:postgresql://192.168.1.100:5432/auditlog
```

### With SSL/TLS

```
jdbc:postgresql://192.168.1.100:5432/historian?ssl=true&sslmode=require
jdbc:postgresql://192.168.1.100:5432/alarmlog?ssl=true&sslmode=require
jdbc:postgresql://192.168.1.100:5432/auditlog?ssl=true&sslmode=require
```

### With Custom Port

**Replace `5433` with your PostgreSQL port:**

```
jdbc:postgresql://192.168.1.100:5433/historian
```

---

## Essential Configuration Summary

### ✅ Must Do (Critical)

1. **Create 3 databases**: historian, alarmlog, auditlog
2. **Enable TimescaleDB extension** on historian database
3. **Add `reWriteBatchedInserts=true`** to all 3 database connections
4. **Disable Ignition partitioning** when using TimescaleDB hypertables
5. **Disable Ignition pruning** on historian (TimescaleDB handles it)
6. **Create hypertable** after Ignition creates sqlth_1_data
7. **Set compression policy** (compress after 7 days recommended)
8. **Set retention policy** (choose appropriate timeframe)
9. **Disable seed queries**: `UPDATE sqlth_partitions SET flags = 1`

### ⚙️ Recommended (Performance)

1. **Add composite index** on (tagid, t_stamp)
2. **Add BRIN index** on t_stamp
3. **Enable alarm pruning** (90-365 days)
4. **Enable audit pruning** (365 days typical)
5. **Use SSL/TLS** for remote connections

### 🔒 Security Checklist

- [ ] Change default ignition password
- [ ] Configure pg_hba.conf for network restrictions
- [ ] Use SSL/TLS for remote connections
- [ ] Restrict database user privileges after initial setup
- [ ] Enable PostgreSQL logging and auditing
- [ ] Regular backup schedule

---

## Quick Command Reference

### Windows Installation Commands

```powershell
# Install PostgreSQL and TimescaleDB (run installer)
# Then run database setup
psql -U postgres -f 01-create-databases.sql

# After Ignition creates tables, configure hypertables
psql -U postgres -d historian -f 02-configure-hypertables.sql
```

### Linux Installation Commands

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install postgresql-17 postgresql-17-timescaledb

# Configure and start
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Run setup scripts
sudo -u postgres psql -f 01-create-databases.sql
sudo -u postgres psql -d historian -f 02-configure-hypertables.sql
```

**📚 Full Installation Guide:** [Installation Instructions](01-installation.md)

---

## Common Pitfalls to Avoid

### ❌ Don't Do This

- **Don't enable Ignition partitioning** with TimescaleDB (double partitioning)
- **Don't enable Ignition pruning** on historian (use TimescaleDB retention)
- **Don't forget `reWriteBatchedInserts=true`** (major performance impact)
- **Don't skip the compression policy** (wastes storage)
- **Don't use default password** for production
- **Don't forget to disable seed queries** (causes partition conflicts)

### ⚠️ Version-Specific Issues

#### Ignition 8.1 Users
- Path is `Config → Tags → History` (not Services → Historians)
- May need to upgrade to 8.3+ for Core Historian features
- QuestDB-based Core Historian not available

#### Ignition 8.3 Users
- Path changed to `Services → Historians → Historians`
- Multiple historian types available (Core, SQL, Legacy)
- Ensure SQL Historian module is installed

---

## Next Steps

After completing this quick setup:

1. **Enable tag history** on your tags in Designer
2. **Run verification commands** to confirm data storage
3. **Set up continuous aggregates** for multi-resolution trending
4. **Configure backup schedule** for PostgreSQL
5. **Review performance tuning** guide

**📚 Continue Learning:**
- [Continuous Aggregates Guide](../configuration/04-continuous-aggregates.md)
- [Performance Tuning](../optimization/01-performance-tuning.md)
- [Data Migration Guide](../examples/05-data-migration.md)
- [ML Integration](../examples/04-ml-integration.md)

---

## Support Resources

### Documentation
- [Full Documentation Index](../INDEX.md)
- [Troubleshooting Guide](../troubleshooting/01-common-issues.md)
- [Best Practices](../reference/04-best-practices.md)

### External Resources
- [Ignition 8.1 Documentation](https://docs.inductiveautomation.com/docs/8.1/)
- [Ignition 8.3 Documentation](https://docs.inductiveautomation.com/docs/8.3/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

### Community
- [Ignition Forum](https://forum.inductiveautomation.com/)
- [ICS Texas Wiki](https://wiki.icstexas.com/books/ignition/page/using-postgresql-and-timescaledb-with-ignition)

---

**Document Version:** 1.1.0  
**Last Updated:** December 8, 2025  
**Compatible with:** Ignition 8.1+ and 8.3+, PostgreSQL 12+, TimescaleDB 2.0+
