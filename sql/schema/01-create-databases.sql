-- ============================================================================
-- Ignition + TimescaleDB Database Setup Script
-- ============================================================================
-- Description: Creates databases and users for Ignition SCADA integration
-- Version: 1.3.0
-- Last Updated: 2025-12-08
-- Compatible with: PostgreSQL 13+, TimescaleDB 2.0+ (2.24+ recommended)
-- Maintained by: Miller-Eads Automation
-- ============================================================================

-- Note: Run this script as the postgres superuser
-- Usage: psql -U postgres -f 01-create-databases.sql

\echo '============================================================================'
\echo 'Ignition + TimescaleDB Database Setup'
\echo '============================================================================'
\echo ''

-- ============================================================================
-- Step 1: Create Ignition User
-- ============================================================================

\echo 'Creating ignition user...'

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'ignition') THEN
        CREATE ROLE ignition WITH
            LOGIN
            SUPERUSER
            CREATEDB
            CREATEROLE
            INHERIT
            REPLICATION
            BYPASSRLS
            CONNECTION LIMIT -1
            PASSWORD 'ignition';  -- CHANGE THIS PASSWORD!
        RAISE NOTICE 'User "ignition" created successfully';
    ELSE
        RAISE NOTICE 'User "ignition" already exists';
    END IF;
END
$$;

\echo '✓ User creation complete'
\echo ''

-- ============================================================================
-- Step 2: Create Historian Database
-- ============================================================================

\echo 'Creating historian database...'

SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'historian'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS historian;

CREATE DATABASE historian
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

COMMENT ON DATABASE historian IS 'Ignition SCADA tag history storage with TimescaleDB';

\echo '✓ Historian database created'
\echo ''

-- ============================================================================
-- Step 3: Create Alarm Log Database
-- ============================================================================

\echo 'Creating alarmlog database...'

SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'alarmlog'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS alarmlog;

CREATE DATABASE alarmlog
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

COMMENT ON DATABASE alarmlog IS 'Ignition SCADA alarm journal storage';

\echo '✓ Alarm log database created'
\echo ''

-- ============================================================================
-- Step 4: Create Audit Log Database
-- ============================================================================

\echo 'Creating auditlog database...'

SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'auditlog'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS auditlog;

CREATE DATABASE auditlog
    WITH 
    OWNER = ignition
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

COMMENT ON DATABASE auditlog IS 'Ignition SCADA audit trail storage';

\echo '✓ Audit log database created'
\echo ''

-- ============================================================================
-- Step 5: Enable TimescaleDB Extension on Historian
-- ============================================================================

\echo 'Enabling TimescaleDB extension on historian database...'

\c historian

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Grant permissions on TimescaleDB schemas
GRANT USAGE ON SCHEMA timescaledb_information TO ignition;
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO ignition;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA timescaledb_information TO ignition;

GRANT USAGE ON SCHEMA timescaledb_experimental TO ignition;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA timescaledb_experimental TO ignition;

-- Grant permissions on public schema
GRANT ALL ON SCHEMA public TO ignition;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ignition;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ignition;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ignition;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ignition;

\echo '✓ TimescaleDB extension enabled and permissions granted'
\echo ''

-- ============================================================================
-- Step 6: Verification
-- ============================================================================

\echo '============================================================================'
\echo 'Verification'
\echo '============================================================================'

-- Check TimescaleDB version
SELECT 'TimescaleDB Version: ' || extversion as info
FROM pg_extension WHERE extname='timescaledb';

-- List databases
\echo ''
\echo 'Created databases:'
SELECT datname as database_name, 
       pg_catalog.pg_get_userbyid(datdba) as owner,
       pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database 
WHERE datname IN ('historian', 'alarmlog', 'auditlog')
ORDER BY datname;

\echo ''
\echo '============================================================================'
\echo 'Setup Complete!'
\echo '============================================================================'
\echo ''
\echo 'IMPORTANT SECURITY NOTES:'
\echo '1. Change the default password for the ignition user immediately!'
\echo '2. After Ignition creates tables, consider reducing user privileges'
\echo '3. Configure pg_hba.conf to restrict network access appropriately'
\echo ''
\echo 'Next Steps:'
\echo '1. Configure Ignition database connections'
\echo '2. Create SQL Historian provider in Ignition'
\echo '3. Wait for Ignition to create tables'
\echo '4. Run 02-configure-hypertables.sql after tables are created'
\echo ''
\echo 'Connection URLs for Ignition:'
\echo '  Historian: jdbc:postgresql://localhost:5432/historian'
\echo '  AlarmLog:  jdbc:postgresql://localhost:5432/alarmlog'
\echo '  AuditLog:  jdbc:postgresql://localhost:5432/auditlog'
\echo '============================================================================'
