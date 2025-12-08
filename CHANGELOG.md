# Changelog

All notable changes to this documentation project will be documented in this file.

## [1.0.0] - 2025-12-07

### Added

- Initial documentation structure
- Complete installation guides for Windows and Linux
- Database setup scripts and procedures
- Ignition 8.3.2+ configuration guide
- Quick start guide for experienced users
- Hypertable configuration scripts
- Continuous aggregates setup and examples
- Comprehensive troubleshooting guide
- Common issues and solutions
- SQL schema creation scripts
- Performance optimization guidance
- Directory structure for organized documentation

### Documentation Sections

- Getting Started (4 documents)
- Configuration (setup pending)
- Optimization (setup pending)
- Troubleshooting (1 document)
- Examples (setup pending)
- Reference (setup pending)

### SQL Scripts

- Database creation script
- Hypertable configuration script
- Continuous aggregates script

### Features

- Step-by-step installation procedures
- Automated setup scripts
- Verification steps for each stage
- Production-ready configurations
- Security best practices
- Performance tuning guidelines

## [1.1.0] - 2025-12-07

### Added

- **Data Migration Guide** - Comprehensive guide for migrating existing historian data to TimescaleDB
- **ML Integration Guide** - Complete machine learning integration documentation with examples
- **Migration Script** - Python script for automated data migration with validation
- **ML Feature Extraction** - SQL views and Python code for feature engineering
- **Migration Reference** - Quick reference for migration strategies

### Documentation

- Data migration scenarios and strategies
- ML use cases (predictive maintenance, anomaly detection, process optimization)
- Python integration examples with TimescaleDB
- Jython examples for Ignition Gateway scripts
- LSTM forecasting example
- Anomaly detection with Isolation Forest
- Feature engineering with SQL window functions
- Migration validation procedures
- Rollback procedures

### Scripts

- `migrate_historian_data.py` - Production-ready migration script
- Batch processing with progress tracking
- Automatic backup creation
- Data validation post-migration

## [1.2.0] - 2025-12-08

### Added

- **Quick Reference Guide** - Copy-paste command reference for rapid deployment
- **Ignition 8.1 Support** - Documentation now covers both 8.1 and 8.3 configuration paths
- **Version Comparison Table** - Side-by-side comparison of 8.1 vs 8.3 navigation paths
- **Connection URL Examples** - Complete examples for local, remote, SSL, and custom port scenarios
- **Common Pitfalls Section** - Guide to avoid common configuration mistakes
- **Essential Configuration Checklist** - Must-do items for proper setup
- **Security Checklist** - Production security best practices

### Documentation

- Quick reference with all setup commands in one place
- Version-specific configuration instructions
- Command reference for Windows and Linux
- Verification commands for each setup stage
- Links to detailed documentation for each section

### Changed

- Updated README.md to highlight Quick Reference guide
- Updated INDEX.md to include Quick Reference document
- Updated maintainer information to Miller-Eads Automation
- Updated version to 1.2.0 across documentation

## [Unreleased]

### Planned

- Configuration section completion (compression, retention details)
- Optimization guides (query tuning, index strategies)
- More example queries
- Backup and recovery procedures
- High availability setup
- Monitoring and alerting guides
- Docker deployment examples

---

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
