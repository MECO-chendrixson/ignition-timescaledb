# Platform Selector - Choose Your Installation Path

Welcome to the Ignition + TimescaleDB Integration Guide! This documentation supports both **Windows Server** and **Linux (Ubuntu/Debian)** installations.

---

## Choose Your Platform

<table>
<tr>
<td width="50%" align="center">

### 🪟 Windows Server

**Recommended for:**
- Windows-based Ignition installations
- Organizations with Windows infrastructure
- Users familiar with Windows administration

**Supported Versions:**
- Windows Server 2016
- Windows Server 2019
- Windows Server 2022

**[Start Windows Installation →](01-installation-windows.md)**

</td>
<td width="50%" align="center">

### 🐧 Linux (Ubuntu/Debian)

**Recommended for:**
- Linux-based Ignition installations
- Organizations with Linux infrastructure
- Users familiar with Linux administration
- Cloud deployments (AWS, Azure, GCP)

**Supported Distributions:**
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Debian 11+

**[Start Linux Installation →](01-installation-linux.md)**

</td>
</tr>
</table>

---

## Installation Paths Overview

### Windows Server Path

1. **[Installation - Windows](01-installation-windows.md)**
   - Download and install PostgreSQL
   - Install TimescaleDB extension
   - Configure Windows Firewall
   - Set up remote connections

2. **[Database Setup - Windows](02-database-setup-windows.md)**
   - Create databases using SQL Shell
   - Configure user permissions
   - Set up automated backups with Task Scheduler

3. **[Ignition Configuration](03-ignition-configuration.md)**
   - Configure database connections
   - Set up historian, alarm log, audit log
   - Enable tag history

### Linux Path

1. **[Installation - Linux](01-installation-linux.md)**
   - Install PostgreSQL via apt
   - Install TimescaleDB extension
   - Configure firewall (UFW/firewalld)
   - Set up remote connections

2. **[Database Setup - Linux](02-database-setup-linux.md)**
   - Create databases using psql
   - Configure user permissions
   - Set up automated backups with cron

3. **[Ignition Configuration](03-ignition-configuration.md)**
   - Configure database connections
   - Set up historian, alarm log, audit log
   - Enable tag history

---

## Quick References

### Platform-Independent Guides

These guides work for both Windows and Linux:

- **[Quick Start Guide](00-quick-start.md)** - Fast-track 30-minute setup
- **[Quick Reference](04-quick-reference.md)** - Copy-paste commands for both platforms
- **[Ignition Configuration](03-ignition-configuration.md)** - Ignition setup (same for all platforms)

### Advanced Guides

- **[Data Migration](../examples/05-data-migration.md)** - Migrate existing historian data
- **[ML Integration](../examples/04-ml-integration.md)** - Machine learning workflows
- **[Troubleshooting](../troubleshooting/01-common-issues.md)** - Common problems and solutions

---

## Platform Comparison

| Feature | Windows Server | Linux (Ubuntu/Debian) |
|---------|----------------|----------------------|
| **Installation Method** | GUI installers | APT package manager |
| **Configuration Files** | `C:\Program Files\PostgreSQL\17\data\` | `/etc/postgresql/17/main/` |
| **Service Management** | `net start/stop` or Services.msc | `systemctl start/stop` |
| **Firewall** | Windows Defender Firewall | UFW or firewalld |
| **Backup Automation** | Task Scheduler | Cron jobs |
| **Remote Access** | RDP | SSH |
| **Performance** | Good | Excellent (typically better) |
| **Cost** | Requires Windows Server license | Free (open source) |
| **Best For** | Windows infrastructure | Cloud deployments, cost savings |

---

## System Requirements

### Minimum Requirements (Both Platforms)

- **RAM:** 4GB (8GB+ recommended)
- **Storage:** 20GB free space (more for production)
- **PostgreSQL:** Version 12+
- **TimescaleDB:** Version 2.0+
- **Ignition:** 8.1+ (8.3+ recommended)

### Recommended Production (Both Platforms)

- **RAM:** 16GB+
- **Storage:** SSD with 100GB+ free space
- **CPU:** 4+ cores
- **PostgreSQL:** Version 15 or 17
- **TimescaleDB:** Version 2.24+

---

## Need Help Choosing?

### Choose Windows Server if:
- ✅ Your Ignition server runs on Windows
- ✅ Your team has Windows administration experience
- ✅ You have existing Windows infrastructure
- ✅ You prefer GUI-based administration tools

### Choose Linux if:
- ✅ Your Ignition server runs on Linux
- ✅ Your team has Linux administration experience
- ✅ You're deploying to cloud (AWS, Azure, GCP)
- ✅ You want better performance and lower costs
- ✅ You prefer command-line administration

### Mixed Environment?

You can run PostgreSQL/TimescaleDB on a different OS than Ignition! For example:
- **Ignition on Windows** + **PostgreSQL on Linux** (common for cloud)
- **Ignition on Linux** + **PostgreSQL on Linux** (best performance)
- **Ignition on Windows** + **PostgreSQL on Windows** (simplest management)

Both platforms connect via JDBC the same way.

---

## Ready to Start?

<table>
<tr>
<td width="50%" align="center">

### **[🪟 Start Windows Installation](01-installation-windows.md)**

PostgreSQL + TimescaleDB on Windows Server

</td>
<td width="50%" align="center">

### **[🐧 Start Linux Installation](01-installation-linux.md)**

PostgreSQL + TimescaleDB on Ubuntu/Debian

</td>
</tr>
</table>

---

## Support

- **Troubleshooting:** [Common Issues Guide](../troubleshooting/01-common-issues.md)
- **Community:** [Ignition Forum](https://forum.inductiveautomation.com/)
- **Documentation:** [Main Index](../INDEX.md)

---

**Last Updated:** December 8, 2025  
**Maintained By:** Miller-Eads Automation
