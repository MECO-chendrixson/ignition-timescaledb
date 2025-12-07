# Installation Guide

**Estimated Time:** 45-60 minutes  
**Difficulty:** Beginner to Intermediate

## Overview

This guide covers the complete installation process for PostgreSQL and TimescaleDB on both Windows and Linux systems. Choose the appropriate section for your operating system.

## Prerequisites

### System Requirements

**Minimum:**
- 4 GB RAM
- 20 GB available disk space
- Modern CPU (2+ cores)
- Administrator/root access

**Recommended:**
- 8+ GB RAM
- 100+ GB SSD storage
- 4+ CPU cores
- Dedicated database server

### Software Requirements

- Operating System: Windows Server 2016+, Ubuntu 20.04+, RHEL 8+, or similar
- Network connectivity to Ignition Gateway
- Web browser for accessing installation packages

## Windows Installation

### Part 1: Install PostgreSQL

#### Step 1: Download PostgreSQL

1. Visit [PostgreSQL Downloads](https://www.postgresql.org/download/windows/)
2. Download the latest **PostgreSQL 15** or **17** installer
3. Run the installer as Administrator

#### Step 2: PostgreSQL Installation Wizard

1. **Select Components:**
   - ✅ PostgreSQL Server
   - ✅ pgAdmin 4
   - ✅ Command Line Tools
   - ⬜ Stack Builder (optional)

2. **Data Directory:**
   - Default: `C:\Program Files\PostgreSQL\17\data`
   - Or choose custom location with sufficient space

3. **Set Password:**
   - Enter a strong password for the `postgres` superuser
   - **IMPORTANT:** Save this password securely

4. **Port:**
   - Default: `5432`
   - Change if port is already in use

5. **Locale:**
   - Default locale (typically `English, United States`)

6. Complete installation and allow through Windows Firewall if prompted

#### Step 3: Add PostgreSQL to System PATH

1. Right-click **This PC** → **Properties**
2. Click **Advanced system settings**
3. Click **Environment Variables**
4. Under **System variables**, select **Path** and click **Edit**
5. Click **New** and add:
   ```
   C:\Program Files\PostgreSQL\17\bin
   ```
6. Click **OK** on all dialogs

#### Step 4: Verify PostgreSQL Installation

Open **Command Prompt** and run:

```cmd
psql --version
```

Expected output:
```
psql (PostgreSQL) 17.x
```

### Part 2: Install TimescaleDB

#### Step 1: Download TimescaleDB

1. Visit [TimescaleDB Downloads](https://www.timescale.com/download)
2. Select **Self-hosted** → **Windows**
3. Download the installer for your PostgreSQL version

#### Step 2: Extract and Prepare

1. Extract the downloaded ZIP file to a temporary location
2. Note the location of the `timescaledb` folder

#### Step 3: Stop PostgreSQL Service

1. Open **Services** (press `Win+R`, type `services.msc`)
2. Find **postgresql-x64-17** service
3. Right-click → **Stop**

#### Step 4: Install TimescaleDB

1. Right-click `setup.exe` in the extracted folder
2. Select **Run as administrator**
3. When prompted, press **y** to tune PostgreSQL
4. Enter the PostgreSQL data directory path:
   ```
   C:\Program Files\PostgreSQL\17\data
   ```
5. Follow prompts, answering **y** to all tuning questions

#### Step 5: Start PostgreSQL Service

1. Return to **Services**
2. Right-click **postgresql-x64-17** → **Start**

#### Step 6: Verify TimescaleDB Installation

Open **Command Prompt** and run:

```cmd
psql -U postgres -c "SELECT default_version FROM pg_available_extensions WHERE name='timescaledb';"
```

Enter the postgres password when prompted. Expected output:
```
 default_version
-----------------
 2.13.0
```

---

## Linux Installation (Ubuntu/Debian)

### Part 1: Install PostgreSQL

#### Step 1: Update Package Index

```bash
sudo apt update
sudo apt upgrade -y
```

#### Step 2: Install PostgreSQL

```bash
# Install PostgreSQL 15
sudo apt install -y postgresql-15 postgresql-contrib-15

# Or install PostgreSQL 17 (if available)
# sudo apt install -y postgresql-17 postgresql-contrib-17
```

#### Step 3: Start and Enable PostgreSQL

```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
sudo systemctl status postgresql
```

Expected status: **active (running)**

#### Step 4: Set PostgreSQL Password

```bash
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'your_secure_password';"
```

Replace `your_secure_password` with a strong password.

### Part 2: Install TimescaleDB

#### Step 1: Add TimescaleDB Repository

```bash
# Add TimescaleDB APT repository
sudo sh -c "echo 'deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main' > /etc/apt/sources.list.d/timescaledb.list"

# Add repository GPG key
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add -
```

#### Step 2: Update and Install TimescaleDB

```bash
sudo apt update
sudo apt install -y timescaledb-2-postgresql-15

# Or for PostgreSQL 17
# sudo apt install -y timescaledb-2-postgresql-17
```

#### Step 3: Tune PostgreSQL for TimescaleDB

```bash
sudo timescaledb-tune --quiet --yes
```

This automatically configures PostgreSQL settings for optimal TimescaleDB performance.

#### Step 4: Restart PostgreSQL

```bash
sudo systemctl restart postgresql
sudo systemctl status postgresql
```

#### Step 5: Verify TimescaleDB Installation

```bash
sudo -u postgres psql -c "SELECT default_version FROM pg_available_extensions WHERE name='timescaledb';"
```

Expected output:
```
 default_version
-----------------
 2.13.0
```

---

## Linux Installation (RHEL/CentOS/Rocky)

### Part 1: Install PostgreSQL

#### Step 1: Add PostgreSQL Repository

```bash
# Install EPEL repository
sudo dnf install -y epel-release

# Add PostgreSQL repository
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Disable built-in PostgreSQL
sudo dnf -qy module disable postgresql
```

#### Step 2: Install PostgreSQL

```bash
sudo dnf install -y postgresql15-server postgresql15-contrib

# Or for PostgreSQL 17
# sudo dnf install -y postgresql17-server postgresql17-contrib
```

#### Step 3: Initialize and Start PostgreSQL

```bash
# Initialize database
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb

# Start and enable service
sudo systemctl start postgresql-15
sudo systemctl enable postgresql-15
sudo systemctl status postgresql-15
```

#### Step 4: Set PostgreSQL Password

```bash
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'your_secure_password';"
```

### Part 2: Install TimescaleDB

#### Step 1: Add TimescaleDB Repository

```bash
sudo tee /etc/yum.repos.d/timescale_timescaledb.repo <<EOL
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/8/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOL
```

#### Step 2: Install TimescaleDB

```bash
sudo dnf install -y timescaledb-2-postgresql-15
```

#### Step 3: Tune PostgreSQL

```bash
sudo timescaledb-tune --quiet --yes
```

#### Step 4: Restart PostgreSQL

```bash
sudo systemctl restart postgresql-15
sudo systemctl status postgresql-15
```

---

## Post-Installation Configuration

### Configure Remote Connections

To allow Ignition to connect from a remote server, edit PostgreSQL configuration files.

#### Linux Configuration

1. **Edit `postgresql.conf`:**

```bash
sudo nano /etc/postgresql/15/main/postgresql.conf
```

Find and modify:
```conf
listen_addresses = '*'          # Allow connections from any IP
```

2. **Edit `pg_hba.conf`:**

```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf
```

Add at the end (adjust subnet as needed):
```conf
# Allow connections from local network
host    all             all             192.168.1.0/24          scram-sha-256

# Or allow from any IP (less secure)
host    all             all             0.0.0.0/0               scram-sha-256
```

3. **Restart PostgreSQL:**

```bash
sudo systemctl restart postgresql
```

#### Windows Configuration

1. **Edit `postgresql.conf`:**

Open: `C:\Program Files\PostgreSQL\17\data\postgresql.conf`

Modify:
```conf
listen_addresses = '*'
```

2. **Edit `pg_hba.conf`:**

Open: `C:\Program Files\PostgreSQL\17\data\pg_hba.conf`

Add:
```conf
# IPv4 local connections:
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
```

3. **Restart PostgreSQL:**

Use Services (`services.msc`) to restart **postgresql-x64-17**

### Configure Firewall

#### Linux (UFW)

```bash
sudo ufw allow 5432/tcp
sudo ufw reload
```

#### Linux (firewalld)

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

#### Windows Firewall

```powershell
New-NetFirewallRule -DisplayName "PostgreSQL" -Direction Inbound -Protocol TCP -LocalPort 5432 -Action Allow
```

---

## Verification Tests

### Test Local Connection

```bash
psql -U postgres -h localhost -c "SELECT version();"
```

### Test Remote Connection

From the Ignition server:

```bash
psql -U postgres -h <database-server-ip> -c "SELECT version();"
```

### Verify TimescaleDB

```bash
psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb; SELECT * FROM timescaledb_information.license;"
```

Expected output showing license type (Apache 2 for community edition).

---

## Troubleshooting Installation Issues

### PostgreSQL Won't Start

**Check logs:**
```bash
# Linux
sudo tail -f /var/log/postgresql/postgresql-15-main.log

# Windows
# Check: C:\Program Files\PostgreSQL\17\data\log\
```

**Common causes:**
- Port 5432 already in use
- Data directory permissions incorrect
- Insufficient disk space

### TimescaleDB Extension Not Found

**Verify shared libraries are loaded:**

```sql
SHOW shared_preload_libraries;
```

Should include `timescaledb`.

**If not, edit `postgresql.conf`:**
```conf
shared_preload_libraries = 'timescaledb'
```

Then restart PostgreSQL.

### Connection Refused

**Check PostgreSQL is listening:**

```bash
# Linux
sudo netstat -tuln | grep 5432

# Windows
netstat -an | findstr 5432
```

**Verify `pg_hba.conf` allows connections**

### Permission Denied

**Grant necessary privileges:**

```sql
GRANT ALL PRIVILEGES ON DATABASE historian TO ignition;
ALTER DATABASE historian OWNER TO ignition;
```

---

## Next Steps

✅ PostgreSQL and TimescaleDB are now installed and configured.

**Continue to:**
- [Database Setup](02-database-setup.md) - Create Ignition databases and users
- [Ignition Configuration](03-ignition-configuration.md) - Configure Ignition historian

---

## Additional Resources

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [PostgreSQL Wiki - Installation](https://wiki.postgresql.org/wiki/Detailed_installation_guides)

**Last Updated:** December 7, 2025
