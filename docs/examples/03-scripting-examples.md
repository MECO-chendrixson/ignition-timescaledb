# Scripting Examples

**Last Updated:** December 8, 2025  
**Difficulty:** Intermediate  
**Prerequisites:** Basic Python/Jython knowledge

## Overview

Python and Jython scripting examples for querying TimescaleDB from Ignition.

## Basic Query Script

```python
# Query tag history from TimescaleDB
def getTagHistory(tagPath, hours=24):
    """Get tag history for the last N hours"""
    
    query = """
        SELECT 
            to_timestamp(t_stamp/1000) as timestamp,
            COALESCE(intvalue, floatvalue) as value,
            dataintegrity as quality
        FROM sqlth_1_data d
        JOIN sqlth_te t ON d.tagid = t.id
        WHERE t.tagpath = ?
          AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '%s hours') * 1000)
        ORDER BY t_stamp DESC
    """ % hours
    
    return system.db.runPrepQuery(query, [tagPath], 'Historian')

# Usage
data = getTagHistory('[default]Production/Temperature', 24)
print "Retrieved %d samples" % len(data)
```

## Export to CSV

```python
def exportTagData(tagPath, filename, days=7):
    """Export tag data to CSV file"""
    
    query = """
        SELECT 
            to_timestamp(t_stamp/1000) as timestamp,
            COALESCE(intvalue, floatvalue) as value
        FROM sqlth_1_data d
        JOIN sqlth_te t ON d.tagid = t.id
        WHERE t.tagpath = ?
          AND t_stamp >= (EXTRACT(EPOCH FROM NOW() - INTERVAL '%s days') * 1000)
        ORDER BY t_stamp
    """ % days
    
    data = system.db.runPrepQuery(query, [tagPath], 'Historian')
    
    # Convert to CSV
    csv = "Timestamp,Value\n"
    for row in data:
        csv += "%s,%s\n" % (row['timestamp'], row['value'])
    
    # Save to file
    system.file.writeFile(filename, csv)
    print "Exported %d rows to %s" % (len(data), filename)
```

## Daily Report Generator

```python
def generateDailyReport(tagList, date):
    """Generate daily statistics report for multiple tags"""
    
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
          AND t_stamp >= (EXTRACT(EPOCH FROM ?::timestamp) * 1000)
          AND t_stamp < (EXTRACT(EPOCH FROM ?::timestamp + INTERVAL '1 day') * 1000)
          AND d.dataintegrity = 192
        GROUP BY t.tagpath
        ORDER BY t.tagpath
    """
    
    nextDay = system.date.addDays(date, 1)
    return system.db.runPrepQuery(query, [tagList, date, date], 'Historian')
```

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
