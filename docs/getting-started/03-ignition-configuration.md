# Ignition Configuration

**Estimated Time:** 20-30 minutes  
**Difficulty:** Beginner to Intermediate  
**Prerequisites:** Databases created and Ignition 8.3.2+ installed

## Overview

This guide covers configuring Ignition SCADA to use PostgreSQL/TimescaleDB for tag history, alarm journaling, and audit logging.

---

## Part 1: Database Connections

### Step 1: Access Gateway Configuration

1. Open web browser
2. Navigate to: `http://your-ignition-server:8088`
3. Click **Config** tab
4. Login with Gateway credentials (default: admin/password)

### Step 2: Create Historian Database Connection

1. Navigate to **Config → Database → Connections**
2. Click **Create new Database Connection...**

**Configure Connection:**

| Setting | Value | Notes |
|---------|-------|-------|
| **Name** | `Historian` | Must match exactly in other configs |
| **Description** | `PostgreSQL/TimescaleDB Historian` | Optional |
| **Enabled** | ✅ Checked | |
| **Database Type** | `PostgreSQL` | Select from dropdown |
| **Connect URL** | See below | Depends on your setup |
| **Username** | `ignition` | Created in database setup |
| **Password** | `your_password` | From database setup |
| **Extra Connection Properties** | `reWriteBatchedInserts=true;` | **IMPORTANT** for performance |

**Connect URL Examples:**

**Local PostgreSQL:**
```
jdbc:postgresql://localhost:5432/historian
```

**Remote PostgreSQL:**
```
jdbc:postgresql://192.168.1.100:5432/historian
```

**With SSL:**
```
jdbc:postgresql://192.168.1.100:5432/historian?ssl=true&sslmode=require
```

**Click:** `Create New Database Connection`

### Step 3: Verify Connection

Connection should show **Valid** with a green checkmark.

**If "Invalid" appears:**
- Click connection name to edit
- Check **Status & Diagnostics** tab
- Review error message
- Common issues:
  - Wrong username/password
  - Database server unreachable
  - Firewall blocking port 5432
  - PostgreSQL not allowing remote connections

### Step 4: Create Alarm Log Connection

Repeat Step 2 with these settings:

| Setting | Value |
|---------|-------|
| **Name** | `AlarmLog` |
| **Connect URL** | `jdbc:postgresql://localhost:5432/alarmlog` |
| **Username** | `ignition` |
| **Password** | `your_password` |
| **Extra Properties** | `reWriteBatchedInserts=true;` |

### Step 5: Create Audit Log Connection

Repeat Step 2 with these settings:

| Setting | Value |
|---------|-------|
| **Name** | `AuditLog` |
| **Connect URL** | `jdbc:postgresql://localhost:5432/auditlog` |
| **Username** | `ignition` |
| **Password** | `your_password` |
| **Extra Properties** | `reWriteBatchedInserts=true;` |

**Result:** You should now have 3 database connections, all showing **Valid**.

---

## Part 2: Configure Tag Historian

### Step 1: Navigate to Historian Configuration

1. In Gateway, navigate to **Services → Historians → Historians**
2. Note the path change in 8.3 (was **Config → Tags → History** in 8.1)

### Step 2: Check for Existing Historians

You may see:
- **Core Historian** (QuestDB-based, new in 8.3)
- **Internal Historian (Legacy)** (SQLite-based)

**For TimescaleDB, we'll create a new SQL Historian.**

### Step 3: Create SQL Historian Provider

**IMPORTANT:** Requires the **SQL Historian** module to be installed.

**Check module installation:**
1. Navigate to **Config → System → Modules**
2. Look for **SQL Tag Historian** module
3. If not installed, contact your Ignition provider or download from Inductive Automation

**Create the historian:**

1. Click **Create Historian +**
2. Select **SQL Historian**
3. Click **Next**

### Step 4: Configure Main Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Name** | `Historian` | Or your preferred name |
| **Description** | `TimescaleDB Historian` | Optional |
| **Enabled** | ✅ Checked | |
| **Data Source** | `Historian` | Select the database connection |

### Step 5: Configure Data Partitioning

**CRITICAL:** TimescaleDB handles partitioning automatically.

| Setting | Value | Why |
|---------|-------|-----|
| **Enable Partitioning** | ❌ **Unchecked** | TimescaleDB hypertables handle this |
| **Partition Length** | N/A | Ignored when unchecked |
| **Partition Units** | N/A | Ignored when unchecked |
| **Enable Pre-processed Partitions** | ❌ Unchecked | Optional; usually not needed |

