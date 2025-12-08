# Installation Guide - Linux (Ubuntu/Debian)

**Platform:** Ubuntu 20.04+, Debian 11+  
**Estimated Time:** 20-30 minutes  
**Difficulty:** Beginner  
**Prerequisites:** sudo/root access to Linux server

---

## Overview

This guide covers installing PostgreSQL and TimescaleDB on Ubuntu/Debian Linux for use with Ignition SCADA. For Windows installation, see [Installation Guide - Windows](01-installation-windows.md).

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Update System](#update-system)
3. [Install PostgreSQL](#install-postgresql)
4. [Install TimescaleDB](#install-timescaledb)
5. [Configure PostgreSQL for Remote Connections](#configure-postgresql-for-remote-connections)
6. [Configure Firewall](#configure-firewall)
7. [Verify Installation](#verify-installation)
8. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Minimum Requirements
- **OS:** Ubuntu 20.04 LTS or Debian 11+
- **RAM:** 4GB (8GB+ recommended)
- **Storage:** 20GB free space (more for production data)
- **PostgreSQL:** Version 13+ (15-18 supported, 17+ recommended)
- **TimescaleDB:** Version 2.0+ (2.24+ recommended)

### Recommended Production Requirements
- **OS:** Ubuntu 22.04 LTS or Ubuntu 24.04 LTS
- **RAM:** 16GB+
- **Storage:** SSD with 100GB+ free space
- **CPU:** 4+ cores

---

## Update System

### Step 1: Update Package Lists

```bash
sudo apt update
```

### Step 2: Upgrade Existing Packages (Optional)

```bash
sudo apt upgrade -y
```

---

## Install PostgreSQL

### Step 1: Add PostgreSQL APT Repository

**For Ubuntu/Debian:**

```bash
# Install prerequisites
sudo apt install -y wget gnupg2 lsb-release

# Add PostgreSQL GPG key
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# Add PostgreSQL repository
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list

# Update package lists
sudo apt update
```

### Step 2: Install PostgreSQL

**Install PostgreSQL 17 or 18 (recommended):**

**For PostgreSQL 18 (latest):**

```bash
sudo apt install -y postgresql-18 postgresql-client-18 postgresql-contrib-18
```

```bash
sudo apt install -y postgresql-17 postgresql-client-17 postgresql-contrib-17
```

**Or install PostgreSQL 15:**

```bash
sudo apt install -y postgresql-15 postgresql-client-15 postgresql-contrib-15
```

### Step 3: Verify PostgreSQL is Running

```bash
sudo systemctl status postgresql
```

**Expected:** `Active: active (running)`

### Step 4: Enable PostgreSQL on Boot

```bash
sudo systemctl enable postgresql
```

---

## Install TimescaleDB

### Step 1: Add TimescaleDB Repository

```bash
# Add Timescale GPG key
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg

# Add repository for Ubuntu 22.04 (adjust for your version)
echo "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main" | sudo tee /etc/apt/sources.list.d/timescaledb.list

# Update package lists
sudo apt update
```

### Step 2: Install TimescaleDB

**For PostgreSQL 17:**

```bash
sudo apt install -y timescaledb-2-postgresql-17
```

**For PostgreSQL 15:**

```bash
sudo apt install -y timescaledb-2-postgresql-15
```

### Step 3: Run TimescaleDB Tuning Script

This script optimizes PostgreSQL configuration for TimescaleDB:

```bash
sudo timescaledb-tune --quiet --yes
```

**What it does:**
- Adjusts shared_buffers based on available RAM
- Sets effective_cache_size
- Configures max_wal_size
- Sets work_mem and maintenance_work_mem
- Adds timescaledb to shared_preload_libraries

### Step 4: Restart PostgreSQL

```bash
sudo systemctl restart postgresql
```

### Step 5: Verify TimescaleDB Installation

```bash
sudo -u postgres psql -c "SELECT default_version FROM pg_available_extensions WHERE name = 'timescaledb';"
```

**Expected:** Version number displayed (e.g., 2.24.0)

---

## Configure PostgreSQL for Remote Connections

If Ignition is on a different server than PostgreSQL, you need to enable remote connections.

### Step 1: Edit postgresql.conf

**For PostgreSQL 17:**

```bash
sudo nano /etc/postgresql/17/main/postgresql.conf
```

**For PostgreSQL 15:**

```bash
sudo nano /etc/postgresql/15/main/postgresql.conf
```

**Find and change:**

```ini
# From:
#listen_addresses = 'localhost'

# To:
listen_addresses = '*'
```

**Save:** `Ctrl + O`, `Enter`, `Ctrl + X`

### Step 2: Edit pg_hba.conf

**For PostgreSQL 17:**

```bash
sudo nano /etc/postgresql/17/main/pg_hba.conf
```

**For PostgreSQL 15:**

```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf
```

**Add at the end of the file:**

```ini
# Allow connections from Ignition server(s)
# Adjust IP range for your network
host    all    all    192.168.1.0/24    scram-sha-256
```

**For specific IP:**
```ini
host    all    all    192.168.1.100/32    scram-sha-256
```

**For any IP (DEVELOPMENT ONLY - NOT SECURE):**
```ini
host    all    all    0.0.0.0/0    scram-sha-256
```

**Save:** `Ctrl + O`, `Enter`, `Ctrl + X`

### Step 3: Restart PostgreSQL

```bash
sudo systemctl restart postgresql
```

---

## Configure Firewall

### For UFW (Ubuntu)

```bash
# Allow PostgreSQL port
sudo ufw allow 5432/tcp

# Check status
sudo ufw status
```

### For firewalld (RHEL/CentOS)

```bash
# Allow PostgreSQL port
sudo firewall-cmd --permanent --add-port=5432/tcp

# Reload firewall
sudo firewall-cmd --reload

# Check status
sudo firewall-cmd --list-ports
```

### For iptables (Manual)

```bash
# Allow PostgreSQL port
sudo iptables -A INPUT -p tcp --dport 5432 -j ACCEPT

# Save rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

---

## Verify Installation

### Step 1: Check PostgreSQL Service

```bash
sudo systemctl status postgresql
```

**Expected:** `Active: active (running)`

### Step 2: Check PostgreSQL Version

```bash
sudo -u postgres psql -c "SELECT version();"
```

**Expected:** PostgreSQL version information

### Step 3: Check TimescaleDB Extension

```bash
sudo -u postgres psql -c "SELECT default_version, installed_version FROM pg_available_extensions WHERE name = 'timescaledb';"
```

**Expected:** Version numbers displayed

### Step 4: Test Connection Locally

```bash
sudo -u postgres psql
```

**At psql prompt:**

```sql
-- Check PostgreSQL version
SELECT version();

-- Create test database
CREATE DATABASE test_db;

-- Connect to test database
\c test_db

-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Verify TimescaleDB
SELECT * FROM timescaledb_information.hypertables;

-- Exit
\q
```

### Step 5: Test Remote Connection (Optional)

From Ignition server or another machine:

```bash
psql -h <postgres-server-ip> -U postgres -d postgres
```

Enter postgres password when prompted.

---

## Troubleshooting

### PostgreSQL Service Won't Start

**Check service status:**

```bash
sudo systemctl status postgresql
```

**Check logs:**

```bash
# For PostgreSQL 17
sudo tail -f /var/log/postgresql/postgresql-17-main.log

# For PostgreSQL 15
sudo tail -f /var/log/postgresql/postgresql-15-main.log
```

**Common issues:**

**1. Port already in use:**

```bash
sudo netstat -tulpn | grep 5432
```

If port is in use, change port in `postgresql.conf`:
```ini
port = 5433
```

**2. Data directory permissions:**

```bash
# For PostgreSQL 17
sudo chown -R postgres:postgres /var/lib/postgresql/17/main
sudo chmod 700 /var/lib/postgresql/17/main
```

**3. Configuration error:**

Check configuration syntax:
```bash
# For PostgreSQL 17
sudo -u postgres /usr/lib/postgresql/17/bin/postgres -C config_file
```

### TimescaleDB Extension Not Loading

**Symptoms:** Error when running `CREATE EXTENSION timescaledb;`

**Check shared_preload_libraries:**

```bash
# For PostgreSQL 17
sudo grep shared_preload_libraries /etc/postgresql/17/main/postgresql.conf
```

**Should show:**
```ini
shared_preload_libraries = 'timescaledb'
```

**If missing, add it:**

```bash
sudo nano /etc/postgresql/17/main/postgresql.conf
```

Add or update:
```ini
shared_preload_libraries = 'timescaledb'
```

**Restart PostgreSQL:**

```bash
sudo systemctl restart postgresql
```

### Cannot Connect Remotely

**Symptoms:** Connection refused from Ignition server

**Check PostgreSQL is listening:**

```bash
sudo netstat -tulpn | grep 5432
```

**Should show:** `0.0.0.0:5432` or `*:5432` (not just `127.0.0.1:5432`)

**Verify listen_addresses:**

```bash
# For PostgreSQL 17
sudo grep listen_addresses /etc/postgresql/17/main/postgresql.conf
```

**Should show:**
```ini
listen_addresses = '*'
```

**Verify pg_hba.conf:**

```bash
# For PostgreSQL 17
sudo cat /etc/postgresql/17/main/pg_hba.conf | grep -v "^#" | grep -v "^$"
```

**Check firewall:**

```bash
# UFW
sudo ufw status

# firewalld
sudo firewall-cmd --list-ports

# iptables
sudo iptables -L -n | grep 5432
```

**Test connection from Ignition server:**

```bash
# Check if port is reachable
nc -zv <postgres-server-ip> 5432

# Or use telnet
telnet <postgres-server-ip> 5432
```

### Permission Denied Errors

**Symptoms:** Permission errors when creating databases or extensions

**Solution:** Ensure you're running commands as postgres user:

```bash
sudo -u postgres psql
```

Or grant necessary permissions to your user.

### Slow Performance

**Check system resources:**

```bash
# Memory usage
free -h

# Disk I/O
iostat -x 1

# PostgreSQL active connections
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"
```

**Tune PostgreSQL:**

```bash
# Re-run tuning script
sudo timescaledb-tune --quiet --yes

# Restart PostgreSQL
sudo systemctl restart postgresql
```

---

## Performance Tuning for Linux

### Recommended postgresql.conf Settings

For a Linux server with 16GB RAM:

```ini
# Memory Settings
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
work_mem = 64MB

# Checkpoint Settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
max_wal_size = 4GB
min_wal_size = 1GB

# Query Tuning
random_page_cost = 1.1  # For SSD
effective_io_concurrency = 200  # For SSD

# Connection Settings
max_connections = 100

# TimescaleDB Settings
timescaledb.max_background_workers = 8
```

**Edit configuration:**

```bash
# For PostgreSQL 17
sudo nano /etc/postgresql/17/main/postgresql.conf
```

**Restart PostgreSQL:**

```bash
sudo systemctl restart postgresql
```

### Linux Kernel Tuning

**For production systems, consider these kernel parameters:**

```bash
sudo nano /etc/sysctl.conf
```

**Add:**

```ini
# PostgreSQL recommendations
vm.swappiness = 10
vm.overcommit_memory = 2
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
```

**Apply changes:**

```bash
sudo sysctl -p
```

---

## Security Hardening

### Set Strong postgres Password

```bash
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'your_secure_password';"
```

### Create Limited User for Ignition

Instead of using postgres superuser, create a limited user:

```bash
sudo -u postgres psql
```

```sql
CREATE USER ignition WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE historian TO ignition;
\q
```

### Enable SSL/TLS (Optional)

**Generate self-signed certificate:**

```bash
# For PostgreSQL 17
cd /var/lib/postgresql/17/main

# Generate key and certificate
sudo -u postgres openssl req -new -x509 -days 365 -nodes -text -out server.crt -keyout server.key -subj "/CN=postgres.example.com"

# Set permissions
sudo -u postgres chmod 600 server.key
```

**Enable SSL in postgresql.conf:**

```bash
sudo nano /etc/postgresql/17/main/postgresql.conf
```

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

**Restart PostgreSQL:**

```bash
sudo systemctl restart postgresql
```

---

## Next Steps

✅ PostgreSQL and TimescaleDB are now installed on Linux.

**Continue to:**
- [Database Setup - Linux](02-database-setup-linux.md) - Create Ignition databases
- [Ignition Configuration](03-ignition-configuration.md) - Configure Ignition historian

**Alternative Path:**
- [Installation Guide - Windows](01-installation-windows.md) - For Windows installations

---

## Additional Resources

- [PostgreSQL Linux Documentation](https://www.postgresql.org/docs/current/install-linux.html)
- [TimescaleDB Linux Installation](https://www.tigerdata.com/docs/self-hosted/latest/install/installation-linux/)
- [PostgreSQL Ubuntu Installation](https://www.postgresql.org/download/linux/ubuntu/)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)

---

**Last Updated:** December 8, 2025  
**Platform:** Linux (Ubuntu/Debian)  
**Maintained By:** Miller-Eads Automation
