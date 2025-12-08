# Table Schema Reference

**Last Updated:** December 8, 2025  
**Difficulty:** Reference

## Overview

Complete reference for Ignition SQL Tag Historian table schemas in PostgreSQL/TimescaleDB.

---

## Core Data Tables

### sqlth_1_data

Main historical data storage table (becomes hypertable).

```sql
\d sqlth_1_data
```

| Column | Type | Description |
|--------|------|-------------|
| `tagid` | INTEGER | Foreign key to sqlth_te.id |
| `intvalue` | INTEGER | Integer tag values |
| `floatvalue` | DOUBLE PRECISION | Floating point tag values |
| `stringvalue` | TEXT | String tag values |
| `datevalue` | TIMESTAMP | Date/time tag values |
| `dataintegrity` | INTEGER | Quality code (0-255) |
| `t_stamp` | BIGINT | Unix timestamp in milliseconds |

**Indexes:**
- Primary key: None (hypertable partitioned by t_stamp)
- `idx_sqlth_data_tstamp_brin` - BRIN index on t_stamp
- `idx_sqlth_data_tagid_tstamp` - B-tree on (tagid, t_stamp DESC)

**Storage:**
- One row per tag value change
- Only one value column populated per row (based on tag datatype)
- Typical row size: 32-48 bytes

---

### sqlth_te (Tag Metadata)

Tag configuration and metadata.

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key, tag ID |
| `tagpath` | VARCHAR(512) | Full tag path |
| `datatype` | INTEGER | Data type (1=int, 2=float, 3=string, 4=date) |
| `scid` | INTEGER | Scan class ID |
| `created` | BIGINT | Creation timestamp |
| `retired` | BIGINT | Retirement timestamp (NULL if active) |

**Indexes:**
- Primary key on `id`
- Unique index on `tagpath` WHERE retired IS NULL

---

## Quality Codes (dataintegrity)

| Code | Name | Description |
|------|------|-------------|
| 192 | Good | Normal, good quality data |
| 0 | Bad | Generic bad quality |
| 8 | Bad_OutOfRange | Value outside configured range |
| 64 | Bad_Stale | Data hasn't updated recently |
| 12 | Bad_DeviceFailure | Device or connection failure |

---

## Metadata Tables

### sqlth_partitions

Partition configuration for historian.

| Column | Type | Description |
|--------|------|-------------|
| `partitionid` | SERIAL | Primary key |
| `pname` | VARCHAR(255) | Partition name |
| `start_time` | BIGINT | Partition start timestamp |
| `end_time` | BIGINT | Partition end timestamp |

### sqlth_drv

Driver information.

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key |
| `drvpath` | VARCHAR(255) | Driver path/name |
| `created` | BIGINT | Creation timestamp |

---

## Query Examples

### Get Tag Schema
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'sqlth_1_data'
ORDER BY ordinal_position;
```

### Check Table Sizes
```sql
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) as total_size,
    pg_size_pretty(pg_relation_size(tablename::regclass)) as table_size
FROM pg_tables
WHERE schemaname = 'public' AND tablename LIKE 'sqlth%';
```

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
