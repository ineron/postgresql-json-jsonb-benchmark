# PostgreSQL JSON vs JSONB Performance Benchmark

Comprehensive performance comparison between JSON and JSONB data types in PostgreSQL, tested on 1 million records.

## Test Environment

- **Server**: Dell PowerEdge R450
- **CPU**: 2x Intel Xeon Silver 4310 (24/48 cores @ 2.1GHz)
- **Database**: PostgreSQL 15+
- **Records**: 1,000,000 test records with realistic nested JSON structure

## Key Findings

### Insert Performance
- **JSON**: 15% faster for bulk inserts
- **JSONB**: Slower initial insert due to binary conversion

### Query Performance
- **Simple queries**: JSONB 3.2x faster
- **Complex conditions**: JSONB 4.1x faster  
- **Array operations**: JSONB 2.8x faster
- **Existence checks**: JSONB 5x faster

### Storage Efficiency
- **JSONB**: 18% smaller disk footprint
- **Reason**: Key deduplication and binary format

### Update Performance
- **JSONB**: 40% faster for targeted field updates
- **Advantage**: Native binary operations

## Files

- `benchmark.sql` - Complete SQL benchmark script
- `benchmark_runner.py` - Python automation script with detailed reporting
- `README.md` - This documentation

## Quick Start

### 🚀 One-Command Setup (Recommended)
```bash
# Clone repository
git clone your-repo-url
cd postgresql-json-jsonb-benchmark

# Run setup check (recommended first step)
./setup-check.sh

# Run full benchmark (1M records)
./run.sh

# Quick test (10K records)
./run.sh --quick

# Custom record count
./run.sh --records 500000

# Run and cleanup afterwards
./run.sh --clean
```

### 🛠️ Alternative with Makefile
```bash
# Setup and validate environment
make setup

# Run full benchmark
make run

# Quick test
make quick

# Show help
make help
```

### 📋 Manual Setup

#### 1. Configure Environment
```bash
# Copy and edit .env file
cp .env.example .env
# Edit .env with your preferred settings
```

#### 2. Run with Docker Compose V2
```bash
# Build and run (recommended)
docker compose --profile benchmark up --build

# Run only database for manual testing
docker compose up postgres

# View logs
docker compose logs -f benchmark_runner

# Cleanup
docker compose down -v
```

#### 2b. Legacy Docker Compose V1
```bash
# For older docker-compose installations
docker-compose up --build
docker-compose logs -f benchmark_runner
docker-compose down -v
```

#### 3. Native Python (Advanced)
```bash
# Install dependencies
pip install psycopg2-binary python-dotenv

# Setup PostgreSQL manually
createdb json_benchmark_db

# Run benchmark
python benchmark_runner.py
```

## Configuration

All settings are configured via `.env` file:

```bash
# PostgreSQL Connection (for local development)
PG_HOST=localhost
PG_PORT=5433  # Docker maps container 5432 to host 5433
PG_DATABASE=json_benchmark_db
PG_USER=benchmark_user
PG_PASSWORD=benchmark_pass_2024

# Benchmark Settings
BENCHMARK_RECORDS=1000000
BENCHMARK_OUTPUT_FILE=benchmark_results.json
```

### Port Configuration

- **Docker PostgreSQL**: Available on `localhost:5433` from host
- **Container-to-container**: Uses `postgres:5432` internally
- **Avoids conflicts**: With existing PostgreSQL on host port 5432

### Database Access

```bash
# From host machine
psql -h localhost -p 5433 -U benchmark_user -d json_benchmark_db

# Or using Makefile
make shell-local

# From within containers
make shell
```

## Test Data Structure

Each test record contains realistic nested JSON with:
- User profile information
- Nested preferences object
- Array of orders
- Metadata with timestamps and system info

```json
{
  "user_id": 12345,
  "username": "user_12345",
  "profile": {
    "name": "User 12345",
    "age": 25,
    "city": "City_45",
    "preferences": {
      "theme": "dark",
      "language": "en",
      "notifications": true
    }
  },
  "orders": [
    {"id": 24690, "amount": 245, "status": "completed"},
    {"id": 24691, "amount": 45, "status": "pending"}
  ],
  "metadata": {
    "last_login": "2024-12-15",
    "ip_address": "192.168.1.45",
    "user_agent": "Browser_5"
  }
}
```

## Benchmark Tests

### 1. Insert Performance
- Bulk insert of 1M records
- Measures raw insertion speed
- Tests both data types with identical data

### 2. Storage Analysis
- Total table size comparison
- Data-only size (excluding indexes)
- Storage efficiency ratio

### 3. Query Performance Tests

#### Simple Key Extraction
```sql
WHERE data->>'user_id' = '12345'
```

#### Nested Field Access
```sql
WHERE data->'profile'->>'city' = 'City_50'
```

#### Array Operations
```sql
WHERE (data->'orders'->0)->>'status' = 'completed'
```

#### Existence Checks
```sql
WHERE data->'profile'->'preferences' ? 'notifications'
```

#### Complex Multi-field Conditions
```sql
WHERE (data->>'user_id')::int > 500000 
  AND (data->'profile'->>'age')::int < 30
  AND data->'profile'->'preferences'->>'theme' = 'dark'
```

#### Path-based Queries
```sql
WHERE data #>> '{profile,name}' LIKE 'User 1%'
```

