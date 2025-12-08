# Retention Policies

**Last Updated:** December 8, 2025  
**Difficulty:** Beginner  
**Estimated Time:** 10-15 minutes  
**Prerequisites:** 
- Hypertable created and configured
- Understanding of data retention requirements
- Compression enabled (recommended)

## Overview

Retention policies automatically delete old data from your hypertables, managing the data lifecycle without manual intervention. This guide covers configuring, monitoring, and managing retention policies for Ignition historian data.

---

## Why Retention Policies Matter

### Automatic Data Lifecycle Management

**Without Retention Policies:**
- Manual deletion required
- Risk of running out of disk space
- Difficult to enforce compliance requirements
- Inconsistent data management

**With Retention Policies:**
- Automatic deletion of old data
- Predictable storage usage
- Compliance enforcement (e.g., GDPR, data retention laws)
- Set it and forget it

### Storage Planning

```
Example: 1000 tags at 1-second scan rate
- Daily data: ~85 GB uncompressed
- With compression (15x): ~5.7 GB/day
- 1 year retention: ~2 TB
- 10 year retention: ~20 TB
```

---

## Understanding Retention Policies

### How They Work

```
Timeline:
│
├─ NOW ──────────────────────────────────┤
│                                         │
│  ← Retention Interval (e.g., 10 years) │
│                                         │
├─ Deletion Point ───────────────────────┤
│                                         │
│  ← Data older than this gets deleted   │
│                                         │
└─ Historical Data ──────────────────────┘
```

### Retention vs. Compression

These work together:

| Age | Compression | Retention |
|-----|-------------|-----------|
| 0-7 days | Uncompressed | Keep |
| 7 days - 10 years | Compressed | Keep |
| > 10 years | N/A | **Deleted** |

**Important:** Data is deleted permanently. Compress data before it reaches retention age to maximize storage efficiency.

---

## Common Retention Strategies

### Strategy 1: Standard Industrial (Recommended)

**Characteristics:**
- General manufacturing data
- Long-term trending
- No specific regulatory requirements

**Configuration:**
```sql
-- 10 year retention
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');
```

**Reasoning:**
- Sufficient for long-term analysis
- Machine lifecycle typically 10-20 years
- Balances storage cost vs. data value

### Strategy 2: Regulatory Compliance

**Characteristics:**
- FDA 21 CFR Part 11
- GMP/GLP requirements
- ISO quality standards

**Configuration:**
```sql
-- 7 year retention (common FDA requirement)
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '220752000000');

-- Or specific date-based retention
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '220723200000'); -- Exactly 7 years
```

**Reasoning:**
- Meets FDA electronic records requirements
- Pharmaceutical industry standard
- Medical device compliance

### Strategy 3: GDPR / Data Privacy

**Characteristics:**
- Personal data retention limits
- Right to be forgotten
- EU data protection

**Configuration:**
```sql
-- 2 year retention (common GDPR interpretation)
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '63072000000');
```

**Reasoning:**
- Minimizes data exposure
- Reduces compliance risk
- Balances operational needs with privacy

### Strategy 4: Short-Term Operations

**Characteristics:**
- Real-time monitoring only
- No historical analysis needed
- Storage-constrained environments

**Configuration:**
```sql
-- 90 day retention
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '7776000000');

-- Or 1 year for minimal history
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '31536000000');
```

### Strategy 5: Indefinite Retention

**Characteristics:**
- Research data
- Historical archives
- Unlimited storage budget

**Configuration:**
```sql
-- No retention policy (keep forever)
-- Simply don't add a retention policy

-- Or very long retention
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '3153600000000');
```

---

## Adding Retention Policies

### Method 1: Automated Script

The provided script adds a default 10-year retention:

```bash
psql -U postgres -d historian -f sql/schema/02-configure-hypertables.sql
```

### Method 2: Manual Configuration

```sql
-- Connect to historian database
\c historian

-- Add retention policy (choose your interval)
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');
```

**Common intervals:**
```sql
-- 1 year
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '31536000000');

-- 2 years
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '63072000000');

-- 5 years
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '157680000000');

-- 7 years (FDA compliance)
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '220752000000');

-- 10 years (recommended default)
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');
```

### Advanced: Specific Duration

```sql
-- Exact number of days
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000'); -- Exactly 10 years

-- In milliseconds (for precise control)
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000'); -- 10 years in ms
```

---

## Modifying Retention Policies

### Change Retention Period

```sql
-- Remove existing policy
SELECT remove_retention_policy('sqlth_1_data');

-- Add new policy with different interval
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '157680000000');
```

### Temporarily Disable Retention

```sql
-- Remove policy temporarily
SELECT remove_retention_policy('sqlth_1_data');

-- Data won't be deleted until policy is re-added
-- Useful during audits or data migration
```

### View Current Policy

