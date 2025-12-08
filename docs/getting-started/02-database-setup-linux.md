# Database Setup - Linux (Ubuntu/Debian)

**Platform:** Ubuntu 20.04+, Debian 11+  
**Estimated Time:** 15-20 minutes  
**Difficulty:** Beginner  
**Prerequisites:** PostgreSQL and TimescaleDB installed

---

## Overview

This guide covers creating and configuring PostgreSQL databases for Ignition SCADA on Linux. For Windows setup, see [Database Setup - Windows](02-database-setup-windows.md).

---

## Table of Contents

1. [Automated Setup](#automated-setup)
2. [Manual Setup](#manual-setup)
3. [Security Configuration](#security-configuration)
4. [Verification](#verification)
5. [Troubleshooting](#troubleshooting)

---

## Automated Setup

### Step 1: Download SQL Script

Download the database creation script from the repository:
```bash
wget https://forge.hpowr.com/chendrixson/ignition-timescaledb/raw/branch/main/sql/schema/01-create-databases.sql
```

Or copy from your cloned repository:
```bash
cd /path/to/ignition-timescaledb
```

### Step 2: Run Script

```bash
sudo -u postgres psql -f sql/schema/01-create-databases.sql
```

### Step 3: Verify Creation

The script will:
- Create `ignition` user with SUPERUSER privileges
- Create `historian`, `alarmlog`, and `auditlog` databases
- Enable TimescaleDB extension on historian database
- Set appropriate permissions

**Expected output:** Success messages for each database

---

## Manual Setup

### Step 1: Connect to PostgreSQL

```bash
sudo -u postgres psql
```

### Step 2: Create Ignition User

```sql
CREATE ROLE ignition WITH
    LOGIN
    SUPERUSER
    CREATEDB
    CREATEROLE
    INHERIT
    REPLICATION
    BYPASSRLS
    CONNECTION LIMIT -1
    PASSWORD 'ignition';
```

⚠️ **IMPORTANT:** Change 'ignition' to a secure password!

**Expected:** `CREATE ROLE`

### Step 3: Create Historian Database

```sql
CREATE DATABASE historian
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
```

**Expected:** `CREATE DATABASE`

### Step 4: Create Alarm Log Database

```sql
CREATE DATABASE alarmlog
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
```

**Expected:** `CREATE DATABASE`

### Step 5: Create Audit Log Database

```sql
CREATE DATABASE auditlog
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
```

**Expected:** `CREATE DATABASE`

### Step 6: Connect to Historian Database

```sql
\c historian
```

**Expected:** `You are now connected to database "historian"`

### Step 7: Enable TimescaleDB Extension

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

**Expected:** `CREATE EXTENSION` or warning that it already exists

### Step 8: Grant Permissions

```sql
-- Grant permissions on TimescaleDB schemas
GRANT USAGE ON SCHEMA timescaledb_information TO ignition;
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO ignition;

-- Grant permissions on public schema
GRANT ALL ON SCHEMA public TO ignition;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ignition;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ignition;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ignition;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ignition;
```

### Step 9: Exit psql

```sql
\q
```

---

## Security Configuration

### Step 1: Change Default Password

**Immediately change the ignition user password:**

```bash
sudo -u postgres psql -c "ALTER USER ignition WITH PASSWORD 'your_secure_password_here';"
```

**Password Requirements:**
- Minimum 12 characters
- Mix of uppercase, lowercase, numbers, symbols
- Use a password manager

### Step 2: Restrict Network Access

Edit `pg_hba.conf` to limit access to specific IPs:

**For PostgreSQL 17:**
```bash
sudo nano /etc/postgresql/17/main/pg_hba.conf
```

**For PostgreSQL 15:**
```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf
```

**Add specific IP ranges instead of 0.0.0.0/0:**

```ini
# Allow only Ignition server
host    historian    ignition    192.168.1.100/32    scram-sha-256
host    alarmlog     ignition    192.168.1.100/32    scram-sha-256
host    auditlog     ignition    192.168.1.100/32    scram-sha-256
```

**Restart PostgreSQL:**

```bash
sudo systemctl restart postgresql
```

### Step 3: Enable SSL/TLS (Production)

**Generate self-signed certificate (for testing):**

```bash
# For PostgreSQL 17
cd /var/lib/postgresql/17/main

# Generate key and certificate
sudo -u postgres openssl req -new -x509 -days 365 -nodes -text -out server.crt -keyout server.key -subj "/CN=postgres.example.com"

# Set permissions
sudo -u postgres chmod 600 server.key
sudo -u postgres chmod 644 server.crt
```

**Edit postgresql.conf:**

```bash
# For PostgreSQL 17
sudo nano /etc/postgresql/17/main/postgresql.conf
```

**Add/modify:**

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

**Restart PostgreSQL:**

```bash
sudo systemctl restart postgresql
```

### Step 4: Limit User Privileges (Optional)

For production, consider creating a more limited user:

```bash
sudo -u postgres psql
```

```sql
-- Create limited user
CREATE USER ignition_app WITH PASSWORD 'secure_password';

-- Grant database access
GRANT CONNECT ON DATABASE historian TO ignition_app;
GRANT CONNECT ON DATABASE alarmlog TO ignition_app;
GRANT CONNECT ON DATABASE auditlog TO ignition_app;

-- Grant schema access
\c historian
GRANT USAGE ON SCHEMA public TO ignition_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ignition_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ignition_app;

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ignition_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ignition_app;
```

---

## Verification

### Step 1: List Databases

```bash
sudo -u postgres psql -c "\l"
```

**Expected:** historian, alarmlog, auditlog listed

### Step 2: Check Database Sizes

```bash
sudo -u postgres psql -c "SELECT datname as database_name, pg_catalog.pg_get_userbyid(datdba) as owner, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datname IN ('historian', 'alarmlog', 'auditlog') ORDER BY datname;"
```

**Expected:** All three databases with ignition as owner

### Step 3: Verify TimescaleDB Extension

```bash
sudo -u postgres psql -d historian -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';"
```

**Expected:** timescaledb with version number

### Step 4: Test User Permissions

```bash
# Connect as ignition user
psql -U ignition -d historian -h localhost
```

**At psql prompt:**

```sql
-- Try creating a test table
CREATE TABLE test_table (id SERIAL PRIMARY KEY, name TEXT);

-- Verify
\dt

-- Clean up
DROP TABLE test_table;

-- Exit
\q
```

**Expected:** No errors

### Step 5: Test Remote Connection (If Applicable)

From Ignition server:

```bash
psql -h <postgres-server-ip> -U ignition -d historian
```

Enter password when prompted.

**Expected:** Successful connection

---

## Troubleshooting

### "Role ignition already exists"

**Solution:** User was already created. You can:

**Option 1: Update password**
```bash
sudo -u postgres psql -c "ALTER USER ignition WITH PASSWORD 'new_password';"
```

**Option 2: Drop and recreate**
```bash
sudo -u postgres psql -c "DROP ROLE ignition;"
# Then run CREATE ROLE command again
```

### "Database historian already exists"

**Solution:** Database was already created. You can:

**Option 1: Use existing database**
```bash
sudo -u postgres psql -d historian
```

**Option 2: Drop and recreate**
```bash
sudo -u postgres psql -c "DROP DATABASE historian;"
# Then run CREATE DATABASE command again
```

⚠️ **WARNING:** Dropping deletes all data!

### Cannot Connect to Database

**Check PostgreSQL service:**

```bash
sudo systemctl status postgresql
```

**Should show:** `Active: active (running)`

**If not running, start it:**

```bash
sudo systemctl start postgresql
```

### Permission Denied Errors

**Ensure you're using sudo with postgres user:**

```bash
sudo -u postgres psql
```

**Or check pg_hba.conf settings:**

```bash
# For PostgreSQL 17
sudo cat /etc/postgresql/17/main/pg_hba.conf | grep -v "^#" | grep -v "^$"
```

### TimescaleDB Extension Error

**Symptoms:** Error creating extension

**Verify shared_preload_libraries:**

```bash
# For PostgreSQL 17
sudo -u postgres psql -c "SHOW shared_preload_libraries;"
```

**Should include:** `timescaledb`

**If not, edit postgresql.conf:**

```bash
sudo nano /etc/postgresql/17/main/postgresql.conf
```

Add:
```ini
shared_preload_libraries = 'timescaledb'
```

Restart:
```bash
sudo systemctl restart postgresql
```

---

## Database Sizing Guidelines

### Estimating Storage Requirements

**Calculate based on tag count and scan rates:**

```
Storage per day = (Tag Count × Samples per Day × Bytes per Sample) × Compression Ratio

Example:
- 1,000 tags
- Sampled every 10 seconds = 8,640 samples/day
- ~40 bytes per sample (uncompressed)
- 20:1 compression ratio

Storage = (1,000 × 8,640 × 40) / 20 = ~17 MB/day = 6.2 GB/year
```

### Recommended Disk Space

| Tag Count | Scan Rate | Daily Storage | 1 Year | 10 Years |
|-----------|-----------|---------------|--------|----------|
| 500 | 10 sec | 8 MB | 3 GB | 30 GB |
| 1,000 | 10 sec | 17 MB | 6 GB | 60 GB |
| 5,000 | 10 sec | 85 MB | 31 GB | 310 GB |
| 10,000 | 10 sec | 170 MB | 62 GB | 620 GB |

**Add 50% buffer for safety**

---

## Backup Configuration

### Automated Daily Backups

**Create backup script:**

```bash
sudo nano /usr/local/bin/backup_ignition_dbs.sh
```

**Add content:**

```bash
#!/bin/bash

# Configuration
BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y-%m-%d)
RETENTION_DAYS=30

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Backup databases
sudo -u postgres pg_dump -Fc historian > "$BACKUP_DIR/historian_$DATE.backup"
sudo -u postgres pg_dump -Fc alarmlog > "$BACKUP_DIR/alarmlog_$DATE.backup"
sudo -u postgres pg_dump -Fc auditlog > "$BACKUP_DIR/auditlog_$DATE.backup"

# Delete old backups
find $BACKUP_DIR -name "*.backup" -mtime +$RETENTION_DAYS -delete

# Log completion
echo "$(date): Backup completed" >> /var/log/postgresql_backup.log
```

**Make executable:**

```bash
sudo chmod +x /usr/local/bin/backup_ignition_dbs.sh
```

**Create cron job:**

```bash
sudo crontab -e
```

**Add line (runs daily at 2 AM):**

```cron
0 2 * * * /usr/local/bin/backup_ignition_dbs.sh
```

### Manual Backup

**Backup single database:**

```bash
sudo -u postgres pg_dump -Fc historian > historian_backup.backup
```

**Restore from backup:**

```bash
sudo -u postgres pg_restore -d historian historian_backup.backup
```

---

## Performance Monitoring

### Check Database Activity

```bash
sudo -u postgres psql -c "SELECT datname, numbackends, xact_commit, xact_rollback FROM pg_stat_database WHERE datname IN ('historian', 'alarmlog', 'auditlog');"
```

### Check Table Sizes

```bash
sudo -u postgres psql -d historian -c "SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"
```

### Monitor Active Connections

```bash
sudo -u postgres psql -c "SELECT datname, count(*) FROM pg_stat_activity WHERE datname IN ('historian', 'alarmlog', 'auditlog') GROUP BY datname;"
```

---

## Next Steps

✅ Databases are now created and configured.

**Continue to:**
- [Ignition Configuration](03-ignition-configuration.md) - Configure Ignition historian

**Alternative Paths:**
- [Database Setup - Windows](02-database-setup-windows.md) - For Windows installations
- [Quick Reference - Linux](04-quick-reference.md#linux-specific-commands) - Quick commands

---

## Additional Resources

- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [TimescaleDB Best Practices](https://www.tigerdata.com/docs/timescaledb/latest/how-to-guides/user-defined-actions/)
- [SQL Script Repository](../../sql/schema/)
- [Linux Cron Tutorial](https://crontab.guru/)

---

**Last Updated:** December 8, 2025  
**Platform:** Linux (Ubuntu/Debian)  
**Maintained By:** Miller-Eads Automation
