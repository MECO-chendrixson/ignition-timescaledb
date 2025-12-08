# Maintenance Scripts

**Version:** 1.3.0  
**Last Updated:** December 8, 2025

## Overview

This directory contains automated maintenance scripts for Ignition TimescaleDB historian databases. These scripts help with backup, monitoring, and cleanup operations.

---

## Available Scripts

### 1. backup_historian.sh

**Purpose:** Automated backup of TimescaleDB historian databases

**Features:**
- ✅ Backs up all three databases (historian, alarmlog, auditlog)
- ✅ Includes global objects (roles, tablespaces)
- ✅ Exports TimescaleDB metadata
- ✅ Automatic compression (gzip)
- ✅ Configurable retention period (default: 30 days)
- ✅ Automatic cleanup of old backups

**Usage:**
```bash
# Run manual backup
sudo ./backup_historian.sh

# Schedule daily backup (cron)
0 2 * * * /path/to/backup_historian.sh >> /var/log/timescaledb_backup.log 2>&1
```

**Configuration:**
Edit the script to modify:
- `BACKUP_DIR` - Backup storage location
- `RETENTION_DAYS` - How long to keep backups
- `POSTGRES_USER` - PostgreSQL user
- `COMPRESS` - Enable/disable compression

**Output:**
- Compressed database dumps: `historian_YYYYMMDD_HHMMSS.sql.dump.gz`
- Global objects: `globals_YYYYMMDD_HHMMSS.sql.gz`
- Metadata: `hypertables_YYYYMMDD_HHMMSS.csv`

---

### 2. monitor_historian.sh

**Purpose:** Comprehensive monitoring and health checks

**Features:**
- ✅ Database size and growth tracking
- ✅ Connection monitoring with alerts
- ✅ Hypertable status and chunk information
- ✅ Compression statistics and ratios
- ✅ Background job status (compression, retention, aggregates)
- ✅ Cache hit ratio analysis
- ✅ Slow query identification
- ✅ Data freshness verification
- ✅ Disk usage monitoring
- ✅ Replication lag (if configured)

**Usage:**
```bash
# Run monitoring report
./monitor_historian.sh

# Schedule hourly monitoring
0 * * * * /path/to/monitor_historian.sh >> /var/log/timescaledb_monitor.log 2>&1

# Email report
./monitor_historian.sh | mail -s "TimescaleDB Monitoring Report" admin@example.com
```

**Alert Thresholds:**
- Connection usage: 80% of max_connections
- Disk usage: 85% capacity
- Cache hit ratio: < 90%

**Output:**
Console report with color-coded status:
- 🟢 Green: Normal operation
- 🟡 Yellow: Warnings
- 🔴 Red: Alerts requiring attention

---

### 3. cleanup_historian.sh

**Purpose:** Database cleanup and maintenance operations

**Features:**
- ✅ Table bloat analysis
- ✅ VACUUM operations
- ✅ ANALYZE for query planner statistics
- ✅ Index maintenance and health checks
- ✅ Automatic chunk compression
- ✅ Continuous aggregate refresh
- ✅ Retired tag cleanup
- ✅ Log file cleanup
- ✅ Autovacuum status check

**Usage:**
```bash
# Run full cleanup (VACUUM + ANALYZE)
./cleanup_historian.sh

# Analyze only (faster, no VACUUM)
./cleanup_historian.sh --analyze-only

# Verbose VACUUM output
./cleanup_historian.sh --verbose

# Show help
./cleanup_historian.sh --help
```

**Options:**
- `-v, --verbose` - Show detailed VACUUM output
- `-a, --analyze-only` - Skip VACUUM, only update statistics
- `-h, --help` - Display help message

**Schedule:**
```bash
# Weekly cleanup (Sunday 3 AM)
0 3 * * 0 /path/to/cleanup_historian.sh >> /var/log/timescaledb_cleanup.log 2>&1

# Daily analyze only (every day 1 AM)
0 1 * * * /path/to/cleanup_historian.sh --analyze-only >> /var/log/timescaledb_analyze.log 2>&1
```

---

## Recommended Maintenance Schedule

### Daily
- ✅ Monitor database health (`monitor_historian.sh`)
- ✅ Quick ANALYZE (`cleanup_historian.sh --analyze-only`)

### Weekly
- ✅ Full backup (`backup_historian.sh`)
- ✅ Complete cleanup with VACUUM (`cleanup_historian.sh`)

### Monthly
- ✅ Review monitoring trends
- ✅ Verify backup integrity
- ✅ Check retention policy effectiveness
- ✅ Review and optimize slow queries

