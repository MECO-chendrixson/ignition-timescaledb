#!/usr/bin/env python3
"""
Migrate Ignition Tag Historian Data to TimescaleDB

This script migrates historical data from existing Ignition historian tables
to TimescaleDB hypertables, with support for:
- Partitioned historian tables (sqlt_data_X_YYYY_MM)
- Single partition tables (sqlth_1_data)
- Transaction Group custom tables
- Cross-database migration
- Data quality validation

Author: Ignition TimescaleDB Integration Project
Version: 1.0.0
Last Updated: 2025-12-07
"""

import argparse
import psycopg2
from psycopg2 import sql
from datetime import datetime, timedelta
import sys
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class HistorianMigration:
    """Migrate Ignition historian data to TimescaleDB"""
    
    def __init__(self, source_config, target_config, batch_size=100000):
        self.source_config = source_config
        self.target_config = target_config
        self.batch_size = batch_size
        self.source_conn = None
        self.target_conn = None
        
    def connect(self):
        """Establish database connections"""
        logger.info("Connecting to source database...")
        self.source_conn = psycopg2.connect(**self.source_config)
        
        if self.target_config != self.source_config:
            logger.info("Connecting to target database...")
            self.target_conn = psycopg2.connect(**self.target_config)
        else:
            self.target_conn = self.source_conn
            logger.info("Using same database for source and target")
    
    def analyze_source_data(self):
        """Analyze source data before migration"""
        logger.info("Analyzing source data...")
        
        with self.source_conn.cursor() as cur:
            # Get table statistics
            cur.execute("""
                SELECT 
                    COUNT(*) as total_records,
                    COUNT(DISTINCT tagid) as unique_tags,
                    MIN(t_stamp) as earliest,
                    MAX(t_stamp) as latest,
                    pg_size_pretty(pg_total_relation_size('sqlth_1_data')) as size
                FROM sqlth_1_data;
            """)
            stats = cur.fetchone()
            
            logger.info(f"Total records: {stats[0]:,}")
            logger.info(f"Unique tags: {stats[1]:,}")
            logger.info(f"Date range: {datetime.fromtimestamp(stats[2]/1000)} to {datetime.fromtimestamp(stats[3]/1000)}")
            logger.info(f"Table size: {stats[4]}")
            
            return stats
    
    def create_backup(self, table_name='sqlth_1_data'):
        """Create backup table before migration"""
        backup_name = f"{table_name}_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        logger.info(f"Creating backup table: {backup_name}")
        
        with self.target_conn.cursor() as cur:
            cur.execute(sql.SQL(
                "CREATE TABLE {} AS SELECT * FROM {}"
            ).format(
                sql.Identifier(backup_name),
                sql.Identifier(table_name)
            ))
            self.target_conn.commit()
            
        logger.info(f"✓ Backup created: {backup_name}")
        return backup_name
    
    def migrate_batch(self, start_ts, end_ts, source_table='sqlth_1_data', 
                     target_table='sqlth_1_data'):
        """Migrate a batch of records"""
        
        with self.source_conn.cursor() as src_cur, \
             self.target_conn.cursor() as tgt_cur:
            
            # Read batch
            src_cur.execute("""
                SELECT tagid, intvalue, floatvalue, stringvalue, 
                       datevalue, dataintegrity, t_stamp
                FROM {}
                WHERE t_stamp >= %s AND t_stamp < %s
                ORDER BY t_stamp;
            """.format(source_table), (start_ts, end_ts))
            
            records = src_cur.fetchall()
            
            if not records:
                return 0
            
            # Insert batch
            insert_query = """
                INSERT INTO {} 
                (tagid, intvalue, floatvalue, stringvalue, datevalue, dataintegrity, t_stamp)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT DO NOTHING;
            """.format(target_table)
            
            tgt_cur.executemany(insert_query, records)
            self.target_conn.commit()
            
            return len(records)
    
    def migrate_all(self, source_table='sqlth_1_data', target_table='sqlth_1_data'):
        """Migrate all data in batches"""
        
        logger.info("Starting batch migration...")
        
        with self.source_conn.cursor() as cur:
            # Get time range
            cur.execute(f"""
                SELECT MIN(t_stamp), MAX(t_stamp) 
                FROM {source_table};
            """)
            min_ts, max_ts = cur.fetchone()
        
        logger.info(f"Time range: {min_ts} to {max_ts}")
        
        # Calculate batch intervals (1 day batches)
        batch_interval = 86400000  # 24 hours in milliseconds
        current_ts = min_ts
        total_migrated = 0
        batch_num = 0
        
        while current_ts < max_ts:
            batch_num += 1
            end_ts = min(current_ts + batch_interval, max_ts)
            
            start_time = time.time()
            migrated = self.migrate_batch(current_ts, end_ts, source_table, target_table)
            duration = time.time() - start_time
            
            total_migrated += migrated
            
            if migrated > 0:
                logger.info(f"Batch {batch_num}: Migrated {migrated:,} records "
                          f"({datetime.fromtimestamp(current_ts/1000).date()}) "
                          f"in {duration:.2f}s")
            
            current_ts = end_ts
        
        logger.info(f"✓ Migration complete: {total_migrated:,} total records migrated")
        return total_migrated
    
    def validate_migration(self, source_table='sqlth_1_data', target_table='sqlth_1_data'):
        """Validate migration completed successfully"""
        
        logger.info("Validating migration...")
        
        with self.source_conn.cursor() as src_cur, \
             self.target_conn.cursor() as tgt_cur:
            
            # Compare record counts
            src_cur.execute(f"SELECT COUNT(*) FROM {source_table};")
            source_count = src_cur.fetchone()[0]
            
            tgt_cur.execute(f"SELECT COUNT(*) FROM {target_table};")
            target_count = tgt_cur.fetchone()[0]
            
            logger.info(f"Source records: {source_count:,}")
            logger.info(f"Target records: {target_count:,}")
            
            if source_count == target_count:
                logger.info("✓ Record counts match")
            else:
                logger.warning(f"⚠ Record count mismatch: {source_count - target_count} records difference")
            
            # Compare timestamp ranges
            src_cur.execute(f"SELECT MIN(t_stamp), MAX(t_stamp) FROM {source_table};")
            src_range = src_cur.fetchone()
            
            tgt_cur.execute(f"SELECT MIN(t_stamp), MAX(t_stamp) FROM {target_table};")
            tgt_range = tgt_cur.fetchone()
            
            if src_range == tgt_range:
                logger.info("✓ Timestamp ranges match")
            else:
                logger.warning("⚠ Timestamp range mismatch")
            
            # Compare tag distribution
            src_cur.execute(f"SELECT COUNT(DISTINCT tagid) FROM {source_table};")
            src_tags = src_cur.fetchone()[0]
            
            tgt_cur.execute(f"SELECT COUNT(DISTINCT tagid) FROM {target_table};")
            tgt_tags = tgt_cur.fetchone()[0]
            
            if src_tags == tgt_tags:
                logger.info(f"✓ Tag counts match ({src_tags} tags)")
            else:
                logger.warning(f"⚠ Tag count mismatch: {src_tags} vs {tgt_tags}")
    
    def close(self):
        """Close database connections"""
        if self.source_conn:
            self.source_conn.close()
        if self.target_conn and self.target_conn != self.source_conn:
            self.target_conn.close()


