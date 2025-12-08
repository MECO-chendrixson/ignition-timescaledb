#!/bin/bash
################################################################################
# Ignition TimescaleDB Historian Backup Script
################################################################################
# Description: Comprehensive backup script for TimescaleDB historian databases
# Version: 1.3.0
# Last Updated: 2025-12-08
# Maintained by: Miller-Eads Automation
################################################################################

set -euo pipefail

# Configuration
BACKUP_DIR="/var/backups/timescaledb"
RETENTION_DAYS=30
POSTGRES_USER="postgres"
DATABASES=("historian" "alarmlog" "auditlog")
COMPRESS=true
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

log_info "Starting TimescaleDB historian backup - $TIMESTAMP"
log_info "Backup directory: $BACKUP_DIR"

# Backup each database
for DB in "${DATABASES[@]}"; do
    log_info "Backing up database: $DB"
    
    BACKUP_FILE="$BACKUP_DIR/${DB}_${TIMESTAMP}.sql"
    
    # Perform backup
    if pg_dump -U "$POSTGRES_USER" -d "$DB" -F c -f "$BACKUP_FILE.dump"; then
        log_info "✓ Database $DB backed up successfully"
        
        # Compress if enabled
        if [ "$COMPRESS" = true ]; then
            log_info "Compressing backup..."
            gzip "$BACKUP_FILE.dump"
            log_info "✓ Backup compressed: ${BACKUP_FILE}.dump.gz"
        fi
    else
        log_error "✗ Failed to backup database: $DB"
        exit 1
    fi
done

# Also backup global objects (roles, tablespaces, etc.)
log_info "Backing up global objects (roles, tablespaces)..."
if pg_dumpall -U "$POSTGRES_USER" -g -f "$BACKUP_DIR/globals_${TIMESTAMP}.sql"; then
    log_info "✓ Global objects backed up successfully"
    if [ "$COMPRESS" = true ]; then
        gzip "$BACKUP_DIR/globals_${TIMESTAMP}.sql"
    fi
else
    log_error "✗ Failed to backup global objects"
fi

# Backup TimescaleDB metadata
log_info "Backing up TimescaleDB metadata..."
psql -U "$POSTGRES_USER" -d historian -c "\COPY (SELECT * FROM timescaledb_information.hypertables) TO '$BACKUP_DIR/hypertables_${TIMESTAMP}.csv' WITH CSV HEADER;" 2>/dev/null || log_warn "Could not backup hypertable metadata"
psql -U "$POSTGRES_USER" -d historian -c "\COPY (SELECT * FROM timescaledb_information.continuous_aggregates) TO '$BACKUP_DIR/caggs_${TIMESTAMP}.csv' WITH CSV HEADER;" 2>/dev/null || log_warn "Could not backup continuous aggregate metadata"

# Clean up old backups
log_info "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.dump.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.csv" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log_info "Total backup directory size: $BACKUP_SIZE"

# List today's backups
log_info "Backups created today:"
ls -lh "$BACKUP_DIR" | grep "$TIMESTAMP" || echo "No backups found for current timestamp"

log_info "Backup completed successfully!"

# Exit with success
exit 0
