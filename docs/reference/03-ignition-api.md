# Ignition API Reference

**Last Updated:** December 8, 2025  
**Difficulty:** Reference

## Overview

Reference for Ignition scripting functions to query and manipulate TimescaleDB historian data.

---

## Tag History Functions

### system.tag.queryTagHistory()

Query tag historical data.

**Syntax:**
```python
system.tag.queryTagHistory(
    paths,
    startDate,
    endDate,
    returnSize=-1,
    aggregationMode='Average',
    returnFormat='Wide',
    columnNames=None,
    intervalHours=1,
    intervalMinutes=0,
    rangeHours=8,
    rangeMinutes=0,
    aggregationModes=[],
    includeBoundingValues=True,
    validatesSCExec=True,
    noInterpolation=False,
    ignoreBadQuality=False,
    timeout=60000
)
```

**Example:**
```python
# Get last 24 hours of temperature data
paths = ['[default]Production/Temperature']
startDate = system.date.addHours(system.date.now(), -24)
endDate = system.date.now()

results = system.tag.queryTagHistory(
    paths=paths,
    startDate=startDate,
    endDate=endDate,
    returnSize=10000,
    aggregationMode='Average',
    returnFormat='Wide'
)

# Process results
for row in results:
    timestamp = row[0]
    value = row[1]
    print "%s: %s" % (timestamp, value)
```

**Aggregation Modes:**
- `'Average'` - Average values in interval
- `'MinMax'` - Min and max in interval
- `'LastValue'` - Last value in interval
- `'SimpleAverage'` - Simple average (no weighting)
- `'Sum'` - Sum of values
- `'Count'` - Number of samples

**Return Formats:**
- `'Wide'` - One column per tag
- `'Tall'` - Separate row per tag/time combination

---

### system.tag.queryTagCalculations()

Perform calculations on tag history.

```python
# Calculate statistics
paths = ['[default]Production/Temperature']
calculations = ['Average', 'Minimum', 'Maximum', 'StdDev']

results = system.tag.queryTagCalculations(
    paths=paths,
    calculations=calculations,
    startDate=startDate,
    endDate=endDate
)
```

---

## Database Query Functions

### system.db.runQuery()

Execute SELECT query.

```python
query = """
    SELECT 
        to_timestamp(t_stamp/1000) as timestamp,
        COALESCE(intvalue, floatvalue) as value
    FROM sqlth_1_data d
    JOIN sqlth_te t ON d.tagid = t.id
    WHERE t.tagpath = '[default]Production/Temperature'
      AND t_stamp >= %s
    ORDER BY t_stamp DESC
""" % (int(startTime.getTime()))

results = system.db.runQuery(query, 'Historian')
```

### system.db.runPrepQuery()

Execute prepared statement (safer, prevents SQL injection).

```python
query = """
    SELECT 
        to_timestamp(t_stamp/1000) as timestamp,
        COALESCE(intvalue, floatvalue) as value
    FROM sqlth_1_data d
    JOIN sqlth_te t ON d.tagid = t.id
    WHERE t.tagpath = ?
      AND t_stamp >= ?
    ORDER BY t_stamp DESC
"""

tagPath = '[default]Production/Temperature'
startTime = int(system.date.addHours(system.date.now(), -24).getTime())

results = system.db.runPrepQuery(query, [tagPath, startTime], 'Historian')
```

---

## Date/Time Functions

### system.date Functions

```python
# Current time
now = system.date.now()

# Add/subtract time
yesterday = system.date.addDays(now, -1)
lastHour = system.date.addHours(now, -1)
lastWeek = system.date.addWeeks(now, -1)

# Format dates
formatted = system.date.format(now, 'yyyy-MM-dd HH:mm:ss')

# Parse dates
parsed = system.date.parse('2025-12-08 10:00:00', 'yyyy-MM-dd HH:mm:ss')

# Convert to milliseconds (for queries)
timestamp_ms = int(now.getTime())
```

---

## Dataset Functions

### system.dataset Functions

```python
# Convert to Python dataset
pyData = system.dataset.toPyDataSet(results)

# Iterate rows
for row in pyData:
    timestamp = row['timestamp']
    value = row['value']
    print "%s: %s" % (timestamp, value)

# Export to CSV
csv = system.dataset.toCSV(results)
system.file.writeFile('C:\\temp\\export.csv', csv)
```

---

## Common Script Patterns

### Export Tag Data to CSV

```python
def exportTagHistory(tagPath, filePath, hours=24):
    """Export tag history to CSV file"""
    
    query = """
        SELECT 
            to_timestamp(t_stamp/1000) as timestamp,
            COALESCE(intvalue, floatvalue) as value,
            dataintegrity as quality
        FROM sqlth_1_data d
        JOIN sqlth_te t ON d.tagid = t.id
        WHERE t.tagpath = ?
          AND t_stamp >= ?
        ORDER BY t_stamp
    """
    
    startTime = int(system.date.addHours(system.date.now(), -hours).getTime())
    data = system.db.runPrepQuery(query, [tagPath, startTime], 'Historian')
    
    # Convert to CSV
    csv = system.dataset.toCSV(data)
    system.file.writeFile(filePath, csv)
    
    return len(data)
```

### Daily Report Generator

```python
def generateDailyReport(tagList, targetDate):
    """Generate daily statistics for multiple tags"""
    
    query = """
        SELECT 
            t.tagpath,
            COUNT(*) as samples,
            AVG(COALESCE(d.intvalue, d.floatvalue)) as avg_value,
            MIN(COALESCE(d.intvalue, d.floatvalue)) as min_value,
            MAX(COALESCE(d.intvalue, d.floatvalue)) as max_value,
            STDDEV(COALESCE(d.intvalue, d.floatvalue)) as std_dev
        FROM sqlth_1_data d
        JOIN sqlth_te t ON d.tagid = t.id
        WHERE t.tagpath = ANY(?)
          AND t_stamp >= ?
          AND t_stamp < ?
          AND d.dataintegrity = 192
        GROUP BY t.tagpath
    """
    
    dayStart = int(targetDate.getTime())
    dayEnd = int(system.date.addDays(targetDate, 1).getTime())
    
    return system.db.runPrepQuery(query, [tagList, dayStart, dayEnd], 'Historian')
```

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
