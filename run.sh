#!/bin/bash

# PostgreSQL JSON vs JSONB Benchmark Runner
# Usage: ./run.sh [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RECORDS=1000000
CLEAN=false
QUICK=false

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to show usage
show_usage() {
    echo "PostgreSQL JSON vs JSONB Benchmark"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --records NUM     Number of records to test (default: 1000000)"
    echo "  -q, --quick          Quick test with 10,000 records"
    echo "  -c, --clean          Clean up containers and volumes after test"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Run full benchmark with 1M records"
    echo "  $0 --quick           # Quick test with 10K records"
    echo "  $0 -r 500000         # Test with 500K records"
    echo "  $0 --clean           # Run test and cleanup afterwards"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--records)
            RECORDS="$2"
            shift 2
            ;;
        -q|--quick)
            RECORDS=10000
            QUICK=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if docker compose is available (V2)
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
    print_warning "Using legacy docker-compose. Consider upgrading to Docker Compose V2"
else
    print_error "Neither 'docker compose' nor 'docker-compose' is available."
    print_error "Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

print_info "Using: $DOCKER_COMPOSE"

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    print_warning ".env file not found. Creating default .env file..."
    cat > .env << EOF
# PostgreSQL Connection Settings
PG_HOST=localhost
PG_PORT=5432
PG_DATABASE=json_benchmark_db
PG_USER=benchmark_user
PG_PASSWORD=benchmark_pass_2024

# Benchmark Settings
BENCHMARK_RECORDS=$RECORDS
BENCHMARK_OUTPUT_FILE=benchmark_results.json

# Docker Settings
POSTGRES_VERSION=15
EOF
    print_success "Created .env file with default settings"
else
    # Update BENCHMARK_RECORDS in existing .env file
    if grep -q "BENCHMARK_RECORDS=" .env; then
        sed -i "s/BENCHMARK_RECORDS=.*/BENCHMARK_RECORDS=$RECORDS/" .env
    else
        echo "BENCHMARK_RECORDS=$RECORDS" >> .env
    fi
fi

# Create results directory
mkdir -p results

print_info "Starting PostgreSQL JSON vs JSONB Benchmark"
echo "=============================================="
print_info "Records to test: $(printf "%'d" $RECORDS)"
if [ "$QUICK" = true ]; then
    print_info "Mode: Quick test"
else
    print_info "Mode: Full benchmark"
fi
print_info "Results will be saved to: ./results/"
echo ""

# Build and run the benchmark
print_info "Building Docker containers..."
if ! $DOCKER_COMPOSE build --quiet; then
    print_error "Failed to build Docker containers"
    exit 1
fi

print_success "Docker containers built successfully"
print_info "Starting benchmark... This may take several minutes."
echo ""

# Run the benchmark with profile
if $DOCKER_COMPOSE --profile benchmark up --build --abort-on-container-exit --exit-code-from benchmark_runner; then
    print_success "Benchmark completed successfully!"
    
    # Show results summary if available
    if [ -f "results/benchmark_results.json" ]; then
        print_info "Results summary:"
        if command -v python3 >/dev/null 2>&1; then
            python3 -c "
import json
import sys
try:
    with open('results/benchmark_results.json', 'r') as f:
        data = json.load(f)
    
    insert = data.get('insert_performance', {})
    if insert:
        print(f\"📊 INSERT (1M records):\"
        print(f\"   JSON:  {insert.get('json_time_seconds', 0)}s\"
        print(f\"   JSONB: {insert.get('jsonb_time_seconds', 0)}s\"
    
    storage = data.get('storage_sizes', {})
    if storage:
        json_size = storage.get('json', {}).get('total_size_mb', 0)
        jsonb_size = storage.get('jsonb', {}).get('total_size_mb', 0)
        print(f\"💾 Storage sizes:\"
        print(f\"   JSON:  {json_size} MB\"
        print(f\"   JSONB: {jsonb_size} MB\"
        
    print(f\"📁 Full results: ./results/benchmark_results.json\"
except Exception as e:
    print(f\"Could not parse results: {e}\"
" 2>/dev/null || print_info "Full results available in ./results/benchmark_results.json"
        fi
    fi
else
    print_error "Benchmark failed!"
    exit 1
fi

# Cleanup if requested
if [ "$CLEAN" = true ]; then
    print_info "Cleaning up Docker containers and volumes..."
    $DOCKER_COMPOSE down -v
    print_success "Cleanup completed"
fi

echo ""
print_success "All done! 🎉"
