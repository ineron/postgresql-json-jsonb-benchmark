#!/usr/bin/env python3
"""
PostgreSQL JSON vs JSONB Benchmark Runner
Automates the benchmark execution and generates performance reports

Requirements:
- psycopg2-binary
- python-dotenv (optional, for .env file support)
"""

import psycopg2
import time
import json
import sys
import os
from datetime import datetime
from typing import Dict, List, Any

class PostgreSQLBenchmark:
    def __init__(self, connection_params: Dict[str, str]):
        """Initialize benchmark with database connection parameters"""
        self.conn_params = connection_params
        self.results = {
            'test_info': {
                'timestamp': datetime.now().isoformat(),
                'postgresql_version': None,
                'server_info': 'Dell PowerEdge R450, 2x Intel Xeon Silver 4310 24/48 cores @ 2.1GHz'
            },
            'insert_performance': {},
            'storage_sizes': {},
            'query_performance': {},
            'update_performance': {}
        }
    
    def connect(self):
        """Establish database connection"""
        try:
            self.conn = psycopg2.connect(**self.conn_params)
            self.conn.autocommit = True
            self.cur = self.conn.cursor()
            
            # Get PostgreSQL version
            self.cur.execute("SELECT version()")
            self.results['test_info']['postgresql_version'] = self.cur.fetchone()[0]
            print(f"Connected to: {self.results['test_info']['postgresql_version']}")
            
        except Exception as e:
            print(f"Connection failed: {e}")
            sys.exit(1)
    
    def setup_tables(self):
        """Create test tables and indexes"""
        print("Setting up test tables...")
        
        setup_sql = """
        -- Drop existing tables
        DROP TABLE IF EXISTS json_test CASCADE;
        DROP TABLE IF EXISTS jsonb_test CASCADE;
        
        -- Create tables
        CREATE TABLE json_test (
            id SERIAL PRIMARY KEY,
            data JSON,
            created_at TIMESTAMP DEFAULT NOW()
        );
        
        CREATE TABLE jsonb_test (
            id SERIAL PRIMARY KEY,
            data JSONB,
            created_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Create test data generation function
        CREATE OR REPLACE FUNCTION generate_test_json(i INTEGER)
        RETURNS TEXT AS $$
        BEGIN
            RETURN format('{
                "user_id": %s,
                "username": "user_%s",
                "profile": {
                    "name": "User %s",
                    "age": %s,
                    "city": "City_%s",
                    "preferences": {
                        "theme": "%s",
                        "language": "en",
                        "notifications": %s
                    }
                },
                "orders": [
                    {"id": %s, "amount": %s, "status": "completed"},
                    {"id": %s, "amount": %s, "status": "pending"}
                ],
                "metadata": {
                    "last_login": "2024-12-%s",
                    "ip_address": "192.168.1.%s",
                    "user_agent": "Browser_%s"
                }
            }',
            i, i, i, (i % 50) + 18, (i % 100) + 1,
            CASE (i % 3) WHEN 0 THEN 'dark' WHEN 1 THEN 'light' ELSE 'auto' END,
            CASE (i % 2) WHEN 0 THEN 'true' ELSE 'false' END,
            i * 2, (i % 1000) + 10, (i * 2) + 1, (i % 500) + 5,
            (i % 30) + 1, (i % 254) + 1, (i % 10) + 1
            );
        END;
        $$ LANGUAGE plpgsql;
        """
        
        self.cur.execute(setup_sql)
        print("Tables and functions created successfully")
    
    def benchmark_inserts(self, record_count: int = 1000000):
        """Benchmark INSERT performance"""
        print(f"Benchmarking INSERT performance with {record_count:,} records...")
        
        # JSON INSERT
        start_time = time.time()
        self.cur.execute(f"""
            INSERT INTO json_test (data)
            SELECT generate_test_json(i)::JSON
            FROM generate_series(1, {record_count}) AS i
        """)
        json_insert_time = time.time() - start_time
        
        # JSONB INSERT
        start_time = time.time()
        self.cur.execute(f"""
            INSERT INTO jsonb_test (data)
            SELECT generate_test_json(i)::JSONB
            FROM generate_series(1, {record_count}) AS i
        """)
        jsonb_insert_time = time.time() - start_time
        
        self.results['insert_performance'] = {
            'record_count': record_count,
            'json_time_seconds': round(json_insert_time, 2),
            'jsonb_time_seconds': round(jsonb_insert_time, 2),
            'json_records_per_second': int(record_count / json_insert_time),
            'jsonb_records_per_second': int(record_count / jsonb_insert_time),
            'performance_ratio': round(json_insert_time / jsonb_insert_time, 2)
        }
        
        print(f"JSON INSERT: {json_insert_time:.2f}s ({self.results['insert_performance']['json_records_per_second']:,} records/sec)")
        print(f"JSONB INSERT: {jsonb_insert_time:.2f}s ({self.results['insert_performance']['jsonb_records_per_second']:,} records/sec)")
        
        # Create indexes after insert for fair comparison
        print("Creating indexes...")
        self.cur.execute("CREATE INDEX idx_json_gin ON json_test USING GIN ((data::jsonb))")
        self.cur.execute("CREATE INDEX idx_jsonb_gin ON jsonb_test USING GIN (data)")
    
    def check_storage_sizes(self):
        """Compare storage sizes"""
        print("Checking storage sizes...")
        
        self.cur.execute("""
            SELECT 
                'json' as type,
                pg_total_relation_size('json_test') as total_size,
                pg_relation_size('json_test') as data_size
            UNION ALL
            SELECT 
                'jsonb' as type,
                pg_total_relation_size('jsonb_test') as total_size,
                pg_relation_size('jsonb_test') as data_size
        """)
        
        sizes = self.cur.fetchall()
        self.results['storage_sizes'] = {}
        
        for row in sizes:
            data_type, total_size, data_size = row
            self.results['storage_sizes'][data_type] = {
                'total_size_bytes': total_size,
                'data_size_bytes': data_size,
                'total_size_mb': round(total_size / (1024*1024), 2),
                'data_size_mb': round(data_size / (1024*1024), 2)
            }
        
        json_size = self.results['storage_sizes']['json']['total_size_bytes']
        jsonb_size = self.results['storage_sizes']['jsonb']['total_size_bytes']
        size_ratio = round(jsonb_size / json_size, 3)
        
        print(f"JSON total size: {self.results['storage_sizes']['json']['total_size_mb']} MB")
        print(f"JSONB total size: {self.results['storage_sizes']['jsonb']['total_size_mb']} MB")
        print(f"JSONB/JSON size ratio: {size_ratio}")
        
        self.results['storage_sizes']['size_ratio'] = size_ratio
    
    def benchmark_queries(self):
        """Benchmark various query types"""
        print("Benchmarking query performance...")
        
        queries = {
            'simple_key_extraction': {
                'description': 'Simple key extraction (data->>user_id)',
                'json_query': "SELECT COUNT(*) FROM json_test WHERE data->>'user_id' = '12345'",
                'jsonb_query': "SELECT COUNT(*) FROM jsonb_test WHERE data->>'user_id' = '12345'"
            },
            'nested_field_access': {
                'description': 'Nested field access',
                'json_query': "SELECT COUNT(*) FROM json_test WHERE data->'profile'->>'city' = 'City_50'",
                'jsonb_query': "SELECT COUNT(*) FROM jsonb_test WHERE data->'profile'->>'city' = 'City_50'"
            },
            'array_operations': {
                'description': 'Array operations',
                'json_query': "SELECT COUNT(*) FROM json_test WHERE (data->'orders'->0)->>'status' = 'completed'",
                'jsonb_query': "SELECT COUNT(*) FROM jsonb_test WHERE (data->'orders'->0)->>'status' = 'completed'"
            },
            'complex_conditions': {
                'description': 'Complex multi-field conditions',
                'json_query': """SELECT COUNT(*) FROM json_test 
                    WHERE (data->>'user_id')::int > 500000 
                      AND (data->'profile'->>'age')::int < 30
                      AND data->'profile'->'preferences'->>'theme' = 'dark'""",
                'jsonb_query': """SELECT COUNT(*) FROM jsonb_test 
                    WHERE (data->>'user_id')::int > 500000 
                      AND (data->'profile'->>'age')::int < 30
                      AND data->'profile'->'preferences'->>'theme' = 'dark'"""
            },
            'path_queries': {
                'description': 'Path-based queries',
                'json_query': "SELECT COUNT(*) FROM json_test WHERE data #>> '{profile,name}' LIKE 'User 1%'",
                'jsonb_query': "SELECT COUNT(*) FROM jsonb_test WHERE data #>> '{profile,name}' LIKE 'User 1%'"
            }
        }
        
        self.results['query_performance'] = {}
        
        for query_name, query_info in queries.items():
            print(f"Testing: {query_info['description']}")
            
            # Warm up
            self.cur.execute("SELECT 1")
            
            # JSON query
            start_time = time.time()
            self.cur.execute(query_info['json_query'])
            json_result = self.cur.fetchone()[0]
            json_time = time.time() - start_time
            
            # JSONB query
            start_time = time.time()
            self.cur.execute(query_info['jsonb_query'])
            jsonb_result = self.cur.fetchone()[0]
            jsonb_time = time.time() - start_time
            
            performance_ratio = round(json_time / jsonb_time, 2) if jsonb_time > 0 else 0
            
            self.results['query_performance'][query_name] = {
                'description': query_info['description'],
                'json_time_ms': round(json_time * 1000, 2),
                'jsonb_time_ms': round(jsonb_time * 1000, 2),
                'json_result_count': json_result,
                'jsonb_result_count': jsonb_result,
                'performance_ratio': performance_ratio
            }
            
            print(f"  JSON: {json_time*1000:.2f}ms | JSONB: {jsonb_time*1000:.2f}ms | Ratio: {performance_ratio}x")
    
    def benchmark_updates(self):
        """Benchmark UPDATE performance"""
        print("Benchmarking UPDATE performance...")
        
        # JSON update
        start_time = time.time()
        self.cur.execute("""
            UPDATE json_test 
            SET data = jsonb_set(data::jsonb, '{profile,preferences,theme}', '"updated"'::jsonb)::json
            WHERE id BETWEEN 1 AND 1000
        """)
        json_update_time = time.time() - start_time
        
        # JSONB update
        start_time = time.time()
        self.cur.execute("""
            UPDATE jsonb_test 
            SET data = jsonb_set(data, '{profile,preferences,theme}', '"updated"'::jsonb)
            WHERE id BETWEEN 1 AND 1000
        """)
        jsonb_update_time = time.time() - start_time
        
        self.results['update_performance'] = {
            'records_updated': 1000,
            'json_time_ms': round(json_update_time * 1000, 2),
            'jsonb_time_ms': round(jsonb_update_time * 1000, 2),
            'performance_ratio': round(json_update_time / jsonb_update_time, 2)
        }
        
        print(f"JSON UPDATE: {json_update_time*1000:.2f}ms")
        print(f"JSONB UPDATE: {jsonb_update_time*1000:.2f}ms")
    
    def generate_report(self, output_file: str = 'benchmark_results.json'):
        """Generate detailed benchmark report"""
        print(f"Generating report: {output_file}")
        
        with open(output_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        # Console summary
        print("\n" + "="*60)
        print("BENCHMARK SUMMARY")
        print("="*60)
        
        insert = self.results['insert_performance']
        print(f"INSERT Performance (1M records):")
        print(f"  JSON:  {insert['json_time_seconds']}s ({insert['json_records_per_second']:,} rec/s)")
        print(f"  JSONB: {insert['jsonb_time_seconds']}s ({insert['jsonb_records_per_second']:,} rec/s)")
        print(f"  Winner: {'JSON' if insert['performance_ratio'] > 1 else 'JSONB'} ({abs(insert['performance_ratio'] - 1)*100:.1f}% faster)")
        
        storage = self.results['storage_sizes']
        print(f"\nStorage Size:")
        print(f"  JSON:  {storage['json']['total_size_mb']} MB")
        print(f"  JSONB: {storage['jsonb']['total_size_mb']} MB")
        print(f"  JSONB is {(1-storage['size_ratio'])*100:.1f}% smaller")
        
        print(f"\nQuery Performance (average improvement):")
        query_ratios = [q['performance_ratio'] for q in self.results['query_performance'].values() if q['performance_ratio'] > 0]
        avg_improvement = sum(query_ratios) / len(query_ratios) if query_ratios else 0
        print(f"  JSONB is {avg_improvement:.1f}x faster on average")
        
        update = self.results['update_performance']
        print(f"\nUpdate Performance:")
        print(f"  JSONB is {update['performance_ratio']:.1f}x faster")
        
        print("\nDetailed results saved to:", output_file)
    
    def cleanup(self):
        """Clean up test data"""
        try:
            if hasattr(self, 'cur') and self.cur:
                print("Cleaning up...")
                self.cur.execute("""
                    DROP TABLE IF EXISTS json_test CASCADE;
                    DROP TABLE IF EXISTS jsonb_test CASCADE;
                    DROP FUNCTION IF EXISTS generate_test_json(INTEGER);
                """)
                print("Cleanup completed")
        except Exception as e:
            print(f"Cleanup failed (non-critical): {e}")
    
    def close(self):
        """Close database connection"""
        try:
            if hasattr(self, 'cur') and self.cur:
                self.cur.close()
            if hasattr(self, 'conn') and self.conn:
                self.conn.close()
        except Exception as e:
            print(f"Error closing connections: {e}")

def load_env_file(env_file='.env'):
    """Load environment variables from .env file"""
    import os
    if env_file == '/dev/null':
        # Skip .env loading when explicitly disabled
        return
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Only set if not already in environment (Docker env has priority)
                    if key.strip() not in os.environ:
                        os.environ[key.strip()] = value.strip()

def main():
    """Main benchmark execution"""
    import os
    import argparse
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='PostgreSQL JSON vs JSONB Benchmark')
    parser.add_argument('--records', type=int, default=None, 
                        help='Number of records to test (default from env or 1000000)')
    parser.add_argument('--env-file', default='.env', 
                        help='Path to .env file (default: .env)')
    parser.add_argument('--output', default=None,
                        help='Output file for results (default from env or benchmark_results.json)')
    args = parser.parse_args()
    
    # Load environment variables (Docker env takes priority)
    load_env_file(args.env_file)
    
    # Database connection parameters from environment
    conn_params = {
        'host': os.getenv('PG_HOST', 'localhost'),
        'database': os.getenv('PG_DATABASE', 'json_benchmark_db'),
        'user': os.getenv('PG_USER', 'benchmark_user'),
        'password': os.getenv('PG_PASSWORD', 'benchmark_pass_2024'),
        'port': int(os.getenv('PG_PORT', 5432))
    }
    
    # Benchmark settings
    record_count = args.records or int(os.getenv('BENCHMARK_RECORDS', 1000000))
    output_file = args.output or os.getenv('BENCHMARK_OUTPUT_FILE', 'benchmark_results.json')
    
    print(f"Connecting to: {conn_params['host']}:{conn_params['port']}/{conn_params['database']}")
    print(f"Testing with: {record_count:,} records")
    print(f"Output file: {output_file}")
    print("")  # Empty line for readability
    
    
    benchmark = PostgreSQLBenchmark(conn_params)
    
    try:
        benchmark.connect()
        benchmark.setup_tables()
        benchmark.benchmark_inserts(record_count)
        benchmark.check_storage_sizes()
        benchmark.benchmark_queries()
        benchmark.benchmark_updates()
        benchmark.generate_report(output_file)
        
        print(f"\n🎉 Benchmark completed successfully!")
        print(f"📊 Results saved to: {output_file}")
        
    except Exception as e:
        print(f"❌ Benchmark failed: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    finally:
        benchmark.cleanup()
        benchmark.close()
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
