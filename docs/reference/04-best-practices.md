# Best Practices

**Last Updated:** December 8, 2025  
**Difficulty:** Reference

## Overview

Consolidated best practices for TimescaleDB with Ignition SCADA historian.

---

## Schema Design

### Hypertable Configuration

✅ **DO:**
- Use 24-hour chunks for standard workloads
- Enable compression after 7 days
- Set retention policies appropriate for compliance
- Use BRIN indexes on timestamp columns
- Disable Ignition partitioning when using TimescaleDB

❌ **DON'T:**
- Don't enable both Ignition AND TimescaleDB partitioning
- Don't make chunks too small (<10MB) or too large (>1GB)
- Don't compress data that needs frequent updates
- Don't skip the integer now function setup

---

## Compression

### Configuration

✅ **DO:**
- Segment by tagid for tag-specific queries
- Order by t_stamp DESC for recent data access
- Compress after data stabilizes (7-14 days)
- Monitor compression ratios (target: 10x+)
- Use compression policies for automation

❌ **DON'T:**
- Don't compress recent data (<7 days)
- Don't use too many segment_by columns (max 3)
- Don't skip compression (wastes 90% storage)

---

## Query Optimization

### Performance

✅ **DO:**
- Always filter on t_stamp first
- Use time_bucket for aggregations
- Use continuous aggregates for historical queries
- Select only needed columns
- Use prepared statements
- Cache tagid lookups

❌ **DON'T:**
- Don't use SELECT *
- Don't use functions on indexed columns in WHERE
- Don't use OR for multiple values (use IN/ANY)
- Don't aggregate raw data for historical queries

---

## Maintenance

### Regular Tasks

**Daily:**
- Monitor database size
- Check compression status
- Verify data freshness
- Review slow queries

**Weekly:**
- Run ANALYZE on main tables
- Check autovacuum status
- Review retention policy execution
- Backup databases

**Monthly:**
- VACUUM metadata tables
- Review and optimize indexes
- Capacity planning review
- Check for unused indexes

---

## Security

### Access Control

✅ **DO:**
- Use least privilege principle
- Separate users for read vs write
- Enable SSL/TLS connections
- Use .pgpass for password management
- Regular password rotation

```sql
-- Create read-only user
CREATE ROLE reporter LOGIN PASSWORD 'secure_pass';
GRANT CONNECT ON DATABASE historian TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporter;
```

---

## Backup and Recovery

### Strategy

✅ **3-2-1 Rule:**
- 3 copies of data
- 2 different storage types
- 1 off-site backup

**Automated backups:**
```bash
# Daily backup script
0 2 * * * /path/to/scripts/maintenance/backup_historian.sh
```

---

## Monitoring

### Key Metrics

Track these metrics:
- Database size and growth rate
- Compression ratio
- Cache hit ratio (>99%)
- Query performance (p95, p99)
- Connection count
- Replication lag (if applicable)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
