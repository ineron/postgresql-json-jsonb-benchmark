-- PostgreSQL JSON vs JSONB Performance Benchmark
-- Test Environment: Dell PowerEdge R450, 2x Intel Xeon Silver 4310 24/48 cores @ 2.1GHz
-- Database: PostgreSQL 15+

-- ===========================================
-- 1. SETUP TABLES
-- ===========================================

-- Create tables for testing
DROP TABLE IF EXISTS json_test CASCADE;
DROP TABLE IF EXISTS jsonb_test CASCADE;

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

-- Create indexes for fair comparison
CREATE INDEX idx_json_gin ON json_test USING GIN ((data::jsonb));
CREATE INDEX idx_jsonb_gin ON jsonb_test USING GIN (data);

-- ===========================================
-- 2. GENERATE TEST DATA
-- ===========================================

-- Function to generate random test data
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
    i,                                    -- user_id
    i,                                    -- username
    i,                                    -- profile.name
    (i % 50) + 18,                       -- profile.age (18-67)
    (i % 100) + 1,                       -- profile.city
    CASE (i % 3) WHEN 0 THEN 'dark' WHEN 1 THEN 'light' ELSE 'auto' END, -- theme
    CASE (i % 2) WHEN 0 THEN 'true' ELSE 'false' END, -- notifications
    i * 2,                               -- orders[0].id
    (i % 1000) + 10,                     -- orders[0].amount
    (i * 2) + 1,                         -- orders[1].id
    (i % 500) + 5,                       -- orders[1].amount
    (i % 30) + 1,                        -- last_login day
    (i % 254) + 1,                       -- ip_address last octet
    (i % 10) + 1                         -- user_agent
    );
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- 3. INSERT PERFORMANCE TEST
-- ===========================================

\echo 'Starting INSERT performance test...'

-- JSON INSERT test
\timing on
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    
    INSERT INTO json_test (data)
    SELECT generate_test_json(i)::JSON
    FROM generate_series(1, 1000000) AS i;
    
    end_time := clock_timestamp();
    RAISE NOTICE 'JSON INSERT completed in: %', end_time - start_time;
END $$;

-- JSONB INSERT test
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    
    INSERT INTO jsonb_test (data)
    SELECT generate_test_json(i)::JSONB
    FROM generate_series(1, 1000000) AS i;
    
    end_time := clock_timestamp();
    RAISE NOTICE 'JSONB INSERT completed in: %', end_time - start_time;
END $$;
\timing off

-- ===========================================
-- 4. STORAGE SIZE COMPARISON
-- ===========================================

\echo 'Storage size comparison:'
SELECT 
    'JSON' as type,
    pg_size_pretty(pg_total_relation_size('json_test')) as table_size,
    pg_size_pretty(pg_relation_size('json_test')) as data_size
UNION ALL
SELECT 
    'JSONB' as type,
    pg_size_pretty(pg_total_relation_size('jsonb_test')) as table_size,
    pg_size_pretty(pg_relation_size('jsonb_test')) as data_size;

-- ===========================================
-- 5. QUERY PERFORMANCE TESTS
-- ===========================================

\echo 'Starting query performance tests...'

-- Test 1: Simple key extraction
\echo 'Test 1: Simple key extraction (data->>''user_id'')'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM json_test WHERE data->>'user_id' = '12345';

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test WHERE data->>'user_id' = '12345';

-- Test 2: Nested field access
\echo 'Test 2: Nested field access'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM json_test WHERE data->'profile'->>'city' = 'City_50';

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test WHERE data->'profile'->>'city' = 'City_50';

-- Test 3: Array operations
\echo 'Test 3: Array operations'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM json_test WHERE (data->'orders'->0)->>'status' = 'completed';

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test WHERE (data->'orders'->0)->>'status' = 'completed';

-- Test 4: Existence checks (JSONB only)
\echo 'Test 4: Existence checks'
-- JSON equivalent (slower)
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM json_test WHERE data::text LIKE '%"notifications"%';

-- JSONB optimized
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test WHERE data->'profile'->'preferences' ? 'notifications';

-- Test 5: Complex conditions
\echo 'Test 5: Complex conditions'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM json_test 
WHERE data->>'user_id'::int > 500000 
  AND data->'profile'->>'age'::int < 30
  AND data->'profile'->'preferences'->>'theme' = 'dark';

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test 
WHERE (data->>'user_id')::int > 500000 
  AND (data->'profile'->>'age')::int < 30
  AND data->'profile'->'preferences'->>'theme' = 'dark';

-- Test 6: Path-based queries
\echo 'Test 6: Path-based queries'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM json_test WHERE data #>> '{profile,name}' LIKE 'User 1%';

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test WHERE data #>> '{profile,name}' LIKE 'User 1%';

-- Test 7: Containment queries (JSONB only)
\echo 'Test 7: Containment queries (JSONB advantage)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM jsonb_test 
WHERE data @> '{"profile": {"preferences": {"theme": "dark"}}}';

-- Test 8: Aggregations
\echo 'Test 8: Aggregations'
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    data->'profile'->>'city' as city,
    COUNT(*),
    AVG((data->>'user_id')::int)
FROM json_test 
GROUP BY data->'profile'->>'city' 
LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    data->'profile'->>'city' as city,
    COUNT(*),
    AVG((data->>'user_id')::int)
FROM jsonb_test 
GROUP BY data->'profile'->>'city' 
LIMIT 10;

-- ===========================================
-- 6. UPDATE PERFORMANCE TESTS
-- ===========================================

\echo 'Testing UPDATE performance...'

-- JSON update test
\timing on
UPDATE json_test 
SET data = jsonb_set(data::jsonb, '{profile,preferences,theme}', '"updated"'::jsonb)::json
WHERE id BETWEEN 1 AND 1000;
\timing off

-- JSONB update test
\timing on
UPDATE jsonb_test 
SET data = jsonb_set(data, '{profile,preferences,theme}', '"updated"'::jsonb)
WHERE id BETWEEN 1 AND 1000;
\timing off

-- ===========================================
-- 7. CLEANUP FUNCTION
-- ===========================================

CREATE OR REPLACE FUNCTION cleanup_benchmark()
RETURNS void AS $$
BEGIN
    DROP TABLE IF EXISTS json_test CASCADE;
    DROP TABLE IF EXISTS jsonb_test CASCADE;
    DROP FUNCTION IF EXISTS generate_test_json(INTEGER);
    RAISE NOTICE 'Benchmark cleanup completed';
END;
$$ LANGUAGE plpgsql;

-- Uncomment to clean up after testing
-- SELECT cleanup_benchmark();