**Why disable Ignition partitioning?**
- TimescaleDB's automatic partitioning is more efficient
- Avoids double-partitioning overhead
- Simplifies continuous aggregate setup
- Single table (`sqlth_1_data`) is easier to manage

### Step 6: Configure Data Pruning

**CRITICAL:** TimescaleDB retention policies handle this.

| Setting | Value | Why |
|---------|-------|-----|
| **Enable Data Pruning** | ❌ **Unchecked** | TimescaleDB retention policies handle this |
| **Prune Age** | N/A | Will be set in TimescaleDB |
| **Prune Age Units** | N/A | Will be set in TimescaleDB |

### Step 7: Advanced Settings (Optional)

| Setting | Default | Notes |
|---------|---------|-------|
| **Enable Stale Data Detection** | ✅ Checked | Recommended for tag groups |
| **Stale Detection Multiplier** | `3.0` | Adjust based on scan rates |

### Step 8: Create Historian

Click **Create Historian**

**Verify:** Historian appears in list with **Status: Running**

---

## Part 3: Configure Alarm Journal

### Step 1: Navigate to Alarm Configuration

1. In Gateway, navigate to **Alarming → Journal**
2. Click **Create new Alarm Journal Profile...**

### Step 2: Configure Alarm Journal

| Setting | Value |
|---------|-------|
| **Name** | `AlarmLog` |
| **Description** | `PostgreSQL Alarm Journal` |
| **Enabled** | ✅ Checked |
| **Datasource** | `AlarmLog` |

### Step 3: Configure Pruning

| Setting | Value | Notes |
|---------|-------|-------|
| **Enable Data Pruning** | ✅ Checked | Unlike historian, enable this |
| **Prune Age** | `90` | Adjust to requirements |
| **Prune Age Units** | `Days` | Common: 30-365 days |

**Why enable pruning for alarms?**
- Alarm data is typically not needed indefinitely
- Keeps alarm journal responsive
- Can export for long-term archival if needed

### Step 4: Create Journal Profile

Click **Create New Alarm Journal Profile**

**Verify:** Profile shows **Active**

---

## Part 4: Configure Audit Logging

### Step 1: Navigate to Audit Configuration

1. In Gateway, navigate to **Security → Auditing**
2. Click **Create new Audit Profile...**

### Step 2: Configure Audit Profile

| Setting | Value |
|---------|-------|
| **Name** | `AuditLog` |
| **Description** | `PostgreSQL Audit Log` |
| **Enabled** | ✅ Checked |
| **Datasource** | `AuditLog` |

### Step 3: Configure Scope

| Setting | Value | Notes |
|---------|-------|-------|
| **Audit Gateway Events** | ✅ Checked | System changes |
| **Audit Designer Events** | ✅ Checked | Project changes |
| **Audit Client Events** | ⬜ Unchecked | Usually too verbose |

### Step 4: Configure Pruning

| Setting | Value |
|---------|-------|
| **Enable Data Pruning** | ✅ Checked |
| **Prune Age** | `365` |
| **Prune Age Units** | `Days` |

### Step 5: Create Audit Profile

Click **Create New Audit Profile**

---

## Part 5: Wait for Table Creation

After configuring the historian, Ignition will automatically create the necessary tables.

### Monitor Table Creation

**Check table creation progress:**

```bash
# Connect to historian database
psql -U postgres -d historian

# List all tables
\dt sqlth*

# Exit
\q
```

**Expected tables (may take 1-2 minutes):**
- `sqlth_1_data` - Main historical data
- `sqlth_te` - Tag metadata
- `sqlth_partitions` - Partition information
- `sqlth_drv` - Driver information
- `sqlth_scinfo` - Scan class information
- `sqlth_sce` - Scan class execution
- `sqlth_annotations` - Power Chart annotations

**Check row counts:**
```sql
SELECT 'sqlth_1_data' as table_name, COUNT(*) FROM sqlth_1_data
UNION ALL
SELECT 'sqlth_te', COUNT(*) FROM sqlth_te
UNION ALL
SELECT 'sqlth_partitions', COUNT(*) FROM sqlth_partitions
UNION ALL
SELECT 'sqlth_drv', COUNT(*) FROM sqlth_drv;
```

---

## Part 6: Enable Tag History

### Option 1: Designer Tag Configuration

1. Open Ignition Designer
2. Navigate to **Tag Browser**
3. Right-click a tag → **Edit Tag(s)**
4. In **Tag Editor**, find **Tag History** section:

