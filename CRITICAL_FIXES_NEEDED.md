# CRITICAL DOCUMENTATION FIXES NEEDED

**Date:** 2025-12-08
**Priority:** URGENT - Multiple syntax errors will cause commands to fail

## Summary

The documentation has systematic errors where `INTERVAL` types are used for BIGINT time columns.
For Ignition's BIGINT timestamp columns (milliseconds since epoch), all time-based parameters
must use integer milliseconds, not INTERVAL types.

## Files Requiring Fixes

### 1. docs/configuration/02-compression.md
**Status:** PARTIALLY FIXED (first section only)
**Remaining Issues:**
- Line 234: `show_chunks` with `INTERVAL '7 days'` - Should use milliseconds or timestamp
- Line 276, 295, 313, 331: `add_compression_policy` uses INTERVAL - Should use BIGINT
- Line 523, 729: More `add_compression_policy` with INTERVAL
- Strategy sections (lines 295-331): All use INTERVAL instead of BIGINT

**Required Changes:**
```sql
# WRONG:
SELECT add_compression_policy('sqlth_1_data', INTERVAL '7 days');

# CORRECT:
SELECT add_compression_policy('sqlth_1_data', BIGINT '604800000');
```

### 2. docs/configuration/03-retention-policies.md
**Status:** NOT FIXED
**Issues:** ALL retention policy examples use INTERVAL instead of BIGINT with drop_after parameter
**Lines affected:** 89, 107, 110, 128, 146, 149, 165, 187, 193, 196, 199, 202, 205, 212, 215, 229, 433, 478, 523, 526, 529, 532, 600

**Required Changes:**
```sql
# WRONG:
SELECT add_retention_policy('sqlth_1_data', INTERVAL '10 years');

# CORRECT:
SELECT add_retention_policy('sqlth_1_data', drop_after => BIGINT '315360000000');
```

### 3. docs/configuration/04-continuous-aggregates.md  
**Status:** NOT FIXED
**Critical Issues:**
1. `time_bucket` with BIGINT columns needs integer bucket widths, not INTERVAL
2. All retention policies use INTERVAL instead of BIGINT  
3. Refresh policies (add_continuous_aggregate_policy) use INTERVAL for start_offset/end_offset - MUST be INTEGER for BIGINT columns
4. Line 834: `add_compression_policy` uses INTERVAL

**Required Changes for time_bucket:**
```sql
# WRONG:
time_bucket('1 minute', t_stamp)

# CORRECT (for milliseconds):
time_bucket(60000, t_stamp)  -- 60000 ms = 1 minute
```

**Required Changes for refresh policies:**
```sql
# WRONG:
SELECT add_continuous_aggregate_policy('tag_history_1min',
    start_offset => INTERVAL '1 hour',
    end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '5 minutes');

# CORRECT:
SELECT add_continuous_aggregate_policy('tag_history_1min',
    start_offset => 3600000,  -- 1 hour in milliseconds
    end_offset => 60000,       -- 1 minute in milliseconds  
    schedule_interval => INTERVAL '5 minutes');  -- schedule_interval ALWAYS uses INTERVAL

**Note:** schedule_interval is wall-clock time and ALWAYS uses INTERVAL, even for integer time columns!
```

## Millisecond Conversion Reference

Common time intervals in milliseconds:
- 1 second = 1,000 ms
- 1 minute = 60,000 ms
- 5 minutes = 300,000 ms
- 10 minutes = 600,000 ms
- 1 hour = 3,600,000 ms
- 1 day = 86,400,000 ms
- 3 days = 259,200,000 ms
- 7 days = 604,800,000 ms
- 14 days = 1,209,600,000 ms
- 30 days = 2,592,000,000 ms
- 90 days = 7,776,000,000 ms
- 1 year = 31,536,000,000 ms
- 2 years = 63,072,000,000 ms
- 5 years = 157,680,000,000 ms
- 7 years = 220,752,000,000 ms
- 10 years = 315,360,000,000 ms

## Testing Required

After fixes, ALL commands must be tested against actual Ignition historian database:
1. Compression policy creation
2. Retention policy creation
3. Continuous aggregate creation with time_bucket
4. Refresh policy creation
5. Manual chunk operations (drop_chunks, show_chunks)

## Priority Order

1. **IMMEDIATE:** Fix 01-hypertable-setup.md (DONE ✓)
2. **HIGH:** Fix SQL script 02-configure-hypertables.sql (DONE ✓)  
3. **HIGH:** Fix 02-compression.md (PARTIALLY DONE - need to complete)
4. **HIGH:** Fix 03-retention-policies.md (NOT STARTED)
5. **CRITICAL:** Fix 04-continuous-aggregates.md (NOT STARTED - most complex)

## Impact

**If not fixed:**
- Users will get syntax errors when following documentation
- Policies will fail to create
- Continuous aggregates will not work
- Automated scripts will fail
- Users will lose trust in documentation accuracy

**Estimated time to fix:** 2-3 hours for complete review and testing