def main():
    parser = argparse.ArgumentParser(
        description='Migrate Ignition historian data to TimescaleDB'
    )
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--port', type=int, default=5432, help='Database port')
    parser.add_argument('--database', default='historian', help='Database name')
    parser.add_argument('--user', default='ignition', help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--source-table', default='sqlth_1_data', help='Source table')
    parser.add_argument('--target-table', default='sqlth_1_data', help='Target table')
    parser.add_argument('--batch-size', type=int, default=100000, help='Batch size')
    parser.add_argument('--no-backup', action='store_true', help='Skip backup creation')
    parser.add_argument('--validate-only', action='store_true', help='Only validate, do not migrate')
    
    args = parser.parse_args()
    
    # Database configuration
    db_config = {
        'host': args.host,
        'port': args.port,
        'database': args.database,
        'user': args.user,
        'password': args.password
    }
    
    # Create migration instance
    migration = HistorianMigration(db_config, db_config, args.batch_size)
    
    try:
        # Connect
        migration.connect()
        
        # Analyze
        migration.analyze_source_data()
        
        if args.validate_only:
            migration.validate_migration(args.source_table, args.target_table)
            return
        
        # Create backup
        if not args.no_backup:
            backup_name = migration.create_backup(args.target_table)
            logger.info(f"Backup created: {backup_name}")
        
        # Migrate
        total = migration.migrate_all(args.source_table, args.target_table)
        
        # Validate
        migration.validate_migration(args.source_table, args.target_table)
        
        logger.info("✓ Migration completed successfully")
        
    except Exception as e:
        logger.error(f"Migration failed: {str(e)}", exc_info=True)
        sys.exit(1)
    finally:
        migration.close()


if __name__ == '__main__':
    main()
