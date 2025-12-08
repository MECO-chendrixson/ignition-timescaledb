#!/bin/bash
################################################################################
# Ignition TimescaleDB Historian Monitoring Script
################################################################################
# Description: Monitor database health, performance, and resource usage
# Version: 1.3.0
# Last Updated: 2025-12-08
# Maintained by: Miller-Eads Automation
################################################################################

set -euo pipefail

# Configuration
POSTGRES_USER="postgres"
DATABASE="historian"
ALERT_THRESHOLD_CONNECTIONS=80  # Alert if > 80% of max connections
ALERT_THRESHOLD_DISK=85         # Alert if > 85% disk usage
ALERT_THRESHOLD_CACHE_HIT=90    # Alert if < 90% cache hit ratio

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    echo -e "\n${YELLOW}▶ $1${NC}\n"
}

alert() {
    echo -e "${RED}⚠ ALERT: $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Start monitoring
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  TimescaleDB Historian Monitoring Report                        ║${NC}"
echo -e "${BLUE}║  $(date '+%Y-%m-%d %H:%M:%S')                                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"

# 1. Database Size and Growth
print_header "DATABASE SIZE & GROWTH"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    'historian' as database,
    pg_size_pretty(pg_database_size('historian')) as size,
    (SELECT COUNT(*) FROM sqlth_1_data) as total_records,
    pg_size_pretty(pg_total_relation_size('sqlth_1_data')) as data_table_size
\gx
EOSQL

# 2. Connection Status
print_section "Connection Status"

CONN_INFO=$(psql -U "$POSTGRES_USER" -t -A -F',' -d postgres -c "
SELECT 
    (SELECT count(*) FROM pg_stat_activity WHERE datname = 'historian') as active,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max
")

ACTIVE_CONN=$(echo "$CONN_INFO" | cut -d',' -f1)
MAX_CONN=$(echo "$CONN_INFO" | cut -d',' -f2)
CONN_PCT=$((ACTIVE_CONN * 100 / MAX_CONN))

echo "Active connections: $ACTIVE_CONN / $MAX_CONN ($CONN_PCT%)"

if [ "$CONN_PCT" -gt "$ALERT_THRESHOLD_CONNECTIONS" ]; then
    alert "Connection usage above ${ALERT_THRESHOLD_CONNECTIONS}%"
else
    success "Connection usage normal"
fi

# 3. Hypertable Status
print_section "Hypertable Status"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    hypertable_name,
    num_chunks,
    compression_enabled,
    pg_size_pretty(total_bytes) as total_size
FROM timescaledb_information.hypertables
ORDER BY hypertable_name;
EOSQL

# 4. Compression Statistics
print_section "Compression Statistics"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    hypertable_name,
    COUNT(*) as compressed_chunks,
    pg_size_pretty(SUM(before_compression_total_bytes)) as uncompressed_size,
    pg_size_pretty(SUM(after_compression_total_bytes)) as compressed_size,
    ROUND(
        AVG(before_compression_total_bytes::numeric / 
            NULLIF(after_compression_total_bytes, 0))::numeric, 
        2
    ) as avg_compression_ratio
FROM timescaledb_information.compressed_chunk_stats
WHERE hypertable_name = 'sqlth_1_data'
GROUP BY hypertable_name;
EOSQL

# 5. Background Jobs Status
print_section "Background Jobs Status"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    job_id,
    application_name,
    last_run_status,
    last_run_started_at,
    next_start,
    total_successes,
    total_failures
FROM timescaledb_information.job_stats
WHERE job_id IN (
    SELECT job_id FROM timescaledb_information.jobs
    WHERE hypertable_name = 'sqlth_1_data'
)
ORDER BY job_id;
EOSQL

# 6. Cache Hit Ratio
print_section "Cache Performance"

CACHE_HIT=$(psql -U "$POSTGRES_USER" -d "$DATABASE" -t -A -c "
SELECT 
    ROUND(
        100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0),
        2
    )
FROM pg_stat_database
WHERE datname = 'historian'
")

echo "Cache hit ratio: ${CACHE_HIT}%"

if (( $(echo "$CACHE_HIT < $ALERT_THRESHOLD_CACHE_HIT" | bc -l) )); then
    alert "Cache hit ratio below ${ALERT_THRESHOLD_CACHE_HIT}%"
else
    success "Cache hit ratio healthy"
fi

# 7. Slow Queries (if pg_stat_statements is enabled)
print_section "Slowest Queries (Top 5)"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL' 2>/dev/null || echo "pg_stat_statements not available"
SELECT 
    LEFT(query, 60) as query_snippet,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_ms,
    ROUND(total_exec_time::numeric, 2) as total_ms
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'historian')
ORDER BY mean_exec_time DESC
LIMIT 5;
EOSQL

# 8. Data Freshness
print_section "Data Freshness"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL'
SELECT 
    'historian' as database,
    to_timestamp(MAX(t_stamp)/1000) as latest_data,
    NOW() - to_timestamp(MAX(t_stamp)/1000) as data_age,
    COUNT(DISTINCT tagid) as active_tags
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '5 minutes') * 1000);
EOSQL

# 9. Disk Usage
print_section "Disk Usage"

df -h $(psql -U "$POSTGRES_USER" -t -A -c "SHOW data_directory") | tail -1 | awk '{
    usage=$5
    gsub(/%/, "", usage)
    if (usage > 85) {
        print $0 " ⚠ ALERT: Disk usage > 85%"
    } else {
        print $0 " ✓ Normal"
    }
}'

# 10. Replication Lag (if replication is configured)
print_section "Replication Status"

psql -U "$POSTGRES_USER" -d "$DATABASE" << 'EOSQL' 2>/dev/null || echo "No replication configured"
SELECT 
    client_addr,
    state,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) as send_lag,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) as replay_lag
FROM pg_stat_replication;
EOSQL

# Summary
echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Monitoring report completed at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}\n"

exit 0