### Quarterly
- ✅ Database performance audit
- ✅ Compression ratio analysis
- ✅ Capacity planning review

---

## Automation with Cron

### Example crontab

```bash
# Edit crontab
crontab -e

# Add these entries:

# Daily backup at 2 AM
0 2 * * * /home/user/scripts/maintenance/backup_historian.sh >> /var/log/timescaledb_backup.log 2>&1

# Hourly monitoring
0 * * * * /home/user/scripts/maintenance/monitor_historian.sh >> /var/log/timescaledb_monitor.log 2>&1

# Daily analyze at 1 AM
0 1 * * * /home/user/scripts/maintenance/cleanup_historian.sh --analyze-only >> /var/log/timescaledb_analyze.log 2>&1

# Weekly full cleanup on Sunday at 3 AM
0 3 * * 0 /home/user/scripts/maintenance/cleanup_historian.sh >> /var/log/timescaledb_cleanup.log 2>&1
```

---

## Automation with systemd (Linux)

### Create systemd timer units

**Backup Timer:**
```ini
# /etc/systemd/system/timescaledb-backup.timer
[Unit]
Description=Daily TimescaleDB Backup

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

**Backup Service:**
```ini
# /etc/systemd/system/timescaledb-backup.service
[Unit]
Description=TimescaleDB Backup Service

[Service]
Type=oneshot
ExecStart=/path/to/backup_historian.sh
User=postgres
```

**Enable and start:**
```bash
sudo systemctl enable timescaledb-backup.timer
sudo systemctl start timescaledb-backup.timer
sudo systemctl status timescaledb-backup.timer
```

---

## Windows Task Scheduler

### Create Scheduled Task

1. Open Task Scheduler
2. Create Task → General tab:
   - Name: "TimescaleDB Backup"
   - Run with highest privileges
3. Triggers tab:
   - New → Daily at 2:00 AM
4. Actions tab:
   - Program: `bash.exe`
   - Arguments: `/c/path/to/backup_historian.sh`
5. Settings:
   - Stop task if runs > 2 hours
   - Run as soon as possible after missed

---

## Monitoring Integration

### Grafana Dashboard

Create dashboard with these metrics:
- Database size over time
- Compression ratio trends
- Query performance (95th percentile)
- Connection count
- Cache hit ratio
- Chunk creation rate

### Alerting

Configure alerts for:
- Database size > 80% capacity
- Cache hit ratio < 90%
- Connection usage > 80%
- Failed backup jobs
- Compression policy failures

---

## Troubleshooting

### Backup Fails

**Symptom:** backup_historian.sh returns error

**Check:**
```bash
# Verify PostgreSQL is running
systemctl status postgresql

# Check disk space
df -h /var/backups/timescaledb

# Test pg_dump manually
pg_dump -U postgres -d historian -F c -f /tmp/test.dump
```

### Monitor Shows High Memory Usage

**Solution:**
```bash
# Adjust shared_buffers in postgresql.conf
shared_buffers = 4GB  # 25% of total RAM

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Cleanup Takes Too Long

**Solution:**
```bash
# Use --analyze-only for daily runs
./cleanup_historian.sh --analyze-only

# Full VACUUM only weekly
```

---

## Prerequisites

### Required Permissions

Scripts must run as user with:
- PostgreSQL superuser or database owner privileges
- Read/write access to backup directory
- Read access to PostgreSQL log directory

### Required Tools

- `bash` (version 4.0+)
- `psql` (PostgreSQL client)
- `pg_dump` and `pg_dumpall`
- `gzip` (for compression)
- `bc` (for calculations)

**Install on Ubuntu/Debian:**
```bash
sudo apt-get install postgresql-client gzip bc
```

**Install on RHEL/CentOS:**
```bash
sudo yum install postgresql gzip bc
```

---

## Security Considerations

### Backup Security

✅ Store backups on separate disk/server  
✅ Encrypt backups for sensitive data  
✅ Restrict backup directory permissions (700)  
✅ Use `.pgpass` file for password management  

**Example .pgpass:**
```
localhost:5432:*:postgres:your_secure_password
```

```bash
chmod 600 ~/.pgpass
```

### Script Permissions

```bash
# Make scripts executable
chmod 755 *.sh

# Restrict to owner only for sensitive configs
chmod 700 backup_historian.sh
```

---

## Additional Resources

- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [TimescaleDB Maintenance](https://docs.timescale.com/use-timescale/latest/maintenance/)
- [Monitoring Best Practices](../docs/reference/04-best-practices.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
