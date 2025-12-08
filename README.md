# Ignition SCADA + TimescaleDB Integration Guide

**Version:** 1.3.0  
**Last Updated:** December 8, 2025  
**Compatible with:** Ignition 8.1+ (LTS) and 8.3+ (Current LTS), TimescaleDB 2.24+, Windows Server 2016+, Ubuntu 20.04+

## Overview

This documentation provides comprehensive guidance for integrating TimescaleDB with Ignition SCADA's Tag Historian system. TimescaleDB extends PostgreSQL with time-series optimizations including automatic partitioning, compression, continuous aggregates, and retention policies—making it an excellent choice for long-term industrial data storage and analytics.

## Why TimescaleDB for Ignition?

### Key Benefits

- **10-20x Storage Reduction**: Advanced compression reduces database size dramatically
- **Superior Query Performance**: Optimized time-series queries with native indexing
- **Automatic Data Management**: Built-in retention policies and partitioning
- **Hierarchical Downsampling**: Continuous aggregates for multi-resolution data
- **SQL Compatibility**: Full PostgreSQL ecosystem and tool support
- **ML-Ready**: Easy integration with Python, R, and analytical tools

### Use Cases

- Long-term historical data storage (years to decades)
- Multi-resolution trending and reporting
- Machine learning and predictive maintenance
- Process optimization and statistical analysis
- Compliance and regulatory record-keeping
- Cross-site data aggregation and analysis

## Documentation Structure

### Getting Started

**Choose Your Platform:**
- [🎯 Platform Selector](docs/getting-started/00-platform-selector.md) - **START HERE** - Choose Windows or Linux

**Windows Server:**
- [Installation - Windows](docs/getting-started/01-installation-windows.md) - PostgreSQL + TimescaleDB on Windows
- [Database Setup - Windows](docs/getting-started/02-database-setup-windows.md) - Create databases on Windows

**Linux (Ubuntu/Debian):**
- [Installation - Linux](docs/getting-started/01-installation-linux.md) - PostgreSQL + TimescaleDB on Linux
- [Database Setup - Linux](docs/getting-started/02-database-setup-linux.md) - Create databases on Linux

**Platform-Independent:**
- [Quick Start Guide](docs/getting-started/00-quick-start.md) - Fast-track setup for experienced users
- [Quick Reference](docs/getting-started/04-quick-reference.md) - Copy-paste commands for both platforms
- [Ignition Configuration](docs/getting-started/03-ignition-configuration.md) - Configure Ignition historian

### Configuration
- [Hypertable Configuration](docs/configuration/01-hypertable-setup.md) - Convert tables to hypertables
- [Compression Settings](docs/configuration/02-compression.md) - Configure data compression
- [Retention Policies](docs/configuration/03-retention-policies.md) - Automatic data lifecycle management
- [Continuous Aggregates](docs/configuration/04-continuous-aggregates.md) - Multi-resolution downsampling

### Optimization
- [Performance Tuning](docs/optimization/01-performance-tuning.md) - Index optimization and query performance
- [Query Optimization](docs/optimization/02-query-optimization.md) - Best practices for efficient queries
- [Storage Optimization](docs/optimization/03-storage-optimization.md) - Minimize disk usage
- [Scaling Strategies](docs/optimization/04-scaling.md) - Handle high-volume data

### Troubleshooting
- [Common Issues](docs/troubleshooting/01-common-issues.md) - Known problems and solutions
- [Performance Issues](docs/troubleshooting/02-performance-issues.md) - Diagnose slow queries
- [Data Quality](docs/troubleshooting/03-data-quality.md) - Resolve data integrity problems
- [Diagnostic Tools](docs/troubleshooting/04-diagnostic-tools.md) - Utilities and commands

### Examples
- [Basic Queries](docs/examples/01-basic-queries.md) - Common query patterns
- [Continuous Aggregate Examples](docs/examples/02-continuous-aggregates.md) - Real-world aggregate configurations
- [Scripting Examples](docs/examples/03-scripting-examples.md) - Python and Jython scripts
- [ML Integration](docs/examples/04-ml-integration.md) - Machine learning workflows
- [Data Migration](docs/examples/05-data-migration.md) - **NEW!** Migrate existing historian data to TimescaleDB

### Reference
- [Table Schema Reference](docs/reference/01-table-schema.md) - Database table structures
- [SQL Functions](docs/reference/02-sql-functions.md) - TimescaleDB function reference
- [Ignition API Reference](docs/reference/03-ignition-api.md) - Historian scripting functions
- [Best Practices](docs/reference/04-best-practices.md) - Recommended patterns

## Quick Links

### Scripts
- [Setup Scripts](scripts/setup/) - Automated installation and configuration
- [Maintenance Scripts](scripts/maintenance/) - Backup, monitoring, and cleanup
- [Migration Scripts](scripts/migration/) - Migrate from other historians

### SQL Resources
- [Schema Scripts](sql/schema/) - Database and table creation
- [Query Library](sql/queries/) - Pre-built queries for common tasks
- [Maintenance Queries](sql/maintenance/) - Administrative queries

### Additional Resources
- [Official Ignition Documentation](https://docs.inductiveautomation.com/docs/8.3/intro)
- [TimescaleDB Documentation](https://www.tigerdata.com/docs/)
- [Community Forum Discussions](https://forum.inductiveautomation.com/t/timeseries-db-for-postgresql/21770)
- [GitHub Examples](https://github.com/aRaymo/Using-TimeScaleDB-with-Ignition)

## System Requirements

### Minimum Requirements
- **Ignition:** Version 8.3.0 or higher (8.3 is current LTS)
- **PostgreSQL:** Version 12 or higher
- **TimescaleDB:** Version 2.0 or higher (2.24+ recommended)
- **RAM:** 4GB minimum (8GB+ recommended)
- **Storage:** Depends on data volume and retention period

### Recommended Requirements
- **Ignition:** Version 8.3.x (latest)
- **PostgreSQL:** Version 13 or higher (15-18 supported, 17+ recommended)
- **TimescaleDB:** Version 2.24+ (latest stable)
- **RAM:** 16GB+ for production systems
- **Storage:** SSD for database storage
- **Network:** Low-latency connection between Ignition and database

## Support and Contributing

### Getting Help
- Review the [Troubleshooting Guide](docs/troubleshooting/01-common-issues.md)
- Check the [Ignition Forum](https://forum.inductiveautomation.com/)
- Consult [TimescaleDB Community](https://timescale.com/community)

### Project Status
- ✅ Production-ready for Ignition 8.3.0+ (LTS)
- ✅ Tested with TimescaleDB 2.24+
- ✅ PostgreSQL 15+ support verified
- 🔄 Continuous updates based on community feedback

## License

This documentation is provided as-is for educational and reference purposes.

## Acknowledgments

- Inductive Automation for the Ignition platform
- TimescaleDB team for the excellent time-series extension
- Ignition community members who shared their experiences
- Special thanks to aRaymo for the initial GitHub implementation

---

**Last Review:** December 8, 2025  
**Document Version:** 1.3.0  
**Maintained By:** Miller-Eads Automation
