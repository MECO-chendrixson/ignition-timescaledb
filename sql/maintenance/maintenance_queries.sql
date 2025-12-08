-- ============================================================================
-- Maintenance Queries for TimescaleDB Historian
-- ============================================================================
-- Description: Database maintenance and monitoring queries
-- Version: 1.3.0
-- Last Updated: 2025-12-08
-- ============================================================================

-- =============================================================================
-- DATABASE HEALTH CHECKS
-- =============================================================================

-- Query 1: Database Size Overview
SELECT 
    'historian' as database,
    pg_size_pretty(pg_database_size('historian')) as total_size,
    (SELECT COUNT(*) FROM sqlth_1_data) as total_records,
    pg_size_pretty(pg_total_relation_size('sqlth_1_data')) as data_table_size,
    pg_size_pretty(pg_indexes_size('sqlth_1_data')) as indexes_size;

-- Query 2: Table Bloat Analysis
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    n_dead_tup as dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public' 
  AND tablename LIKE 'sqlth%'
ORDER BY n_dead_tup DESC;

-- Query 3: Connection Status
SELECT 
    datname as database,
    usename as user,
    state,
    COUNT(*) as connections
FROM pg_stat_activity
WHERE datname IN ('historian', 'alarmlog', 'auditlog')
GROUP BY datname, usename, state
ORDER BY datname, connections DESC;

-- =============================================================================
-- TIMESCALEDB SPECIFIC
-- =============================================================================

-- Query 4: Hypertable Overview
SELECT 
    hypertable_schema,
    hypertable_name,
    num_dimensions,
    num_chunks,
    compression_enabled,
    pg_size_pretty(total_bytes) as total_size
FROM timescaledb_information.hypertables
ORDER BY total_bytes DESC;

-- Query 5: Chunk Status
SELECT 
    hypertable_name,
    COUNT(*) as total_chunks,
    COUNT(*) FILTER (WHERE is_compressed) as compressed_chunks,
    COUNT(*) FILTER (WHERE NOT is_compressed) as uncompressed_chunks,
    pg_size_pretty(SUM(total_bytes)) as total_size,
    pg_size_pretty(SUM(total_bytes) FILTER (WHERE is_compressed)) as compressed_size,
    pg_size_pretty(SUM(total_bytes) FILTER (WHERE NOT is_compressed)) as uncompressed_size
FROM timescaledb_information.chunks
GROUP BY hypertable_name;

-- Query 6: Compression Statistics
SELECT 
    hypertable_name,
    chunk_name,
    pg_size_pretty(before_compression_total_bytes) as before_size,
    pg_size_pretty(after_compression_total_bytes) as after_size,
    ROUND(
        before_compression_total_bytes::numeric / 
        NULLIF(after_compression_total_bytes, 0),
        2
    ) as compression_ratio
FROM timescaledb_information.compressed_chunk_stats
WHERE hypertable_name = 'sqlth_1_data'
ORDER BY range_start DESC
LIMIT 10;

-- Query 7: Background Jobs Status
SELECT 
    job_id,
    application_name,
    schedule_interval,
    last_run_started_at,
    last_run_status,
    next_start,
    total_runs,
    total_successes,
    total_failures
FROM timescaledb_information.job_stats
WHERE job_id IN (
    SELECT job_id FROM timescaledb_information.jobs
    WHERE hypertable_name = 'sqlth_1_data'
)
ORDER BY job_id;

-- =============================================================================
-- PERFORMANCE MONITORING
-- =============================================================================

-- Query 8: Cache Hit Ratio
SELECT 
    'historian' as database,
    ROUND(
        100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0),
        2
    ) as cache_hit_ratio,
    CASE 
        WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) >= 99 
            THEN 'Excellent'
        WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) >= 95 
            THEN 'Good'
        WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) >= 90 
            THEN 'Fair'
        ELSE 'Poor - Increase shared_buffers'
    END as status
FROM pg_stat_database
WHERE datname = 'historian';

-- Query 9: Index Usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public' 
  AND tablename LIKE 'sqlth%'
ORDER BY idx_scan DESC;

-- Query 10: Table Access Statistics
SELECT 
    schemaname,
    tablename,
    seq_scan as sequential_scans,
    seq_tup_read as seq_tuples_read,
    idx_scan as index_scans,
    idx_tup_fetch as idx_tuples_fetched,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes
FROM pg_stat_user_tables
WHERE schemaname = 'public' 
  AND tablename LIKE 'sqlth%'
