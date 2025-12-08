-- ============================================================================
-- TimescaleDB Hypertable Configuration for Ignition
-- ============================================================================
-- Description: Converts Ignition historian tables to TimescaleDB hypertables
-- Version: 1.3.0
-- Last Updated: 2025-12-08
-- Prerequisites: 
--   - Ignition has created sqlth_1_data table
--   - TimescaleDB extension enabled
-- Maintained by: Miller-Eads Automation
-- ============================================================================

-- IMPORTANT: Wait for Ignition to create the sqlth_1_data table before running!
-- Usage: psql -U postgres -d historian -f 02-configure-hypertables.sql

\echo '============================================================================'
\echo 'TimescaleDB Hypertable Configuration'
\echo '============================================================================'
\echo ''

-- Connect to historian database
\c historian

-- ============================================================================
-- Step 1: Verify Prerequisites
-- ============================================================================

\echo 'Checking prerequisites...'

DO $$
BEGIN
    -- Check if TimescaleDB extension exists
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        RAISE EXCEPTION 'TimescaleDB extension not found. Please install it first.';
    END IF;
    
    -- Check if sqlth_1_data table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables 
                   WHERE table_name = 'sqlth_1_data') THEN
        RAISE EXCEPTION 'Table sqlth_1_data not found. Wait for Ignition to create it.';
    END IF;
    
    RAISE NOTICE '✓ Prerequisites met';
END
$$;

\echo '✓ Prerequisites verified'
\echo ''

-- ============================================================================
-- Step 2: Display Current Table Statistics
-- ============================================================================

\echo 'Current table statistics:'
SELECT 
    'sqlth_1_data' as table_name,
    COUNT(*) as row_count,
    pg_size_pretty(pg_total_relation_size('sqlth_1_data')) as total_size,
    pg_size_pretty(pg_relation_size('sqlth_1_data')) as table_size,
    pg_size_pretty(pg_indexes_size('sqlth_1_data')) as indexes_size
FROM sqlth_1_data;

\echo ''

-- ============================================================================
-- Step 3: Create Hypertable
-- ============================================================================

\echo 'Converting sqlth_1_data to hypertable...'
\echo 'Configuration: 24-hour chunks, partitioned by t_stamp column'
\echo ''

-- Create hypertable with 24-hour chunks (86400000 milliseconds)
SELECT create_hypertable(
    'sqlth_1_data',
    't_stamp',
    chunk_time_interval => 86400000,  -- 24 hours in milliseconds
    if_not_exists => TRUE,
    migrate_data => TRUE
);

\echo '✓ Hypertable created successfully'
\echo ''

-- ============================================================================
-- Step 4: Configure Compression
-- ============================================================================

\echo 'Configuring compression settings...'

-- Enable compression with optimal settings
ALTER TABLE sqlth_1_data SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 't_stamp DESC',
    timescaledb.compress_segmentby = 'tagid'
);

\echo '✓ Compression configured'
\echo '  - Order by: t_stamp DESC (recent data first)'
\echo '  - Segment by: tagid (separate compression per tag)'
\echo ''

-- ============================================================================
-- Step 5: Create Timestamp Helper Function
-- ============================================================================

\echo 'Creating unix_now() function for compression policies...'

CREATE OR REPLACE FUNCTION unix_now() 
RETURNS BIGINT 
LANGUAGE SQL 
STABLE 
AS $$ 
    SELECT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
$$;

COMMENT ON FUNCTION unix_now() IS 'Returns current Unix timestamp in milliseconds for TimescaleDB policies';

\echo '✓ Helper function created'
\echo ''

-- ============================================================================
-- Step 6: Set Integer Now Function
-- ============================================================================

\echo 'Setting integer now function for hypertable...'

SELECT set_integer_now_func('sqlth_1_data', 'unix_now');

\echo '✓ Integer now function configured'
\echo ''

-- ============================================================================
-- Step 7: Add Compression Policy
-- ============================================================================

\echo 'Adding compression policy...'
\echo 'Policy: Compress chunks older than 7 days'
\echo ''

-- Compress chunks older than 7 days (604800000 milliseconds = 7 days)
-- For BIGINT time columns, must use BIGINT type casting
SELECT add_compression_policy('sqlth_1_data', BIGINT '604800000');

