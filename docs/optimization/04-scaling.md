# Scaling Strategies

**Last Updated:** December 8, 2025  
**Difficulty:** Advanced  
**Estimated Time:** 2-3 hours  
**Prerequisites:** Production TimescaleDB deployment, understanding of replication

## Overview

This guide covers vertical and horizontal scaling strategies for TimescaleDB with Ignition historian workloads as data volume and query load grow.

## Vertical Scaling (Scale Up)

### Hardware Upgrades

**CPU:**
- More cores for parallel queries
- Higher clock speed for single-threaded operations
- Recommended: 16+ cores for production

**Memory:**
- Increase shared_buffers (25% of RAM)
- More RAM for caching hot data
- Recommended: 64GB+ for medium installations, 256GB+ for large

**Storage:**
- Upgrade to NVMe SSDs
- RAID 10 for redundancy and performance
- Recommended: 4TB+ usable space

### PostgreSQL Configuration for Large Systems

```conf
# For 128GB RAM system
shared_buffers = 32GB
effective_cache_size = 96GB
work_mem = 256MB
maintenance_work_mem = 4GB
max_connections = 500
max_parallel_workers = 16
```

## Horizontal Scaling (Scale Out)

### Read Replicas

Setup streaming replication for read scaling:

```bash
# On primary server
# Edit postgresql.conf
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on

# Create replication user
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'secure_password';
```

**On replica:**
```bash
# Stop PostgreSQL
pg_basebackup -h primary_host -D /var/lib/postgresql/15/main -U replicator -P -v

# Create standby.signal
touch /var/lib/postgresql/15/main/standby.signal

# Start replica
```

### Load Balancing with PgBouncer

Route reads to replicas, writes to primary:

```ini
[databases]
historian_write = host=primary port=5432 dbname=historian
historian_read = host=replica1,replica2 port=5432 dbname=historian

[pgbouncer]
pool_mode = transaction
default_pool_size = 25
max_client_conn = 1000
```

### Multi-Node TimescaleDB (Distributed Hypertables)

For extreme scale (10TB+ datasets):

```sql
-- Add data nodes
SELECT add_data_node('node1', host => 'node1.example.com');
SELECT add_data_node('node2', host => 'node2.example.com');

-- Create distributed hypertable
SELECT create_distributed_hypertable('sqlth_1_data', 't_stamp', 'tagid',
    number_partitions => 4);
```

## Capacity Planning

### Calculate Growth Rate

```sql
-- Storage growth per day
WITH daily_size AS (
    SELECT 
        DATE(timestamp) as day,
        SUM(pg_total_relation_size('sqlth_1_data')) as size
    FROM storage_metrics
    WHERE DATE(timestamp) >= CURRENT_DATE - 30
    GROUP BY day
)
SELECT 
    AVG(size - LAG(size) OVER (ORDER BY day)) as avg_daily_growth_bytes,
    pg_size_pretty(AVG(size - LAG(size) OVER (ORDER BY day))) as avg_daily_growth
FROM daily_size;
```

### Project Future Needs

```python
# Python capacity planning
current_size_gb = 500
daily_growth_gb = 5
retention_days = 365

projected_size = current_size_gb + (daily_growth_gb * retention_days)
print(f"Projected size in 1 year: {projected_size}GB")
```

## High Availability

### Patroni Setup

Automatic failover cluster:

```yaml
# patroni.yml
scope: postgres-cluster
namespace: /db/
name: node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: node1:8008

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576

postgresql:
  listen: 0.0.0.0:5432
  connect_address: node1:5432
  data_dir: /var/lib/postgresql/15/main
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: secure_pass
    superuser:
      username: postgres
      password: secure_pass
```

## Best Practices

✅ Start with vertical scaling (simpler)
✅ Use read replicas for dashboards
✅ Implement connection pooling
✅ Monitor replication lag
✅ Test failover procedures
✅ Plan for 2x current capacity

❌ Don't over-provision initially
❌ Don't ignore replication lag
❌ Don't skip disaster recovery testing

## Next Steps

- [Performance Tuning](01-performance-tuning.md)
- [Storage Optimization](03-storage-optimization.md)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
