# Database Setup - Windows Server

**Platform:** Windows Server 2016+  
**Estimated Time:** 15-20 minutes  
**Difficulty:** Beginner  
**Prerequisites:** PostgreSQL and TimescaleDB installed

---

## Overview

This guide covers creating and configuring PostgreSQL databases for Ignition SCADA on Windows Server. For Linux setup, see [Database Setup - Linux](02-database-setup-linux.md).

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
```
sql/schema/01-create-databases.sql
```

### Step 2: Run Script via Command Prompt

**Open Command Prompt as Administrator:**

```cmd
cd "C:\Program Files\PostgreSQL\17\bin"
psql.exe -U postgres -f "C:\path\to\01-create-databases.sql"
```

**Enter postgres password when prompted.**

###Step 3: Verify Creation

The script will:
- Create `ignition` user with SUPERUSER privileges
- Create `historian`, `alarmlog`, and `auditlog` databases
- Enable TimescaleDB extension on historian database
- Set appropriate permissions

**Expected output:** Success messages for each database

---

## Manual Setup

### Step 1: Open SQL Shell (psql)

1. From Start Menu, search for **SQL Shell (psql)**
2. Press Enter to accept defaults:
   - Server: `localhost`
   - Database: `postgres`
   - Port: `5432`
   - Username: `postgres`
3. Enter postgres password

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

---

## Security Configuration

### Step 1: Change Default Password

**Immediately change the ignition user password:**

```sql
ALTER USER ignition WITH PASSWORD 'your_secure_password_here';
```

**Password Requirements:**
- Minimum 12 characters
- Mix of uppercase, lowercase, numbers, symbols
- Use a password manager

### Step 2: Restrict Network Access (Optional)

Edit `pg_hba.conf` to limit access to specific IPs:

**Location:**
```
C:\Program Files\PostgreSQL\17\data\pg_hba.conf
```

**Add specific IP ranges instead of 0.0.0.0/0:**

```ini
# Allow only Ignition server
host    all    all    192.168.1.100/32    scram-sha-256
```

**Restart PostgreSQL:**

```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

### Step 3: Enable SSL/TLS (Production)

**Generate self-signed certificate (for testing):**

```cmd
cd "C:\Program Files\PostgreSQL\17\data"
"C:\Program Files\PostgreSQL\17\bin\openssl.exe" req -new -x509 -days 365 -nodes -text -out server.crt -keyout server.key
```

**Edit postgresql.conf:**

```
C:\Program Files\PostgreSQL\17\data\postgresql.conf
```

**Add:**

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

**Restart PostgreSQL:**

```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

---

## Verification

### Step 1: List Databases

```sql
\l
```

**Expected:** historian, alarmlog, auditlog listed

### Step 2: Check Database Sizes

```sql
SELECT 
    datname as database_name,
    pg_catalog.pg_get_userbyid(datdba) as owner,
    pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database 
WHERE datname IN ('historian', 'alarmlog', 'auditlog')
ORDER BY datname;
```

**Expected:** All three databases with ignition as owner

### Step 3: Verify TimescaleDB Extension

```sql
\c historian
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
```

**Expected:** timescaledb with version number

### Step 4: Test User Permissions

```sql
-- Connect as ignition user
\c historian ignition

-- Try creating a test table
CREATE TABLE test_table (id SERIAL PRIMARY KEY, name TEXT);

-- Verify
\dt

-- Clean up
DROP TABLE test_table;
```

**Expected:** No errors

### Step 5: Test Remote Connection (If Applicable)

From Ignition server, open Command Prompt:

```cmd
"C:\Program Files\PostgreSQL\17\bin\psql.exe" -h <postgres-server-ip> -U ignition -d historian
```

Enter password when prompted.

**Expected:** Successful connection

---

## Troubleshooting

### "Role ignition already exists"

**Solution:** User was already created. You can:

**Option 1: Update password**
```sql
ALTER USER ignition WITH PASSWORD 'new_password';
```

**Option 2: Drop and recreate**
```sql
DROP ROLE ignition;
-- Then run CREATE ROLE command again
```

### "Database historian already exists"

**Solution:** Database was already created. You can:

**Option 1: Use existing database**
```sql
\c historian
-- Verify it's configured correctly
```

**Option 2: Drop and recreate**
```sql
DROP DATABASE historian;
-- Then run CREATE DATABASE command again
```

⚠️ **WARNING:** Dropping deletes all data!

### Cannot Connect to Database

**Check PostgreSQL service:**

```cmd
sc query postgresql-x64-17
```

**Should show:** `RUNNING`

**If stopped, start it:**

```cmd
net start postgresql-x64-17
```

### Permission Denied Errors

**Ensure you're connected as postgres or ignition user:**

```sql
-- Check current user
SELECT current_user;

-- If not correct, reconnect
\c postgres postgres
```

### TimescaleDB Extension Error

**Symptoms:** Error creating extension

**Verify shared_preload_libraries:**

```cmd
"C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -c "SHOW shared_preload_libraries;"
```

**Should include:** `timescaledb`

**If not, edit postgresql.conf and restart:**

```
C:\Program Files\PostgreSQL\17\data\postgresql.conf
```

Add:
```ini
shared_preload_libraries = 'timescaledb'
```

Restart:
```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
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

### Windows Task Scheduler Backup

**Create backup script (backup_databases.bat):**

```batch
@echo off
set PGPASSWORD=your_postgres_password
set BACKUP_DIR=D:\PostgreSQL_Backups
set DATE=%date:~10,4%-%date:~4,2%-%date:~7,2%

"C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" -U postgres -Fc historian > "%BACKUP_DIR%\historian_%DATE%.backup"
"C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" -U postgres -Fc alarmlog > "%BACKUP_DIR%\alarmlog_%DATE%.backup"
"C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" -U postgres -Fc auditlog > "%BACKUP_DIR%\auditlog_%DATE%.backup"

:: Delete backups older than 30 days
forfiles /p "%BACKUP_DIR%" /m *.backup /d -30 /c "cmd /c del @path"
```

**Schedule in Task Scheduler:**

1. Open **Task Scheduler**
2. Create Basic Task
3. Name: "PostgreSQL Backup"
4. Trigger: Daily at 2:00 AM
5. Action: Start a program
6. Program: `C:\path\to\backup_databases.bat`

---

## Next Steps

✅ Databases are now created and configured.

**Continue to:**
- [Ignition Configuration](03-ignition-configuration.md) - Configure Ignition historian

**Alternative Paths:**
- [Database Setup - Linux](02-database-setup-linux.md) - For Linux installations
- [Quick Reference - Windows](04-quick-reference.md#windows-specific-commands) - Quick commands

---

## Additional Resources

- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [TimescaleDB Best Practices](https://docs.timescale.com/timescaledb/latest/how-to-guides/user-defined-actions/)
- [SQL Script Repository](../../sql/schema/)

---

**Last Updated:** December 8, 2025  
**Platform:** Windows Server  
**Maintained By:** Miller-Eads Automation
