# Installation Guide - Windows Server

**Platform:** Windows Server 2016, 2019, 2022  
**Estimated Time:** 30-45 minutes  
**Difficulty:** Beginner  
**Prerequisites:** Administrator access to Windows Server

---

## Overview

This guide covers installing PostgreSQL and TimescaleDB on Windows Server for use with Ignition SCADA. For Linux installation, see [Installation Guide - Linux](01-installation-linux.md).

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Download PostgreSQL](#download-postgresql)
3. [Install PostgreSQL](#install-postgresql)
4. [Install TimescaleDB](#install-timescaledb)
5. [Configure PostgreSQL for Remote Connections](#configure-postgresql-for-remote-connections)
6. [Configure Windows Firewall](#configure-windows-firewall)
7. [Verify Installation](#verify-installation)
8. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Minimum Requirements
- **OS:** Windows Server 2016 or higher
- **RAM:** 4GB (8GB+ recommended)
- **Storage:** 20GB free space (more for production data)
- **PostgreSQL:** Version 12+ (15-17 recommended)
- **TimescaleDB:** Version 2.0+ (2.13+ recommended)

### Recommended Production Requirements
- **OS:** Windows Server 2019/2022
- **RAM:** 16GB+
- **Storage:** SSD with 100GB+ free space
- **CPU:** 4+ cores

---

## Download PostgreSQL

### Step 1: Visit PostgreSQL Download Page

1. Open web browser
2. Navigate to: https://www.enterprisedb.com/downloads/postgres-postgresql-downloads
3. Select your PostgreSQL version (recommend 15 or 17)
4. Select **Windows x86-64** platform
5. Click **Download**

**Recommended Version:** PostgreSQL 15.x or 17.x (stable releases)

### Step 2: Download TimescaleDB

TimescaleDB will be installed after PostgreSQL using the Timescale installer.

---

## Install PostgreSQL

### Step 1: Run PostgreSQL Installer

1. Locate the downloaded file (e.g., `postgresql-17.x-windows-x64.exe`)
2. Right-click → **Run as Administrator**
3. Click **Next** on welcome screen

### Step 2: Select Installation Directory

**Default:**
```
C:\Program Files\PostgreSQL\17\
```

**Recommended:** Use default unless you have specific requirements

Click **Next**

### Step 3: Select Components

**Ensure these are checked:**
- ✅ PostgreSQL Server
- ✅ pgAdmin 4
- ✅ Stack Builder (needed for TimescaleDB)
- ✅ Command Line Tools

Click **Next**

### Step 4: Set Data Directory

**Default:**
```
C:\Program Files\PostgreSQL\17\data
```

**Production Recommendation:** Use a separate drive for data
```
D:\PostgreSQL\data
```

Click **Next**

### Step 5: Set Superuser Password

**CRITICAL:** Set a strong password for the `postgres` superuser.

**Example:** Use a password manager to generate a secure password

⚠️ **Important:** Save this password securely - you'll need it for database administration!

Click **Next**

### Step 6: Set Port

**Default:** `5432`

**Recommendation:** Use default unless port 5432 is already in use

Click **Next**

### Step 7: Locale

**Default:** `[Default locale]`

**Recommendation:** Use default for English systems

Click **Next**

### Step 8: Review and Install

1. Review installation summary
2. Click **Next** to begin installation
3. Wait for installation to complete (5-10 minutes)
4. ✅ **Uncheck** "Launch Stack Builder at exit" (we'll use Timescale installer instead)
5. Click **Finish**

---

## Install TimescaleDB

### Step 1: Download Timescale Installer

1. Open web browser
2. Navigate to: https://docs.timescale.com/self-hosted/latest/install/installation-windows/
3. Download the **Timescale PostgreSQL installer** for your PostgreSQL version
4. Or visit: https://www.timescale.com/download

### Step 2: Run Timescale Installer

1. Locate downloaded file (e.g., `timescaledb-postgresql-17-windows-amd64.exe`)
2. Right-click → **Run as Administrator**
3. Follow installation wizard
4. Select your PostgreSQL installation directory
5. Click **Install**

### Step 3: Update PostgreSQL Configuration

The TimescaleDB installer should automatically update `postgresql.conf`, but verify:

1. Open file in text editor (as Administrator):
   ```
   C:\Program Files\PostgreSQL\17\data\postgresql.conf
   ```

2. Find the `shared_preload_libraries` line and ensure it includes `timescaledb`:
   ```
   shared_preload_libraries = 'timescaledb'
   ```

3. Save file

### Step 4: Restart PostgreSQL Service

**Option A: Using Services Manager**

1. Press `Win + R`
2. Type `services.msc` and press Enter
3. Find **postgresql-x64-17** (or your version)
4. Right-click → **Restart**

**Option B: Using Command Prompt (as Administrator)**

```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

---

## Configure PostgreSQL for Remote Connections

If Ignition is on a different server than PostgreSQL, you need to enable remote connections.

### Step 1: Edit postgresql.conf

1. Open in text editor (as Administrator):
   ```
   C:\Program Files\PostgreSQL\17\data\postgresql.conf
   ```

2. Find the line:
   ```
   #listen_addresses = 'localhost'
   ```

3. Change to:
   ```
   listen_addresses = '*'
   ```

4. Save file

### Step 2: Edit pg_hba.conf

1. Open in text editor (as Administrator):
   ```
   C:\Program Files\PostgreSQL\17\data\pg_hba.conf
   ```

2. Add this line at the end (adjust IP range for your network):
   ```
   # Allow connections from Ignition server(s)
   host    all    all    192.168.1.0/24    scram-sha-256
   ```

   **For specific IP:**
   ```
   host    all    all    192.168.1.100/32    scram-sha-256
   ```

   **For any IP (DEVELOPMENT ONLY - NOT SECURE):**
   ```
   host    all    all    0.0.0.0/0    scram-sha-256
   ```

3. Save file

### Step 3: Restart PostgreSQL

```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

---

## Configure Windows Firewall

### Option 1: Using Windows Firewall GUI

1. Open **Windows Defender Firewall with Advanced Security**
2. Click **Inbound Rules**
3. Click **New Rule...**
4. Select **Port**, click **Next**
5. Select **TCP**, enter port `5432`, click **Next**
6. Select **Allow the connection**, click **Next**
7. Check all profiles (Domain, Private, Public), click **Next**
8. Name: `PostgreSQL`, click **Finish**

### Option 2: Using PowerShell (as Administrator)

```powershell
New-NetFirewallRule -DisplayName "PostgreSQL" -Direction Inbound -Protocol TCP -LocalPort 5432 -Action Allow
```

### Option 3: Using Command Prompt (as Administrator)

```cmd
netsh advfirewall firewall add rule name="PostgreSQL" dir=in action=allow protocol=TCP localport=5432
```

---

## Verify Installation

### Step 1: Check PostgreSQL Service

```cmd
sc query postgresql-x64-17
```

**Expected:** `STATE: RUNNING`

### Step 2: Connect with psql

1. Open **SQL Shell (psql)** from Start Menu
2. Press Enter to accept defaults for:
   - Server: `localhost`
   - Database: `postgres`
   - Port: `5432`
   - Username: `postgres`
3. Enter the password you set during installation

### Step 3: Check PostgreSQL Version

```sql
SELECT version();
```

**Expected output:** PostgreSQL version information

### Step 4: Check TimescaleDB Installation

```sql
SELECT default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'timescaledb';
```

**Expected:** Version numbers displayed (e.g., 2.13.0)

### Step 5: Test TimescaleDB Extension

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

**Expected:** `CREATE EXTENSION` or warning that it already exists

### Step 6: Verify TimescaleDB Functions

```sql
SELECT * FROM timescaledb_information.hypertables;
```

**Expected:** Empty result (no hypertables yet) or successful query execution

### Step 7: Exit psql

```sql
\q
```

---

## Troubleshooting

### PostgreSQL Service Won't Start

**Symptoms:** Service fails to start after installation

**Check Event Viewer:**
1. Open **Event Viewer**
2. Navigate to **Windows Logs → Application**
3. Look for PostgreSQL errors

**Common Causes:**

**1. Port Already in Use**
```cmd
netstat -ano | findstr :5432
```

If port is in use, change PostgreSQL port in `postgresql.conf`:
```
port = 5433
```

**2. Data Directory Permissions**

Ensure PostgreSQL service account has full control of data directory:
1. Right-click data folder → **Properties**
2. **Security** tab → **Edit**
3. Ensure **NETWORK SERVICE** has **Full Control**

**3. Invalid Configuration**

Check PostgreSQL log:
```
C:\Program Files\PostgreSQL\17\data\log\postgresql-*.log
```

### TimescaleDB Extension Not Found

**Symptoms:** Error when running `CREATE EXTENSION timescaledb;`

**Solutions:**

**1. Verify shared_preload_libraries**
```sql
SHOW shared_preload_libraries;
```

Should include `timescaledb`

**2. Reinstall TimescaleDB**
- Download Timescale installer again
- Run as Administrator
- Select correct PostgreSQL installation

**3. Manual Configuration**

Edit `postgresql.conf`:
```
shared_preload_libraries = 'timescaledb'
```

Restart service:
```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

### Cannot Connect Remotely

**Symptoms:** Ignition can't connect to PostgreSQL from another server

**Solutions:**

**1. Check PostgreSQL is Listening**
```cmd
netstat -ano | findstr :5432
```

Should show `0.0.0.0:5432` or `*:5432`

**2. Verify pg_hba.conf**

Ensure you have the correct entry for Ignition's IP:
```
host    all    all    192.168.1.100/32    scram-sha-256
```

**3. Check Firewall**
```powershell
Get-NetFirewallRule -DisplayName "PostgreSQL"
```

Should show rule as **Enabled**

**4. Test from Ignition Server**

Using PowerShell on Ignition server:
```powershell
Test-NetConnection -ComputerName <postgres-server-ip> -Port 5432
```

**Expected:** `TcpTestSucceeded : True`

### pgAdmin Can't Connect

**Symptoms:** pgAdmin shows "could not connect to server"

**Solutions:**

**1. Verify PostgreSQL Service Running**
```cmd
sc query postgresql-x64-17
```

**2. Check Password**
- Ensure you're using the correct superuser password
- Reset if forgotten (requires Windows access to server)

**3. Check Port**
- Ensure PostgreSQL is on port 5432
- Check `postgresql.conf` for `port` setting

### Performance Issues on Windows

**Symptoms:** Slow query performance or high disk I/O

**Optimizations:**

**1. Disable Windows Search Indexing on Data Directory**
1. Right-click data folder → **Properties**
2. Uncheck **Allow files in this folder to have contents indexed**

**2. Adjust PostgreSQL Memory Settings**

Edit `postgresql.conf`:
```
# For 16GB RAM system
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
work_mem = 64MB
```

**3. Use SSD for Data Directory**

Move data directory to SSD if currently on HDD

---

## Performance Tuning for Windows

### Recommended postgresql.conf Settings

For a Windows Server with 16GB RAM:

```ini
# Memory Settings
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
work_mem = 64MB

# Checkpoint Settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB

# Query Tuning
random_page_cost = 1.1  # For SSD
effective_io_concurrency = 200  # For SSD

# TimescaleDB Settings
timescaledb.max_background_workers = 8
```

Restart PostgreSQL after changes:
```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

---

## Next Steps

✅ PostgreSQL and TimescaleDB are now installed on Windows Server.

**Continue to:**
- [Database Setup - Windows](02-database-setup-windows.md) - Create Ignition databases
- [Ignition Configuration](03-ignition-configuration.md) - Configure Ignition historian

**Alternative Path:**
- [Installation Guide - Linux](01-installation-linux.md) - For Linux installations

---

## Additional Resources

- [PostgreSQL Windows Documentation](https://www.postgresql.org/docs/current/install-windows.html)
- [TimescaleDB Windows Installation](https://docs.timescale.com/self-hosted/latest/install/installation-windows/)
- [PostgreSQL Windows Tuning](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)

---

**Last Updated:** December 8, 2025  
**Platform:** Windows Server  
**Maintained By:** Miller-Eads Automation