ORDER BY seq_scan + idx_scan DESC;

-- =============================================================================
-- DATA INTEGRITY
-- =============================================================================

-- Query 11: Duplicate Detection
SELECT 
    tagid,
    t_stamp,
    COUNT(*) as duplicate_count
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY tagid, t_stamp
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- Query 12: Data Freshness Check
SELECT 
    'historian' as database,
    to_timestamp(MAX(t_stamp)/1000) as latest_data,
    NOW() - to_timestamp(MAX(t_stamp)/1000) as data_age,
    CASE 
        WHEN NOW() - to_timestamp(MAX(t_stamp)/1000) < INTERVAL '5 minutes' 
            THEN 'Current'
        WHEN NOW() - to_timestamp(MAX(t_stamp)/1000) < INTERVAL '1 hour' 
            THEN 'Recent'
        ELSE 'Stale - Check Ignition'
    END as status,
    COUNT(DISTINCT tagid) as active_tags
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '5 minutes') * 1000);

-- Query 13: Quality Code Distribution
SELECT 
    dataintegrity as quality_code,
    CASE dataintegrity
        WHEN 192 THEN 'Good'
        WHEN 0 THEN 'Bad'
        WHEN 8 THEN 'Bad_OutOfRange'
        WHEN 64 THEN 'Bad_Stale'
        ELSE 'Other'
    END as quality_name,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY dataintegrity
ORDER BY count DESC;

-- =============================================================================
-- VACUUM & ANALYZE
-- =============================================================================

-- Query 14: VACUUM Status
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count,
    last_analyze,
    last_autoanalyze,
    analyze_count,
    autoanalyze_count
FROM pg_stat_user_tables
WHERE schemaname = 'public' 
  AND tablename LIKE 'sqlth%'
ORDER BY tablename;

-- Query 15: Tables Needing VACUUM
SELECT 
    schemaname,
    tablename,
    n_dead_tup as dead_tuples,
    n_live_tup as live_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as table_size,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND n_dead_tup > 1000
  AND ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 5
ORDER BY n_dead_tup DESC;

-- =============================================================================
-- CHUNK MANAGEMENT
-- =============================================================================

-- Query 16: Chunks Eligible for Compression
SELECT 
    chunk_schema || '.' || chunk_name as chunk,
    to_timestamp(range_start/1000) as chunk_start,
    to_timestamp(range_end/1000) as chunk_end,
    pg_size_pretty(total_bytes) as size,
    is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
  AND NOT is_compressed
  AND range_end < (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
ORDER BY range_start DESC;

-- Query 17: Chunks Eligible for Retention Deletion
SELECT 
    chunk_schema || '.' || chunk_name as chunk,
    to_timestamp(range_start/1000) as chunk_start,
    to_timestamp(range_end/1000) as chunk_end,
    NOW() - to_timestamp(range_end/1000) as age,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
  AND range_end < (EXTRACT(EPOCH FROM NOW() - INTERVAL '10 years') * 1000)
ORDER BY range_start;

-- =============================================================================
-- CONTINUOUS AGGREGATES
-- =============================================================================

-- Query 18: Continuous Aggregate Status
SELECT 
    view_name,
    materialization_hypertable_schema || '.' || materialization_hypertable_name as materialized_table,
    refresh_lag,
    compression_enabled,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.continuous_aggregates;

-- Query 19: Continuous Aggregate Refresh Status
SELECT 
    job_id,
    application_name,
    hypertable_name,
    last_run_started_at,
    last_run_status,
    next_start,
    total_runs,
    total_failures
FROM timescaledb_information.job_stats
WHERE application_name LIKE '%Continuous Aggregate%'
ORDER BY hypertable_name;

-- =============================================================================
-- QUICK FIX COMMANDS
-- =============================================================================

-- Command 1: Manual VACUUM (run separately)
-- VACUUM VERBOSE sqlth_1_data;

-- Command 2: Manual ANALYZE (run separately)
-- ANALYZE sqlth_1_data;

-- Command 3: Reindex if needed (run separately)
-- REINDEX TABLE sqlth_1_data;

-- Command 4: Compress specific chunk (run separately, replace chunk name)
-- SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Command 5: Decompress specific chunk if needed (run separately)
-- SELECT decompress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Command 6: Drop old chunks manually (run separately, CAUTION: deletes data)
-- SELECT drop_chunks('sqlth_1_data', older_than => INTERVAL '11 years');

-- ============================================================================
-- END OF MAINTENANCE QUERIES
-- ============================================================================