| Setting | Value | Notes |
|---------|-------|-------|
| **History Enabled** | ✅ Checked | Enable tag history |
| **Historical Tag Provider** | `Historian` | Must match provider name |
| **Sample Mode** | `On Change` | Or `Tag Group` or `Periodic` |
| **Deadband Style** | `Discrete` | Or `Analog` |
| **Deadband** | `0.0` | Adjust based on tag variability |
| **Max Time Between Samples** | `10000` ms | Adjust as needed |
| **Storage Provider** | `Historian` | Should auto-populate |

5. Click **Save**

### Option 2: Bulk Tag Configuration

**For enabling history on multiple tags:**

1. In Tag Browser, select multiple tags (Ctrl+Click or Shift+Click)
2. Right-click → **Edit Tags**
3. Click **Tag History** tab
4. Check **Override** for settings you want to apply to all
5. Configure as above
6. Click **OK**

### Option 3: Scripting (Advanced)

```python
# Enable history on all tags in a folder
system.tag.configure(basePath="[default]Production/Line1",
    tags=[{
        "historyEnabled": True,
        "historicalTagProvider": "Historian",
        "sampleMode": "OnChange"
    }],
    collisionPolicy="o")
```

---

## Verification and Testing

### Test 1: Verify Connection Status

1. Navigate to **Config → Database → Connections**
2. All three connections should show **Valid**

### Test 2: Verify Historian Status

1. Navigate to **Services → Historians → Historians**
2. SQL Historian should show **Status: Running**
3. Click on historian name
4. Check **Diagnostics** tab for any errors

### Test 3: Verify Tables Created

```bash
psql -U postgres -d historian -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'sqlth%' ORDER BY tablename;"
```

### Test 4: Verify Data is Being Stored

Wait 5-10 minutes after enabling tag history, then check:

```sql
-- Connect to historian database
psql -U postgres -d historian

-- Check for recent data
SELECT 
    COUNT(*) as total_records,
    MAX(t_stamp) as latest_timestamp,
    to_timestamp(MAX(t_stamp)/1000) as latest_time
FROM sqlth_1_data;
```

Expected: `total_records` > 0 and `latest_time` should be recent.

### Test 5: View Tag History in Designer

1. In Designer, open **Easy Chart** or **Power Chart**
2. Drag a history-enabled tag onto the chart
3. Set time range to **Last Hour**
4. Verify trend line appears

---

## Troubleshooting

### No Tables Created

**Check Gateway logs:**
1. Navigate to **Status → Diagnostics → Logs**
2. Filter for "historian" or "database"
3. Look for errors

**Common causes:**
- Database permissions insufficient
- Connection invalid
- Historian not started

**Solution:**
```sql
-- Grant full permissions
GRANT ALL PRIVILEGES ON DATABASE historian TO ignition;
GRANT ALL ON SCHEMA public TO ignition;
```

### Tables Created But No Data

**Check tag configuration:**
1. Verify tag has **History Enabled** = True
2. Verify tag quality is **Good** (bad quality won't log)
3. Check **Sample Mode** is appropriate
4. Review deadband settings

**Check Store and Forward:**
1. Navigate to **Config → System → Store and Forward**
2. Check for backlogs or quarantined data
3. Review errors in **Diagnostics** tab

### "Invalid Connection" Error

**Verify connection string:**
- Correct hostname/IP
- Correct port (5432)
- Correct database name
- Username and password correct

**Test from command line:**
```bash
psql -U ignition -h localhost -d historian -c "SELECT 1;"
```

### Performance Issues

**Add connection property:**
```
reWriteBatchedInserts=true;defaultRowFetchSize=10000;
```

**Check active connections:**
```sql
SELECT count(*) FROM pg_stat_activity WHERE datname = 'historian';
```

If high (>50), consider increasing PostgreSQL connection limits.

---

## Next Steps

✅ Ignition is now configured to use TimescaleDB.

**Continue to:**
- [Hypertable Configuration](../configuration/01-hypertable-setup.md) - Convert tables to TimescaleDB hypertables
- [Performance Tuning](../optimization/01-performance-tuning.md) - Optimize for production

---

## Additional Resources

- [Ignition 8.3 Historian Documentation](https://docs.inductiveautomation.com/docs/8.3/ignition-modules/tag-historian)
- [Database Connection Configuration](https://docs.inductiveautomation.com/docs/8.3/platform/database-connections)
- [Tag History Configuration](https://docs.inductiveautomation.com/docs/8.3/ignition-modules/tag-historian/configuring-tag-history)

**Last Updated:** December 7, 2025