\echo '✓ Compression policy added'
\echo '  - Chunks older than 7 days will be compressed automatically'
\echo '  - Runs in background, does not affect data accessibility'
\echo ''

-- ============================================================================
-- Step 8: Add Retention Policy
-- ============================================================================

\echo 'Adding data retention policy...'
\echo 'Choose retention period based on your requirements:'
\echo ''

-- Default: 10 years (315360000000 milliseconds = 10 years)
-- For BIGINT time columns, must use BIGINT type casting
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');

-- Alternative retention periods (comment out the one above and uncomment your choice):

-- 1 year retention (31536000000 milliseconds)
-- SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '31536000000');

-- 2 years retention (63072000000 milliseconds)
-- SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '63072000000');

-- 5 years retention (157680000000 milliseconds)
-- SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '157680000000');

\echo '✓ Retention policy added'
\echo '  - Data older than retention period will be automatically deleted'
\echo ''

-- ============================================================================
-- Step 9: Optimize Partition Configuration
-- ============================================================================

\echo 'Optimizing partition configuration for Ignition...'

-- Disable seed queries for better performance
UPDATE sqlth_partitions 
SET flags = 1 
WHERE pname = 'sqlth_1_data';

\echo '✓ Partition flags updated'
\echo '  - Seed queries disabled for improved query performance'
\echo '  - Trade-off: No automatic interpolation at trend start'
\echo ''

-- ============================================================================
-- Step 10: Create Performance Indexes
-- ============================================================================

\echo 'Creating performance indexes...'

-- BRIN index for time-based queries (very efficient for time-series)
CREATE INDEX IF NOT EXISTS idx_sqlth_data_tstamp_brin 
ON sqlth_1_data USING BRIN (t_stamp);

\echo '✓ BRIN index created on t_stamp'

-- Composite B-tree index for tag + time queries
CREATE INDEX IF NOT EXISTS idx_sqlth_data_tagid_tstamp 
ON sqlth_1_data (tagid, t_stamp DESC);

\echo '✓ Composite index created on (tagid, t_stamp)'
\echo ''

-- ============================================================================
-- Step 11: Analyze Table
-- ============================================================================

\echo 'Analyzing table for query planner...'

ANALYZE sqlth_1_data;

\echo '✓ Table analyzed'
\echo ''

-- ============================================================================
-- Step 12: Verification and Statistics
-- ============================================================================

\echo '============================================================================'
\echo 'Configuration Summary'
\echo '============================================================================'

-- Display hypertable information
SELECT 
    hypertable_schema,
    hypertable_name,
    num_dimensions,
    num_chunks,
    compression_enabled,
    replication_factor
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'sqlth_1_data';

\echo ''
\echo 'Chunk Information:'

-- Display chunk statistics
SELECT 
    chunk_schema,
    chunk_name,
    range_start,
    range_end,
    is_compressed,
    pg_size_pretty(total_bytes) as total_size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 5;

\echo ''
\echo 'Active Policies:'

-- Display configured policies
SELECT 
    application_name as policy,
    schedule_interval,
    config,
    next_start as next_run
FROM timescaledb_information.jobs
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY application_name;

\echo ''
\echo 'Index Information:'

-- Display indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'sqlth_1_data'
ORDER BY indexname;

\echo ''
\echo '============================================================================'
\echo 'Configuration Complete!'
\echo '============================================================================'
\echo ''
\echo 'What was configured:'
\echo '  ✓ Hypertable with 24-hour chunks'
\echo '  ✓ Compression (enabled after 7 days)'
\echo '  ✓ Retention policy (10 years default)'
\echo '  ✓ Performance indexes (BRIN + Composite)'
\echo '  ✓ Partition optimization'
\echo ''
\echo 'Next Steps:'
\echo '  1. Enable tag history on tags in Ignition Designer'
\echo '  2. Wait for data to accumulate'
\echo '  3. Monitor compression and performance'
\echo '  4. Configure continuous aggregates (optional)'
\echo ''
\echo 'Monitoring Commands:'
\echo '  - Check compression: SELECT * FROM timescaledb_information.compressed_chunk_stats;'
\echo '  - Check chunks: SELECT * FROM timescaledb_information.chunks WHERE hypertable_name = ''sqlth_1_data'';'
\echo '  - Check policies: SELECT * FROM timescaledb_information.jobs;'
\echo '============================================================================'
