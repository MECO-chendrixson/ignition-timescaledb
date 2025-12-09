# Common Issues and Solutions

**Last Updated:** December 7, 2025

## Overview

This guide addresses the most common issues encountered when integrating Ignition with TimescaleDB, along with step-by-step solutions.

---

## Installation Issues

### PostgreSQL Won't Start

**Symptoms:**
- Service fails to start
- Port 5432 not listening
- Error messages in logs

**Solutions:**

1. **Check if port is already in use:**
   ```bash
   # Linux
   sudo netstat -tuln | grep 5432
   
   # Windows
   netstat -an | findstr 5432
   ```

2. **Check logs for errors:**
   ```bash
   # Linux
   sudo tail -f /var/log/postgresql/postgresql-15-main.log
   
   # Windows
   # Check: C:\Program Files\PostgreSQL\17\data\log\
   ```

3. **Verify data directory permissions:**
   ```bash
   # Linux
   sudo ls -la /var/lib/postgresql/15/main
   sudo chown -R postgres:postgres /var/lib/postgresql/15/main
   ```

4. **Check disk space:**
   ```bash
   df -h
   ```

### TimescaleDB Extension Not Available

**Symptoms:**
- `CREATE EXTENSION timescaledb` fails
- Extension not listed in `pg_available_extensions`

**Solutions:**

1. **Verify TimescaleDB is installed:**
   ```bash
   # Ubuntu
   dpkg -l | grep timescaledb
   
   # RHEL
   rpm -qa | grep timescaledb
   ```

2. **Check shared_preload_libraries:**
   ```sql
   SHOW shared_preload_libraries;
   ```
   
   Should include `timescaledb`.

3. **Edit postgresql.conf if needed:**
   ```conf
   shared_preload_libraries = 'timescaledb'
   ```
   
   Then restart PostgreSQL:
   ```bash
   sudo systemctl restart postgresql
   ```

4. **Reinstall if necessary:**
   ```bash
   # Ubuntu
   sudo apt install --reinstall timescaledb-2-postgresql-15
   sudo timescaledb-tune --quiet --yes
   sudo systemctl restart postgresql
   ```

---

## Connection Issues

### Ignition Cannot Connect to Database

**Symptoms:**
- "Connection refused" error
- "Invalid" status on database connection
- Timeout errors

**Diagnostic Steps:**

1. **Test connection from Ignition server:**
   ```bash
   psql -U ignition -h database-server -d historian -c "SELECT 1;"
   ```

2. **Check PostgreSQL is listening:**
   ```bash
   # Linux
   sudo netstat -tuln | grep 5432
   
   # Should show: 0.0.0.0:5432 or :::5432
   ```

3. **Verify pg_hba.conf allows connections:**
   ```bash
   sudo nano /etc/postgresql/15/main/pg_hba.conf
   ```
   
   Add if missing:
   ```conf
   host    all    all    0.0.0.0/0    scram-sha-256
   ```

4. **Check postgresql.conf:**
   ```conf
   listen_addresses = '*'
   ```

5. **Verify firewall:**
   ```bash
   # Linux (UFW)
   sudo ufw allow 5432/tcp
   
   # Linux (firewalld)
   sudo firewall-cmd --permanent --add-port=5432/tcp
   sudo firewall-cmd --reload
   ```

6. **Test from Ignition server:**
   ```bash
   telnet database-server 5432
   ```

**Common Fixes:**

**Wrong JDBC URL:**
```
# Correct format
jdbc:postgresql://hostname:5432/historian

# Common mistakes
jdbc:postgresql:historian  # Missing host
jdbc:postgresql://hostname/historian  # Missing port
```

**Authentication failure:**
```sql
-- Verify user exists and can login
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = 'ignition';

-- Reset password if needed
ALTER USER ignition PASSWORD 'new_password';
```

### Connection Pooling Exhausted

**Symptoms:**
- "Too many connections" error
- Database becomes unresponsive
- Ignition logs show connection timeouts

**Solutions:**

1. **Check current connections:**
   ```sql
   SELECT count(*), usename, application_name 
   FROM pg_stat_activity 
   GROUP BY usename, application_name;
   ```

2. **Increase PostgreSQL connection limit:**
   ```conf
   # Edit postgresql.conf
   max_connections = 200
   ```
   
   Restart PostgreSQL.

3. **Configure Ignition connection pooling:**
   
   In Extra Connection Properties:
   ```
   maximumPoolSize=20;minimumIdle=5;connectionTimeout=30000;
   ```

4. **Kill idle connections if needed:**
   ```sql
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE datname = 'historian'
     AND state = 'idle'
     AND state_change < now() - interval '1 hour';
   ```

---

## Data Storage Issues

### No Tables Created by Ignition

**Symptoms:**
- `sqlth_1_data` table doesn't exist
- Historian configured but no data being stored

**Diagnostic Steps:**

