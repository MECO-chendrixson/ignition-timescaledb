# Documentation Index

Complete index of all documentation for Ignition + TimescaleDB integration.

## Quick Navigation

- [Main README](../README.md)
- [Quick Start](getting-started/00-quick-start.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [Changelog](../CHANGELOG.md)

---

## Getting Started

### Platform Selection

| Document | Description | For |
|----------|-------------|-----|
| [🎯 Platform Selector](getting-started/00-platform-selector.md) | **START HERE** - Choose your platform | Everyone |

### Windows Server Path

| Document | Description | Difficulty |
|----------|-------------|------------|
| [Installation - Windows](getting-started/01-installation-windows.md) | PostgreSQL + TimescaleDB on Windows | Beginner |
| [Database Setup - Windows](getting-started/02-database-setup-windows.md) | Create databases on Windows | Beginner |

### Linux (Ubuntu/Debian) Path

| Document | Description | Difficulty |
|----------|-------------|------------|
| [Installation - Linux](getting-started/01-installation-linux.md) | PostgreSQL + TimescaleDB on Linux | Beginner |
| [Database Setup - Linux](getting-started/02-database-setup-linux.md) | Create databases on Linux | Beginner |

### Platform-Independent

| Document | Description | Difficulty |
|----------|-------------|------------|
| [Quick Start Guide](getting-started/00-quick-start.md) | Fast-track setup (30 min) | Intermediate |
| [Quick Reference](getting-started/04-quick-reference.md) | Copy-paste commands for 8.1 & 8.3 | All Levels |
| [Ignition Configuration](getting-started/03-ignition-configuration.md) | Configure Ignition historian | Intermediate |

---

## Configuration

| Document | Description | Status |
|----------|-------------|--------|
| Hypertable Setup | Convert tables to hypertables | Pending |
| Compression Settings | Configure data compression | Pending |
| Retention Policies | Automatic data lifecycle | Pending |
| Continuous Aggregates | Multi-resolution downsampling | Pending |

---

## Optimization

| Document | Description | Status |
|----------|-------------|--------|
| Performance Tuning | Index optimization, query performance | Pending |
| Query Optimization | Best practices for queries | Pending |
| Storage Optimization | Minimize disk usage | Pending |
| Scaling Strategies | Handle high-volume data | Pending |

---

## Troubleshooting

| Document | Description | Status |
|----------|-------------|--------|
| [Common Issues](troubleshooting/01-common-issues.md) | Known problems and solutions | Complete |
| Performance Issues | Diagnose slow queries | Pending |
| Data Quality | Resolve data integrity problems | Pending |
| Diagnostic Tools | Utilities and commands | Pending |

---

## Examples

| Document | Description | Status |
|----------|-------------|--------|
| Basic Queries | Common query patterns | Pending |
| Continuous Aggregate Examples | Real-world configurations | Pending |
| Scripting Examples | Python and Jython scripts | Pending |
| ML Integration | Machine learning workflows | Pending |

---

## Reference

| Document | Description | Status |
|----------|-------------|--------|
| Table Schema Reference | Database table structures | Pending |
| SQL Functions | TimescaleDB function reference | Pending |
| Ignition API Reference | Historian scripting functions | Pending |
| Best Practices | Recommended patterns | Pending |

---

## SQL Scripts

Located in `sql/` directory:

### Schema Scripts (`sql/schema/`)

| Script | Purpose |
|--------|---------|
| [01-create-databases.sql](../sql/schema/01-create-databases.sql) | Create databases and users |
| [02-configure-hypertables.sql](../sql/schema/02-configure-hypertables.sql) | Setup hypertables and policies |
| [03-continuous-aggregates.sql](../sql/schema/03-continuous-aggregates.sql) | Create hierarchical aggregates |

### Query Scripts (`sql/queries/`)

Status: Pending

### Maintenance Scripts (`sql/maintenance/`)

Status: Pending

---

## Setup Scripts

Located in `scripts/` directory:

### Setup (`scripts/setup/`)

Status: Pending

### Maintenance (`scripts/maintenance/`)

Status: Pending

### Migration (`scripts/migration/`)

Status: Pending

---

## Resources

### External Links

- [Ignition 8.3 Documentation](https://docs.inductiveautomation.com/docs/8.3/)
- [TimescaleDB Documentation](https://www.tigerdata.com/docs/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Ignition Forum](https://forum.inductiveautomation.com/)
- [TimescaleDB Community](https://timescale.com/community)

### Community Resources

- [Ignition Forum - TimescaleDB Thread](https://forum.inductiveautomation.com/t/timeseries-db-for-postgresql/21770)
- [GitHub - aRaymo Implementation](https://github.com/aRaymo/Using-TimeScaleDB-with-Ignition)
- [ICS Texas Wiki](https://wiki.icstexas.com/books/ignition/page/using-postgresql-and-timescaledb-with-ignition)

---

## Document Status Legend

- ✅ **Complete** - Fully documented and reviewed
- 🔄 **In Progress** - Currently being written
- 📝 **Pending** - Planned for future release
- 🔧 **Review** - Needs technical review

---

**Last Updated:** December 8, 2025  
**Version:** 1.3.0