```sql
-- Check active retention policy
SELECT 
    hypertable_name,
    job_id,
    schedule_interval,
    config,
    next_start
FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy'
  AND hypertable_name = 'sqlth_1_data';
```

---

## Policy Scheduling

### Default Behavior

Retention policies run automatically:

```sql
-- View schedule details
SELECT 
    job_id,
    application_name,
    schedule_interval,
    config->>'drop_after' as retention_interval,
    next_start,
    last_run_started_at,
    last_run_status
FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy';
```

**Default schedule:**
- Runs daily (typically)
- Checks for chunks older than retention interval
- Drops entire chunks (not individual rows)
- Non-blocking operation

### Manual Execution

Force retention policy to run immediately:

```sql
-- Get job ID
SELECT job_id FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy'
  AND hypertable_name = 'sqlth_1_data';

-- Run job manually
CALL run_job(1001); -- Replace 1001 with actual job_id
```

---

## Verification

### 1. Verify Policy Exists

```sql
-- Check retention policy configuration
SELECT 
    h.hypertable_name,
    j.job_id,
    j.schedule_interval,
    j.config->>'drop_after' as retention_period,
    j.next_start as next_run
FROM timescaledb_information.hypertables h
JOIN timescaledb_information.jobs j 
    ON j.hypertable_name = h.hypertable_name
WHERE h.hypertable_name = 'sqlth_1_data'
  AND j.application_name = 'Retention Policy';
```

**Expected output:**
```
 hypertable_name | job_id | schedule_interval | retention_period | next_run 
-----------------+--------+-------------------+------------------+----------
 sqlth_1_data    | 1001   | 1 day             | 10 years         | 2025-12-09
```

### 2. Check Data Age Distribution

```sql
-- See age distribution of data
SELECT 
    DATE_TRUNC('month', to_timestamp(range_start/1000)) as month,
    COUNT(*) as num_chunks,
    pg_size_pretty(SUM(total_bytes)) as total_size,
    EXTRACT(YEAR FROM AGE(NOW(), to_timestamp(range_start/1000))) as years_old
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
GROUP BY month, years_old
ORDER BY month DESC
LIMIT 24;
```

### 3. Identify Chunks at Risk

```sql
-- Find chunks that will be deleted soon
SELECT 
    chunk_name,
    range_start,
    range_end,
    to_timestamp(range_end/1000) as chunk_end_date,
    AGE(NOW(), to_timestamp(range_end/1000)) as chunk_age,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sqlth_1_data'
  AND to_timestamp(range_end/1000) < NOW() - INTERVAL '9 years 11 months' -- Near 10 year limit
ORDER BY range_end DESC;
```

---

## Monitoring Retention

### Track Deleted Data

```sql
-- View retention policy execution history
SELECT 
    job_id,
    last_run_started_at,
    last_run_status,
    last_run_duration,
    total_runs,
    total_successes,
    total_failures
FROM timescaledb_information.job_stats
WHERE job_id IN (
    SELECT job_id FROM timescaledb_information.jobs
    WHERE application_name = 'Retention Policy'
);
```

### Storage Trends

```sql
-- Track storage over time (useful for capacity planning)
SELECT 
    current_date as measurement_date,
    hypertable_name,
    num_chunks,
    pg_size_pretty(total_bytes) as total_size,
    total_bytes
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'sqlth_1_data';

-- Save this query result periodically to track trends
```

### Estimate Future Deletions

```sql
-- Estimate how much data will be deleted in next run
WITH retention_threshold AS (
    SELECT (EXTRACT(EPOCH FROM NOW() - INTERVAL '10 years') * 1000)::BIGINT as threshold
)
SELECT 
    COUNT(*) as chunks_to_delete,
    pg_size_pretty(SUM(total_bytes)) as space_to_free,
    MIN(to_timestamp(range_start/1000)) as oldest_chunk_start,
    MAX(to_timestamp(range_end/1000)) as newest_chunk_to_delete
FROM timescaledb_information.chunks, retention_threshold
WHERE hypertable_name = 'sqlth_1_data'
  AND range_end < retention_threshold.threshold;
```

---

## Troubleshooting

### Retention Policy Not Running

**Check policy status:**

```sql
SELECT * FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy'
  AND hypertable_name = 'sqlth_1_data';
```

**If no results:**
```sql
-- Policy doesn't exist, add it
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');
```

**If job failed:**
```sql
-- Check error logs
SELECT * FROM timescaledb_information.job_stats
WHERE job_id = <job_id>;

-- Retry manually
CALL run_job(<job_id>);
```

### Data Not Being Deleted

**Verify data is old enough:**

```sql
-- Check oldest data age
SELECT 
    MIN(to_timestamp(t_stamp/1000)) as oldest_data,
    AGE(NOW(), MIN(to_timestamp(t_stamp/1000))) as data_age
FROM sqlth_1_data;
```