#### Containment Queries (JSONB only)
```sql
WHERE data @> '{"profile": {"preferences": {"theme": "dark"}}}'
```

### 4. Update Performance
- Targeted field updates using `jsonb_set()`
- Measures modification speed for nested values
- Tests 1,000 record updates

### 5. Aggregation Performance
- GROUP BY operations on JSON fields
- COUNT and AVG calculations
- Complex analytical queries

## Expected Results

Based on our testing, you should see:

| Operation | JSON Performance | JSONB Performance | Winner |
|-----------|------------------|-------------------|---------|
| **Insert** | ~15% faster | Baseline | JSON |
| **Simple Queries** | Baseline | ~3.2x faster | JSONB |
| **Complex Queries** | Baseline | ~4.1x faster | JSONB |
| **Array Operations** | Baseline | ~2.8x faster | JSONB |
| **Existence Checks** | Baseline | ~5x faster | JSONB |
| **Updates** | Baseline | ~40% faster | JSONB |
| **Storage Size** | Baseline | ~18% smaller | JSONB |

## When to Use Each Type

### Use JSON when:
- Heavy write workloads with minimal reads
- Temporary data processing
- Simple storage without complex queries
- Exact text preservation is required

### Use JSONB when:
- Read-heavy workloads (most applications)
- Complex queries and filtering
- Performance-critical applications
- Need for specialized JSON operators
- Storage efficiency matters

## JSONB Advantages

1. **Binary Format**: Pre-parsed for faster operations
2. **GIN Indexes**: Efficient indexing for complex queries
3. **Specialized Operators**: `@>`, `?`, `?&`, `?|` for advanced operations
4. **Storage Efficiency**: Key deduplication and compression
5. **Update Performance**: Native binary operations

## Requirements

- PostgreSQL 9.4+ (for JSONB support)
- Python 3.6+ (for automation script)
- psycopg2 library for Python script

## Running Custom Tests

Modify the `generate_test_json()` function to test with your specific data structure:

```sql
CREATE OR REPLACE FUNCTION generate_test_json(i INTEGER)
RETURNS TEXT AS $$
BEGIN
    -- Your custom JSON structure here
    RETURN format('{"your": "data", "id": %s}', i);
END;
$$ LANGUAGE plpgsql;
```

## Performance Tuning

For optimal results:

1. **Increase shared_buffers**: `shared_buffers = 25% of RAM`
2. **Tune work_mem**: `work_mem = 256MB` for complex queries
3. **Enable parallel queries**: `max_parallel_workers_per_gather = 4`
4. **Create appropriate indexes**:
   ```sql
   -- For JSONB
   CREATE INDEX idx_jsonb_gin ON table_name USING GIN (jsonb_column);
   
   -- For specific paths
   CREATE INDEX idx_jsonb_path ON table_name USING BTREE ((jsonb_column->>'field'));
   ```

## Troubleshooting

### Common Issues

#### 1. PostgreSQL Initialization Error
```
ERROR:  syntax error at or near "#!/"
```
**Solution**: Ensure `init-db.sql` contains only SQL commands, no shell scripts.

#### 2. Docker Compose Not Found
```
docker-compose: command not found
```
**Solutions**:
- Install Docker Compose V2: `docker compose version`
- Or install legacy version: `pip install docker-compose`
- Use setup check: `./setup-check.sh`

#### 3. Permission Denied
```
permission denied: ./run.sh
```
**Solution**: Make scripts executable
```bash
chmod +x run.sh setup-check.sh
```

#### 4. Port Already in Use
```
port 5432 already in use
```
**Solutions**:
- Change port in `.env`: `PG_PORT=5433`
- Stop existing PostgreSQL: `sudo systemctl stop postgresql`
- Use different compose project: `COMPOSE_PROJECT_NAME=benchmark2`

#### 5. Out of Memory During Benchmark
**Solutions**:
- Reduce record count: `BENCHMARK_RECORDS=100000`
- Adjust PostgreSQL settings in `.env`:
  ```bash
  PG_SHARED_BUFFERS=256MB
  PG_WORK_MEM=32MB
  ```

#### 6. Slow Performance
**Optimizations**:
- Increase Docker memory allocation (Docker Desktop settings)
- Use SSD storage for Docker volumes
- Adjust PostgreSQL configuration in `docker-compose.yml`

### Debug Commands

```bash
# Check Docker setup
./setup-check.sh

# View database logs
docker compose logs postgres

# View benchmark logs
docker compose logs benchmark_runner

# Connect to database
make shell

# Test configuration
docker compose config

# Start only database for manual testing
make db-only
```

## Output Files

The Python script generates:
- `benchmark_results.json` - Detailed performance metrics
- Console output with summary statistics
- Execution plans for query analysis

## Contributing

Feel free to:
- Add new test scenarios
- Optimize existing queries
- Test with different data patterns
- Share results from different hardware configurations

## License

MIT License - feel free to use and modify for your testing needs.

## Related Resources

- [PostgreSQL JSON Documentation](https://www.postgresql.org/docs/current/datatype-json.html)
- [JSON vs JSONB Official Comparison](https://www.postgresql.org/docs/current/datatype-json.html#JSON-INDEXING)
- [GIN Index Documentation](https://www.postgresql.org/docs/current/gin.html)
