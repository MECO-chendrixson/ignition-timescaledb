# Database Setup

**Estimated Time:** 15-20 minutes  
**Difficulty:** Beginner  
**Prerequisites:** PostgreSQL and TimescaleDB installed

## Overview

This guide walks through creating the necessary databases and users for Ignition SCADA, including the historian, alarm journal, and audit log databases.

## Database Architecture

Ignition typically uses three separate databases:

| Database | Purpose | Typical Size |
|----------|---------|--------------|
| **historian** | Tag history storage | Largest - grows continuously |
| **alarmlog** | Alarm event history | Medium - depends on alarm frequency |
| **auditlog** | System audit trail | Small - administrative events only |

**Best Practice:** Use separate databases rather than schemas for better management and backup flexibility.

---

## Creating Databases

### Option 1: Automated Setup Script

We provide a complete SQL script for quick setup.

#### Download the Script

The script is located in: `sql/schema/01-create-databases.sql`

#### Run the Script

**Linux:**
```bash
cd /path/to/ignition-timescaledb
psql -U postgres -f sql/schema/01-create-databases.sql
```

**Windows:**
```cmd
cd C:\path\to\ignition-timescaledb
psql -U postgres -f sql\schema\01-create-databases.sql
```

**What the script does:**
- Creates the `ignition` user with necessary privileges
- Creates `historian`, `alarmlog`, and `auditlog` databases
- Sets proper ownership and permissions
- Enables TimescaleDB extension on the historian database

---

### Option 2: Manual Setup

Follow these steps to manually create databases and users.

#### Step 1: Connect to PostgreSQL

```bash
# Linux
sudo -u postgres psql

# Windows
psql -U postgres
```

Enter the postgres password when prompted.

#### Step 2: Create Ignition User

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
  PASSWORD 'your_secure_password';
```

**Security Notes:**
- Replace `your_secure_password` with a strong password
- Store the password securely (e.g., password manager)
- For production, consider restricting privileges:
  - Remove `SUPERUSER` if possible
  - Remove `CREATEDB` and `CREATEROLE` after setup
  - Remove `REPLICATION` if not using streaming replication

**Production User (More Restrictive):**
```sql
CREATE ROLE ignition WITH
  LOGIN
  CREATEDB
  CONNECTION LIMIT -1
  PASSWORD 'your_secure_password';
```

#### Step 3: Create Historian Database

```sql
CREATE DATABASE historian
  WITH 
  OWNER = ignition
  ENCODING = 'UTF8'
  LOCALE_PROVIDER = 'libc'
  CONNECTION LIMIT = -1
  IS_TEMPLATE = False;
```

**Options explained:**
- `OWNER = ignition`: Database owner
- `ENCODING = 'UTF8'`: Unicode support
- `CONNECTION LIMIT = -1`: Unlimited connections
- `IS_TEMPLATE = False`: Not a template database

#### Step 4: Create Alarm Log Database

```sql
CREATE DATABASE alarmlog
  WITH 
  OWNER = ignition
  ENCODING = 'UTF8'
  LOCALE_PROVIDER = 'libc'
  CONNECTION LIMIT = -1
  IS_TEMPLATE = False;
```

#### Step 5: Create Audit Log Database

```sql
CREATE DATABASE auditlog
  WITH 
  OWNER = ignition
  ENCODING = 'UTF8'
  LOCALE_PROVIDER = 'libc'
  CONNECTION LIMIT = -1
  IS_TEMPLATE = False;
```

#### Step 6: Enable TimescaleDB Extension

```sql
-- Connect to historian database
\c historian

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Verify extension
SELECT * FROM pg_extension WHERE extname = 'timescaledb';
```

Expected output:
```
 oid  |   extname    | extowner | extnamespace | ...
------+--------------+----------+--------------+-----
 xxxxx| timescaledb  |       10 |         2200 | ...
```

#### Step 7: Grant Necessary Permissions

```sql
-- Grant all privileges on historian database
GRANT ALL PRIVILEGES ON DATABASE historian TO ignition;

-- Grant usage on TimescaleDB schema
GRANT USAGE ON SCHEMA timescaledb_information TO ignition;
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO ignition;

-- Grant on public schema
GRANT ALL ON SCHEMA public TO ignition;
```

#### Step 8: Exit psql

```sql
\q
```

---

## Verification

### Verify Databases Created

```bash
psql -U postgres -c "\l"
```

Expected output should include:
```
                                   List of databases
    Name     |  Owner   | Encoding |   Collate   |    Ctype    |
-------------+----------+----------+-------------+-------------+
 alarmlog    | ignition | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 auditlog    | ignition | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 historian   | ignition | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 postgres    | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
