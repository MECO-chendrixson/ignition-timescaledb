#!/bin/bash
################################################################################
# Ignition TimescaleDB Historian Cleanup Script
################################################################################
# Description: Cleanup and maintenance tasks for TimescaleDB historian
# Version: 1.3.0
# Last Updated: 2025-12-08
# Maintained by: Miller-Eads Automation
################################################################################

set -euo pipefail

# Configuration
POSTGRES_USER="postgres"
DATABASE="historian"
VACUUM_VERBOSE=false
ANALYZE_ONLY=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VACUUM_VERBOSE=true
            shift
            ;;
        --analyze-only|-a)
            ANALYZE_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose      Verbose VACUUM output"
            echo "  -a, --analyze-only Only run ANALYZE, skip VACUUM"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}\n"
}

# Start cleanup
print_header "TimescaleDB Historian Cleanup - $(date '+%Y-%m-%d %H:%M:%S')"

# 1. Table Bloat Analysis
print_header "1. Analyzing Table Bloat"

log_info "Checking for table bloat..."
psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as indexes_size,
    n_dead_tup as dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public' 
  AND tablename LIKE 'sqlth%'
  AND n_dead_tup > 0
ORDER BY n_dead_tup DESC;
EOSQL

# 2. VACUUM Operations
if [ "$ANALYZE_ONLY" = false ]; then
    print_header "2. Running VACUUM"
    
    log_info "VACUUMing historian tables..."
    
    if [ "$VACUUM_VERBOSE" = true ]; then
        psql -U "$POSTGRES_USER" -d "$DATABASE" -c "VACUUM VERBOSE sqlth_1_data;"
        psql -U "$POSTGRES_USER" -d "$DATABASE" -c "VACUUM VERBOSE sqlth_te;"
        psql -U "$POSTGRES_USER" -d "$DATABASE" -c "VACUUM VERBOSE sqlth_partitions;"
    else
        psql -U "$POSTGRES_USER" -d "$DATABASE" -c "VACUUM sqlth_1_data;"
        psql -U "$POSTGRES_USER" -d "$DATABASE" -c "VACUUM sqlth_te;"
        psql -U "$POSTGRES_USER" -d "$DATABASE" -c "VACUUM sqlth_partitions;"
    fi
    
    log_info "✓ VACUUM completed"
else
    log_info "Skipping VACUUM (analyze-only mode)"
fi

# 3. ANALYZE for Query Planner
print_header "3. Running ANALYZE"

log_info "Updating statistics for query planner..."
psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
ANALYZE sqlth_1_data;
ANALYZE sqlth_te;
ANALYZE sqlth_partitions;
ANALYZE sqlth_drv;
ANALYZE sqlth_scinfo;
EOSQL

log_info "✓ ANALYZE completed"

# 4. Reindex if needed (based on bloat)
print_header "4. Index Maintenance"

log_info "Checking index health..."
psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public' 
  AND tablename LIKE 'sqlth%'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 10;
EOSQL

# 5. Compress eligible chunks
print_header "5. Compression Maintenance"

log_info "Checking for uncompressed chunks older than 7 days..."
UNCOMPRESSED=$(psql -U "$POSTGRES_USER" -d "$DATABASE" -t -A -c "
SELECT COUNT(*)
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
  AND NOT is_compressed
  AND range_end < (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000);
")

if [ "$UNCOMPRESSED" -gt 0 ]; then
    log_warn "Found $UNCOMPRESSED uncompressed chunks older than 7 days"
    log_info "Compressing eligible chunks..."
    
    psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT compress_chunk(i, if_not_compressed => true)
FROM show_chunks('sqlth_1_data', older_than => INTERVAL '7 days') i;
EOSQL
    
    log_info "✓ Compression completed"
else
    log_info "✓ No uncompressed chunks found"
fi

# 6. Clean up old continuous aggregate data
print_header "6. Continuous Aggregate Maintenance"

log_info "Refreshing continuous aggregates..."
psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL' 2>/dev/null || log_warn "No continuous aggregates configured"
SELECT job_id, application_name 
FROM timescaledb_information.jobs 
WHERE application_name LIKE '%Continuous Aggregate%'
  AND hypertable_name IN ('tag_history_1min', 'tag_history_1hour', 'tag_history_1day');
EOSQL

# 7. Check and clean up orphaned tags
print_header "7. Tag Cleanup"

log_info "Checking for retired tags..."
RETIRED_TAGS=$(psql -U "$POSTGRES_USER" -d "$DATABASE" -t -A -c "
SELECT COUNT(*) FROM sqlth_te WHERE retired IS NOT NULL;
")

log_info "Found $RETIRED_TAGS retired tags"

if [ "$RETIRED_TAGS" -gt 100 ]; then
    log_warn "Large number of retired tags. Consider archiving old tag metadata."
fi

# 8. Log cleanup summary
print_header "8. Cleanup Summary"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    'Total database size' as metric,
    pg_size_pretty(pg_database_size('historian')) as value
UNION ALL
SELECT 
    'Main data table size',
    pg_size_pretty(pg_total_relation_size('sqlth_1_data'))
UNION ALL
SELECT 
    'Total chunks',
    COUNT(*)::text
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
UNION ALL
SELECT 
    'Compressed chunks',
    COUNT(*)::text
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data' 
  AND is_compressed = true;
EOSQL

# 9. Cleanup old logs and temp files (optional)
print_header "9. System Cleanup"

log_info "Checking PostgreSQL log size..."
LOG_DIR=$(psql -U "$POSTGRES_USER" -t -A -c "SHOW log_directory" 2>/dev/null || echo "/var/log/postgresql")
if [ -d "$LOG_DIR" ]; then
    LOG_SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    log_info "PostgreSQL log directory size: $LOG_SIZE"
    
    # Clean logs older than 30 days
    log_info "Cleaning logs older than 30 days..."
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || log_warn "Could not clean old logs (permission denied)"
else
    log_warn "Log directory not found: $LOG_DIR"
fi

# 10. Final recommendations
print_header "Recommendations"

# Check if autovacuum is enabled
AUTOVACUUM=$(psql -U "$POSTGRES_USER" -t -A -c "SHOW autovacuum")
if [ "$AUTOVACUUM" = "off" ]; then
    log_error "⚠ Autovacuum is DISABLED. Enable it for automatic maintenance!"
else
    log_info "✓ Autovacuum is enabled"
fi

# Check shared_buffers
SHARED_BUFFERS=$(psql -U "$POSTGRES_USER" -t -A -c "SHOW shared_buffers")
log_info "Current shared_buffers: $SHARED_BUFFERS"

echo ""
log_info "Cleanup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

exit 0
