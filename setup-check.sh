#!/bin/bash

# Setup and validation script for PostgreSQL JSON vs JSONB benchmark

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "PostgreSQL JSON vs JSONB Benchmark Setup Check"
echo "=============================================="

# Check required files
required_files=(
    "docker-compose.yml"
    "Dockerfile.benchmark"
    "benchmark_runner.py"
    "init-db.sql"
    ".env.example"
    "run.sh"
    "Makefile"
)

print_info "Checking required files..."
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        print_success "$file exists"
    else
        print_error "$file is missing"
        exit 1
    fi
done

# Check .env file
if [ -f ".env" ]; then
    print_success ".env file exists"
    
    # Validate .env content
    required_vars=(
        "PG_DATABASE"
        "PG_USER"
        "PG_PASSWORD"
        "BENCHMARK_RECORDS"
    )
    
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" .env; then
            print_success ".env contains $var"
        else
            print_warning ".env missing $var (will use default)"
        fi
    done
else
    print_warning ".env file not found"
    print_info "Creating .env from template..."
    if cp .env.example .env; then
        print_success "Created .env file"
    else
        print_error "Failed to create .env file"
        exit 1
    fi
fi

# Check Docker
print_info "Checking Docker setup..."
if ! docker --version >/dev/null 2>&1; then
    print_error "Docker is not installed or not in PATH"
    exit 1
else
    print_success "Docker is available: $(docker --version)"
fi

if ! docker info >/dev/null 2>&1; then
    print_error "Docker daemon is not running"
    exit 1
else
    print_success "Docker daemon is running"
fi

# Check Docker Compose
if docker compose version >/dev/null 2>&1; then
    print_success "Docker Compose V2 is available: $(docker compose version --short)"
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    print_warning "Using legacy docker-compose: $(docker-compose --version)"
    print_info "Consider upgrading to Docker Compose V2"
    DOCKER_COMPOSE="docker-compose"
else
    print_error "Docker Compose is not available"
    exit 1
fi

# Validate SQL files
print_info "Validating SQL files..."
if head -1 init-db.sql | grep -q "^--"; then
    print_success "init-db.sql has correct SQL format"
else
    print_error "init-db.sql may have incorrect format (should start with SQL comment)"
    exit 1
fi

if head -1 benchmark.sql | grep -q "^--"; then
    print_success "benchmark.sql has correct SQL format"
else
    print_warning "benchmark.sql may have incorrect format"
fi

# Check Python requirements
print_info "Checking Python setup..."
if command -v python3 >/dev/null 2>&1; then
    print_success "Python 3 is available: $(python3 --version)"
    
    # Check if we can import required modules (for local testing)
    if python3 -c "import psycopg2" 2>/dev/null; then
        print_success "psycopg2 is available for local testing"
    else
        print_info "psycopg2 not available locally (will be installed in Docker)"
    fi
else
    print_warning "Python 3 not found (only needed for local testing)"
fi

# Create results directory
if [ ! -d "results" ]; then
    mkdir -p results
    print_success "Created results directory"
else
    print_success "Results directory exists"
fi

# Test Docker Compose file
print_info "Validating docker-compose.yml..."
if $DOCKER_COMPOSE config >/dev/null 2>&1; then
    print_success "docker-compose.yml is valid"
else
    print_error "docker-compose.yml has syntax errors"
    print_info "Run '$DOCKER_COMPOSE config' to see details"
    exit 1
fi

# Make scripts executable
print_info "Setting script permissions..."
chmod +x run.sh
chmod +x setup-check.sh
print_success "Scripts are now executable"

# Final recommendations
echo ""
print_success "Setup check completed successfully!"
echo ""
print_info "Next steps:"
echo "  1. Review and edit .env file if needed"
echo "  2. Run: ./run.sh --quick (for 10K records test)"
echo "  3. Run: ./run.sh (for full 1M records benchmark)"
echo "  4. Or use: make quick / make run"
echo ""
print_info "For help: ./run.sh --help or make help"