1. **Check historian status:**
   - Gateway → Services → Historians → Historians
   - Should show "Running"

2. **Check Gateway logs:**
   - Gateway → Status → Diagnostics → Logs
   - Filter for "historian" or "database"

3. **Verify database permissions:**
   ```sql
   -- Check user can create tables
   GRANT ALL ON SCHEMA public TO ignition;
   GRANT ALL PRIVILEGES ON DATABASE historian TO ignition;
   ```

4. **Manually test table creation:**
   ```sql
   \c historian ignition
   CREATE TABLE test (id serial primary key);
   DROP TABLE test;
   ```

**Solutions:**

1. **Restart historian:**
   - Edit historian configuration
   - Uncheck "Enabled"
   - Save
   - Re-check "Enabled"
   - Save

2. **Check Store and Forward:**
   - Config → System → Store and Forward
   - Clear any quarantined data

### Tags Not Logging Data

**Symptoms:**
- Tags have history enabled
- No rows in `sqlth_1_data`
- Power Chart shows no data

**Diagnostic Steps:**

1. **Verify tag history configuration:**
   ```python
   # In Designer Script Console
   tags = system.tag.browse("[default]YourTagPath")
   for tag in tags.getResults():
       path = tag['fullPath']
       config = system.tag.getConfiguration(path)[0]
       print path, config.get('historyEnabled')
   ```

2. **Check tag quality:**
   - Bad quality tags won't log
   - Verify tags show "Good" quality in Tag Browser

3. **Check deadband settings:**
   - If deadband too large, values may not change enough to log
   - Set deadband to 0.0 for testing

4. **Check sample mode:**
   - On Change: Only logs when value changes
   - Periodic: Logs at fixed interval
   - Tag Group: Logs per group schedule

5. **Query database directly:**
   ```sql
   SELECT COUNT(*) FROM sqlth_1_data;
   SELECT COUNT(*) FROM sqlth_te;
   SELECT COUNT(*) FROM sqlth_te WHERE retired IS NULL;
   ```

**Solutions:**

1. **Force a log:**
   ```python
   # In Script Console
   from java.util import Date
   tagPath = "[default]YourTag"
   value = 123.45
   quality = "Good"
   timestamp = Date()
   
   system.tag.storeTagHistory(tagPath, [value], [quality], [timestamp])
   ```

2. **Check Store and Forward:**
   - Config → System → Store and Forward
   - Historian storage should show "Connected"
   - Check for quarantined records

3. **Verify historian provider:**
   ```sql
   SELECT * FROM sqlth_drv;
   SELECT * FROM sqlth_te LIMIT 5;
   ```

---

## Performance Issues

### Slow Queries

**Symptoms:**
- Power Chart takes minutes to load
- Easy Chart times out
- Database CPU high

**Diagnostic Steps:**

1. **Check active queries:**
   ```sql
   SELECT pid, now() - query_start as duration, query
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY duration DESC;
   ```

2. **Check for missing indexes:**
   ```sql
   SELECT schemaname, tablename, indexname
   FROM pg_indexes
   WHERE tablename = 'sqlth_1_data';
   ```

3. **Check TimescaleDB chunks:**
   ```sql
   SELECT count(*) as chunk_count
   FROM timescaledb_information.chunks
   WHERE hypertable_name = 'sqlth_1_data';
   ```
   
   Too many chunks (>1000) can slow queries.

**Solutions:**

1. **Create BRIN index if missing:**
   ```sql
   CREATE INDEX IF NOT EXISTS idx_sqlth_data_tstamp_brin 
   ON sqlth_1_data USING BRIN (t_stamp);
   ```

2. **Create composite index:**
   ```sql
   CREATE INDEX IF NOT EXISTS idx_sqlth_data_tagid_tstamp 
   ON sqlth_1_data (tagid, t_stamp DESC);
   ```

3. **Disable seed queries:**
   ```sql
   UPDATE sqlth_partitions SET flags = 1 
   WHERE pname = 'sqlth_1_data';
   ```

4. **Enable compression:**
   ```sql
   -- If not already enabled
   ALTER TABLE sqlth_1_data SET (
       timescaledb.compress,
       timescaledb.compress_orderby = 't_stamp DESC',
       timescaledb.compress_segmentby = 'tagid'
   );
   
   SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');
   ```

5. **Use continuous aggregates:**
   - For long time ranges, query aggregates instead of raw data
   - See [Continuous Aggregates Guide](../configuration/04-continuous-aggregates.md)

### Database Size Growing Too Fast

**Symptoms:**
- Disk space filling quickly
- Database size larger than expected

**Diagnostic Steps:**

1. **Check database size:**
   ```sql
   SELECT pg_size_pretty(pg_database_size('historian'));
   ```

2. **Check table sizes:**
   ```sql
   SELECT 
       schemaname,
       tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
   FROM pg_tables
   WHERE schemaname = 'public'
   ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
   ```