```

### Verify User Can Connect

```bash
psql -U ignition -d historian -c "SELECT current_database(), current_user;"
```

Expected output:
```
 current_database | current_user
------------------+--------------
 historian        | ignition
```

### Verify TimescaleDB Extension

```bash
psql -U ignition -d historian -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';"
```

Expected output:
```
 extversion
------------
 2.13.0
```

### Test Write Permissions

```bash
psql -U ignition -d historian -c "CREATE TABLE test_table (id SERIAL PRIMARY KEY, data TEXT); DROP TABLE test_table;"
```

Expected output:
```
CREATE TABLE
DROP TABLE
```

---

## Security Hardening

### Restrict Ignition User Privileges (Production)

After Ignition creates its tables, you can reduce the `ignition` user's privileges:

```sql
-- Connect as postgres
psql -U postgres

-- Remove superuser privileges
ALTER ROLE ignition NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- Verify changes
\du ignition
```

### Enable SSL Connections (Optional but Recommended)

#### Generate SSL Certificates

**Linux:**
```bash
cd /var/lib/postgresql/15/main
sudo -u postgres openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt -keyout server.key -subj "/CN=dbhost.yourdomain.com"
sudo chmod 600 server.key
```

**Edit `postgresql.conf`:**
```conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

**Restart PostgreSQL:**
```bash
sudo systemctl restart postgresql
```

### Configure Password Encryption

Edit `postgresql.conf`:
```conf
password_encryption = scram-sha-256
```

Update `pg_hba.conf` to use `scram-sha-256` instead of `md5`:
```conf
host    all             all             0.0.0.0/0               scram-sha-256
```

---

## Database Sizing Guidelines

### Estimating Storage Requirements

**Formula for tag history:**
```
Storage per year ≈ (Tags × Samples/day × 365 × Bytes/sample) / Compression Ratio
```

**Example calculation:**
- 1,000 tags
- 3,600 samples/day (1-second sampling rate)
- 50 bytes per sample (average)
- 15:1 compression ratio (TimescaleDB)

```
Storage = (1000 × 3600 × 365 × 50) / 15
        = 4.38 GB/year
```

### Recommended Storage Allocation

| System Size | Tags | Storage (5 years) | RAM Recommendation |
|-------------|------|-------------------|-------------------|
| Small       | <1,000 | 25 GB | 8 GB |
| Medium      | 1,000-10,000 | 250 GB | 16 GB |
| Large       | 10,000-100,000 | 2.5 TB | 32+ GB |
| Enterprise  | >100,000 | 10+ TB | 64+ GB |

**Best Practice:** Monitor actual usage and adjust as needed.

---

## Database Maintenance Setup

### Enable Auto-Vacuum

Edit `postgresql.conf`:
```conf
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
```

### Configure WAL Archiving (for Backups)

```conf
wal_level = replica
archive_mode = on
archive_command = 'cp %p /var/lib/postgresql/15/archive/%f'
```

Create archive directory:
```bash
sudo mkdir -p /var/lib/postgresql/15/archive
sudo chown postgres:postgres /var/lib/postgresql/15/archive
```

---

## Troubleshooting

### "database does not exist" Error

**Verify database name:**
```bash
psql -U postgres -c "\l" | grep historian
```

**Recreate if needed:**
```sql
DROP DATABASE IF EXISTS historian;
CREATE DATABASE historian OWNER ignition;
```

### "permission denied" Error

**Grant explicit permissions:**
```sql
GRANT ALL PRIVILEGES ON DATABASE historian TO ignition;
ALTER DATABASE historian OWNER TO ignition;
```

### TimescaleDB Extension Not Available

**Check extension is installed:**
```bash
psql -U postgres -c "SELECT * FROM pg_available_extensions WHERE name='timescaledb';"
```

**If not available, reinstall TimescaleDB:**
```bash
# Ubuntu
sudo apt install --reinstall timescaledb-2-postgresql-15

# RHEL
sudo dnf reinstall timescaledb-2-postgresql-15
```

### Connection Limit Reached

**Check current connections:**
```sql
SELECT count(*) FROM pg_stat_activity WHERE datname = 'historian';
```

**Increase connection limit:**
```sql
ALTER DATABASE historian CONNECTION LIMIT 100;
```

---

## Next Steps

✅ Databases are created and configured.

**Continue to:**
- [Ignition Configuration](03-ignition-configuration.md) - Configure Ignition to use these databases

---

## Additional Resources

- [PostgreSQL Database Roles](https://www.postgresql.org/docs/current/user-manag.html)
- [TimescaleDB Getting Started](https://docs.timescale.com/getting-started/latest/)
- [PostgreSQL Security Best Practices](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)

**Last Updated:** December 7, 2025
