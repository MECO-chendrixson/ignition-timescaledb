# Data Quality Troubleshooting

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate

## Overview

Guide for identifying and resolving data quality issues in Ignition historian with TimescaleDB.

---

## Missing Data

### Detection

**Check for data gaps:**
```sql
-- Find hours with missing data
WITH hourly_counts AS (
    SELECT 
        time_bucket(3600000, t_stamp) as hour,
        COUNT(*) as sample_count
    FROM sqlth_1_data
    WHERE tagid = 100
      AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
    GROUP BY hour
)
SELECT 
    to_timestamp(hour/1000) as hour,
    sample_count,
    CASE 
        WHEN sample_count < 3000 THEN 'Missing data'
        ELSE 'OK'
    END as status
FROM hourly_counts
WHERE sample_count < 3000
ORDER BY hour DESC;
```

### Causes

1. **Ignition Gateway down**
2. **Tag not enabled for history**
3. **Bad quality data (filtered out)**
4. **Network issues**
5. **Database connection failure**

### Solutions

**1. Check Ignition store and forward:**
- Gateway → Config → System → Store and Forward
- Check for quarantined data
- Check for backlogs

**2. Verify tag configuration:**
```python
# In Ignition Designer
tagConfig = system.tag.getConfiguration('[default]Production/Temperature')[0]
print tagConfig['historyEnabled']
print tagConfig['historicalTagProvider']
```

**3. Backfill missing data (if source available):**
```sql
-- Import from backup or another source
INSERT INTO sqlth_1_data (tagid, floatvalue, dataintegrity, t_stamp)
SELECT tagid, floatvalue, 192, t_stamp
FROM backup_table
WHERE t_stamp NOT IN (SELECT t_stamp FROM sqlth_1_data WHERE tagid = backup_table.tagid);
```

---

## Duplicate Records

### Detection

```sql
-- Find duplicates
SELECT 
    tagid,
    t_stamp,
    COUNT(*) as duplicate_count,
    ARRAY_AGG(COALESCE(intvalue, floatvalue)) as values
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY tagid, t_stamp
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
```

### Removal

```sql
-- Delete duplicates, keeping first record
DELETE FROM sqlth_1_data a USING (
    SELECT MIN(ctid) as ctid, tagid, t_stamp
    FROM sqlth_1_data
    GROUP BY tagid, t_stamp
    HAVING COUNT(*) > 1
) b
WHERE a.tagid = b.tagid 
  AND a.t_stamp = b.t_stamp 
  AND a.ctid <> b.ctid;
```

---

## Incorrect Timestamps

### Detection

```sql
-- Find future timestamps
SELECT 
    tagid,
    t_stamp,
    to_timestamp(t_stamp/1000) as timestamp_human,
    CASE 
        WHEN t_stamp > (EXTRACT(EPOCH FROM NOW() + INTERVAL '1 day') * 1000) 
            THEN 'FUTURE'
        WHEN t_stamp < (EXTRACT(EPOCH FROM '2000-01-01'::timestamp) * 1000)
            THEN 'TOO OLD'
        ELSE 'OK'
    END as timestamp_status
FROM sqlth_1_data
WHERE t_stamp > (EXTRACT(EPOCH FROM NOW() + INTERVAL '1 day') * 1000)
   OR t_stamp < (EXTRACT(EPOCH FROM '2000-01-01'::timestamp) * 1000)
LIMIT 100;
```

### Causes

1. **System clock drift** on Ignition gateway
2. **Timezone issues** in configuration
3. **Millisecond vs second confusion**
4. **Manual data entry errors**

### Solutions

**1. Fix system clock:**
```bash
# Linux - sync time
sudo ntpdate pool.ntp.org
sudo timedatectl set-ntp true

# Windows - sync time
w32tm /resync
```

**2. Delete invalid timestamps:**
```sql
-- Delete future timestamps
DELETE FROM sqlth_1_data
WHERE t_stamp > (EXTRACT(EPOCH FROM NOW() + INTERVAL '1 hour') * 1000);

-- Delete ancient timestamps (before year 2000)
DELETE FROM sqlth_1_data
WHERE t_stamp < (EXTRACT(EPOCH FROM '2000-01-01'::timestamp) * 1000);
```

---

## Data Quality Codes

### Quality Distribution Analysis

```sql
SELECT 
    dataintegrity as quality_code,
    CASE dataintegrity
        WHEN 192 THEN 'Good'
        WHEN 0 THEN 'Bad'
        WHEN 8 THEN 'Bad_OutOfRange'
        WHEN 64 THEN 'Bad_Stale'
        WHEN 12 THEN 'Bad_DeviceFailure'
        ELSE 'Unknown (' || dataintegrity || ')'
    END as quality_name,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM sqlth_1_data
WHERE t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') * 1000)
GROUP BY dataintegrity
ORDER BY count DESC;
```

### Filter Bad Quality

```sql
-- Query only good quality data
SELECT * FROM sqlth_1_data
WHERE dataintegrity = 192  -- Good quality
  AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour') * 1000);
```

---

## Data Integrity Checks

### Comprehensive Quality Report

```sql
WITH quality_stats AS (
    SELECT 
        t.tagpath,
        COUNT(*) as total_samples,
        COUNT(*) FILTER (WHERE d.dataintegrity = 192) as good_samples,
        COUNT(*) FILTER (WHERE d.dataintegrity != 192) as bad_samples,
        MIN(to_timestamp(d.t_stamp/1000)) as first_sample,
        MAX(to_timestamp(d.t_stamp/1000)) as last_sample
    FROM sqlth_1_data d
    JOIN sqlth_te t ON d.tagid = t.id
    WHERE d.t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days') * 1000)
    GROUP BY t.tagpath
)
SELECT 
    tagpath,
    total_samples,
    good_samples,
    bad_samples,
    ROUND(100.0 * good_samples / total_samples, 2) as good_pct,
    last_sample,
    NOW() - last_sample as time_since_update
FROM quality_stats
WHERE bad_samples > 100  -- Only show tags with quality issues
ORDER BY bad_samples DESC;
```

---

## Best Practices

✅ Monitor data quality metrics  
✅ Filter by quality code in queries  
✅ Investigate spikes in bad quality  
✅ Set up alerts for missing data  
✅ Regular data integrity checks  

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
