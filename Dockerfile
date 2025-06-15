# Dockerfile
FROM postgres:15

# Install Python for benchmark runner
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install psycopg2-binary

# Copy benchmark files
COPY benchmark.sql /docker-entrypoint-initdb.d/
COPY benchmark_runner.py /usr/local/bin/
COPY run_benchmark.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/benchmark_runner.py
RUN chmod +x /usr/local/bin/run_benchmark.sh

# PostgreSQL configuration for better performance
RUN echo "shared_buffers = 256MB" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "work_mem = 64MB" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "maintenance_work_mem = 256MB" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "max_parallel_workers_per_gather = 4" >> /usr/share/postgresql/postgresql.conf.sample

EXPOSE 5432

---

# docker-compose.yml
version: '3.8'

services:
  postgres-benchmark:
    build: .
    environment:
      POSTGRES_DB: benchmark_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: benchmark123
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
    ports:
      - "5432:5432"
    volumes:
      - benchmark_data:/var/lib/postgresql/data
      - ./results:/results
    command: >
      bash -c "
        docker-entrypoint.sh postgres &
        sleep 30 &&
        echo 'Running JSON vs JSONB benchmark...' &&
        python3 /usr/local/bin/benchmark_runner.py &&
        echo 'Benchmark completed. Results saved to /results/' &&
        tail -f /dev/null
      "
    shm_size: 1g

volumes:
  benchmark_data:

---

# run_benchmark.sh
#!/bin/bash

echo "PostgreSQL JSON vs JSONB Benchmark"
echo "=================================="

# Set connection parameters
export PG_HOST=localhost
export PG_DATABASE=benchmark_db
export PG_USER=postgres
export PG_PASSWORD=benchmark123
export PG_PORT=5432

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
until pg_isready -h $PG_HOST -p $PG_PORT -U $PG_USER; do
  sleep 2
done

echo "PostgreSQL is ready. Starting benchmark..."

# Run the Python benchmark
python3 /usr/local/bin/benchmark_runner.py

echo "Benchmark completed!"

---

# Makefile
.PHONY: build run clean results

# Build Docker image
build:
    docker-compose build

# Run benchmark
run:
    docker-compose up --build

# Clean up containers and volumes
clean:
    docker-compose down -v
    docker system prune -f

# Copy results from container
results:
    docker-compose exec postgres-benchmark cp /benchmark_results.json /results/
    @echo "Results copied to ./results/"

# Run quick test (fewer records)
test:
    docker-compose run --rm postgres-benchmark \
        python3 /usr/local/bin/benchmark_runner.py --records 10000

# Access database shell
shell:
    docker-compose exec postgres-benchmark psql -U postgres -d benchmark_db

# View logs
logs:
    docker-compose logs -f postgres-benchmark
