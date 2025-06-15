-- PostgreSQL initialization script for JSON vs JSONB benchmark
-- This script sets up the database with optimal settings for benchmarking

\echo 'Initializing PostgreSQL for JSON vs JSONB benchmark...'

-- Create extensions that might be useful
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- Display current PostgreSQL version
SELECT version();

-- Display current configuration
\echo 'Current PostgreSQL configuration:'
SELECT name, setting, unit, short_desc 
FROM pg_settings 
WHERE name IN (
    'shared_buffers', 
    'work_mem', 
    'maintenance_work_mem', 
    'max_parallel_workers_per_gather',
    'random_page_cost',
    'effective_cache_size'
)
ORDER BY name;

-- Create a function to show table sizes
CREATE OR REPLACE FUNCTION show_table_sizes()
RETURNS TABLE(
    table_name text,
    size_pretty text,
    size_bytes bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.table_name::text,
        pg_size_pretty(pg_total_relation_size(quote_ident(t.table_name)))::text,
        pg_total_relation_size(quote_ident(t.table_name))
    FROM information_schema.tables t
    WHERE t.table_schema = 'public'
    AND t.table_type = 'BASE TABLE'
    ORDER BY pg_total_relation_size(quote_ident(t.table_name)) DESC;
END;
$$ LANGUAGE plpgsql;

\echo 'Database initialization completed successfully!'
\echo 'Ready for JSON vs JSONB benchmark testing.'