3. **Check compression status:**
   ```sql
   SELECT * FROM timescaledb_information.compressed_chunk_stats;
   ```

**Solutions:**

1. **Enable compression if not active:**
   ```sql
   SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');
   ```

2. **Manually compress old chunks:**
   ```sql
   SELECT compress_chunk(i, if_not_compressed => true)
   FROM show_chunks('sqlth_1_data', older_than => (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)::BIGINT) i;
   ```

3. **Configure retention policy:**
   ```sql
   SELECT add_retention_policy('sqlth_1_data', INTERVAL '10 years');
   ```

4. **Reduce tag logging frequency:**
   - Increase deadbands
   - Change sample mode from Periodic to On Change
   - Increase tag group scan rates

---

## Hypertable Issues

### Cannot Create Hypertable

**Symptoms:**
- `create_hypertable()` fails
- Error: "table is not empty"
- Error: "table has existing indexes"

**Solutions:**

1. **If table has data, use migrate_data:**
   ```sql
   SELECT create_hypertable(
       'sqlth_1_data',
       't_stamp',
       chunk_time_interval => 86400000,
       migrate_data => TRUE  -- Important!
   );
   ```

2. **If error persists, check for constraints:**
   ```sql
   -- List constraints
   SELECT conname, contype
   FROM pg_constraint
   WHERE conrelid = 'sqlth_1_data'::regclass;
   
   -- Drop problematic constraints if safe
   ALTER TABLE sqlth_1_data DROP CONSTRAINT constraint_name;
   ```

3. **If indexes cause issues:**
   ```sql
   -- Drop indexes temporarily
   DROP INDEX IF EXISTS index_name;
   
   -- Create hypertable
   SELECT create_hypertable(...);
   
   -- Recreate indexes
   CREATE INDEX ...;
   ```

### Compression Not Working

**Symptoms:**
- Chunks not being compressed
- `compressed_chunk_stats` shows no compression
- Disk usage not decreasing

**Diagnostic Steps:**

1. **Check compression policy:**
   ```sql
   SELECT * FROM timescaledb_information.jobs
   WHERE application_name LIKE '%compression%';
   ```

2. **Check if chunks are old enough:**
   ```sql
   SELECT 
       chunk_name,
       range_end,
       is_compressed,
       now() - range_end as age
   FROM timescaledb_information.chunks
   WHERE hypertable_name = 'sqlth_1_data'
   ORDER BY range_end DESC
   LIMIT 10;
   ```

**Solutions:**

1. **Verify integer_now function:**
   ```sql
   SELECT unix_now();  -- Should return current timestamp in milliseconds
   ```

2. **Manually trigger compression:**
   ```sql
   CALL run_job(
       (SELECT job_id FROM timescaledb_information.jobs 
        WHERE application_name LIKE '%compression%' 
        AND hypertable_name = 'sqlth_1_data')
   );
   ```

3. **Compress specific chunk:**
   ```sql
   SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');
   ```

---

## Continuous Aggregate Issues

### Aggregate Not Refreshing

**Symptoms:**
- Continuous aggregate shows old data
- No new data appearing

**Solutions:**

1. **Check refresh policy:**
   ```sql
   SELECT * FROM timescaledb_information.jobs
   WHERE application_name LIKE '%refresh%';
   ```

2. **Manually refresh:**
   ```sql
   CALL refresh_continuous_aggregate('tag_history_1min', NULL, NULL);
   ```

3. **Check for errors in job:**
   ```sql
   SELECT * FROM timescaledb_information.job_stats
   WHERE job_id IN (
       SELECT job_id FROM timescaledb_information.jobs
       WHERE hypertable_name = 'tag_history_1min'
   );
   ```

### Wrong Results in Aggregates

**Symptoms:**
- Aggregate values don't match raw data
- Gaps in aggregate data

**Solutions:**

1. **Check time bucket alignment:**
   ```sql
   SELECT 
       time_bucket('1 minute', t_stamp) as minute,
       COUNT(*)
   FROM sqlth_1_data
   WHERE t_stamp >= NOW() - INTERVAL '1 hour'
   GROUP BY minute
   ORDER BY minute DESC
   LIMIT 10;
   ```

2. **Verify data quality filter:**
   - Aggregates may filter bad quality data
   - Check WHERE clause in aggregate definition

3. **Re-create aggregate if needed:**
   ```sql
   DROP MATERIALIZED VIEW tag_history_1min CASCADE;
   -- Then re-run creation script
   ```

---

## Next Steps

- Review [Performance Tuning](../optimization/01-performance-tuning.md)
- Check [Diagnostic Tools](04-diagnostic-tools.md)
- Consult [Ignition Forum](https://forum.inductiveautomation.com/)
- Review [TimescaleDB Slack](https://timescaledb.slack.com/)

**Last Updated:** December 7, 2025