**If data age < retention period:** Data is not old enough to delete yet.

### Unexpected Data Deletion

**Verify retention policy interval:**

```sql
SELECT 
    config->>'drop_after' as retention_period
FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy'
  AND hypertable_name = 'sqlth_1_data';
```

**If interval is too short:**
```sql
-- Remove incorrect policy
SELECT remove_retention_policy('sqlth_1_data');

-- Add correct policy
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');
```

**⚠️ Warning:** Deleted data cannot be recovered. Ensure backups exist.

---

## Best Practices

### Before Adding Retention Policy

✅ **Verify requirements:** Check regulatory, business, and technical needs  
✅ **Test on non-production:** Validate retention period is correct  
✅ **Document decision:** Record why retention period was chosen  
✅ **Configure backups:** Ensure backup retention >= data retention  
✅ **Notify stakeholders:** Inform users of retention policy  

### Operating with Retention Policies

✅ **Monitor regularly:** Check policy execution logs  
✅ **Review periodically:** Annual review of retention requirements  
✅ **Combine with compression:** Compress before data reaches retention age  
✅ **Archive important data:** Export critical data before deletion  
✅ **Test recovery:** Verify backup restore procedures  

### Data Archival Before Deletion

If you need to keep some old data:

```sql
-- Export data before it's deleted
\copy (
    SELECT * FROM sqlth_1_data 
    WHERE t_stamp < (EXTRACT(EPOCH FROM NOW() - INTERVAL '9 years 11 months') * 1000)
) TO '/backup/archive_2015.csv' WITH CSV HEADER;
```

---

## Multi-Tier Retention Strategy

### Different Retention for Different Resolutions

```sql
-- Raw data: 2 years
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '63072000000');

-- 1-minute aggregates: 5 years
SELECT add_retention_policy('tag_history_1min', drop_after => BIGINT '157680000000');

-- Hourly aggregates: 10 years
SELECT add_retention_policy('tag_history_1hour', drop_after => BIGINT '315360000000');

-- Daily aggregates: 20 years
SELECT add_retention_policy('tag_history_1day', drop_after => BIGINT '630720000000');
```

**Benefits:**
- Keep raw data for recent analysis
- Long-term trends with aggregates
- Massive storage savings
- Meets various query requirements

---

## Compliance Documentation

### Generating Retention Reports

```sql
-- Retention policy audit report
SELECT 
    hypertable_name,
    config->>'drop_after' as retention_policy,
    last_run_started_at as last_execution,
    last_run_status as status,
    next_start as next_execution
FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy'
ORDER BY hypertable_name;
```

### Data Retention Certificate

```sql
-- Generate retention certificate for compliance
SELECT 
    'Data Retention Policy Certificate' as document,
    current_timestamp as generated_at,
    'sqlth_1_data' as table_name,
    config->>'drop_after' as retention_period,
    'Active' as policy_status,
    MIN(to_timestamp(t_stamp/1000)) as oldest_data,
    MAX(to_timestamp(t_stamp/1000)) as newest_data
FROM timescaledb_information.jobs, sqlth_1_data
WHERE application_name = 'Retention Policy'
  AND hypertable_name = 'sqlth_1_data'
GROUP BY config;
```

---

## Next Steps

✅ Retention policy configured and verified

**Continue to:**
- [Continuous Aggregates](04-continuous-aggregates.md) - Multi-resolution downsampling before deletion
- [Storage Optimization](../optimization/03-storage-optimization.md) - Maximize compression before retention

**Or explore:**
- [Basic Queries](../examples/01-basic-queries.md) - Query your retained data
- [Data Migration](../examples/05-data-migration.md) - Archive data before deletion

---

## Reference

### Common Commands

```sql
-- Add retention policy
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');

-- Remove retention policy
SELECT remove_retention_policy('sqlth_1_data');

-- View all retention policies
SELECT * FROM timescaledb_information.jobs
WHERE application_name = 'Retention Policy';

-- Manually run retention policy
CALL run_job(<job_id>);

-- Check data age
SELECT 
    MIN(to_timestamp(t_stamp/1000)) as oldest,
    MAX(to_timestamp(t_stamp/1000)) as newest,
    AGE(MAX(to_timestamp(t_stamp/1000)), MIN(to_timestamp(t_stamp/1000))) as span
FROM sqlth_1_data;
```

### Additional Resources

- [TimescaleDB Retention Documentation](https://www.tigerdata.com/docs/use-timescale/latest/data-retention/)
- [Data Retention Best Practices](https://www.tigerdata.com/docs/use-timescale/latest/data-retention/about-data-retention/)
- [FDA 21 CFR Part 11 Guidelines](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/part-11-electronic-records-electronic-signatures-scope-and-application)

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
