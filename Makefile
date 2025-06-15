# PostgreSQL JSON vs JSONB Benchmark Makefile
# Supports both Docker Compose V1 and V2

# Detect Docker Compose command
DOCKER_COMPOSE := $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo "docker-compose"; fi)

.PHONY: help build run quick clean logs shell db-only results setup

# Default target
help: ## Show this help message
	@echo "PostgreSQL JSON vs JSONB Benchmark"
	@echo "=================================="
	@echo "Using: $(DOCKER_COMPOSE)"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Create .env file from template if it doesn't exist
	@if [ ! -f .env ]; then \
	cp .env.example .env; \
	echo "✅ Created .env file from template"; \
	echo "📝 Edit .env file to customize settings"; \
	else \
	echo "ℹ️  .env file already exists"; \
	fi
	@mkdir -p results

build: setup ## Build Docker containers
	@echo "🔨 Building containers..."
	@$(DOCKER_COMPOSE) build

run: build ## Run full benchmark (1M records)
	@echo "🚀 Starting full benchmark..."
	@$(DOCKER_COMPOSE) --profile benchmark up --abort-on-container-exit --exit-code-from benchmark_runner

quick: build ## Run quick test (10K records)
	@echo "⚡ Starting quick test..."
	@BENCHMARK_RECORDS=10000 $(DOCKER_COMPOSE) --profile benchmark up --abort-on-container-exit --exit-code-from benchmark_runner

db-only: setup ## Start only PostgreSQL database
	@echo "🗄️  Starting PostgreSQL only..."
	@$(DOCKER_COMPOSE) up postgres

clean: ## Clean up containers, volumes, and images
	@echo "🧹 Cleaning up..."
	@$(DOCKER_COMPOSE) down -v --remove-orphans
	@docker volume rm postgresql-json-jsonb-benchmark_postgres_data 2>/dev/null || true
	@docker system prune -f
	@echo "✅ Cleanup completed"

logs: ## Show logs from all services
	@$(DOCKER_COMPOSE) logs -f

shell: ## Access database shell
	@echo "🐚 Connecting to database..."
	@$(DOCKER_COMPOSE) exec postgres psql -U ${PG_USER:-benchmark_user} -d ${PG_DATABASE:-json_benchmark_db}

shell-local: ## Access database from host (localhost:5433)
	@echo "🐚 Connecting to database from host..."
	@psql -h localhost -p 5433 -U ${PG_USER:-benchmark_user} -d ${PG_DATABASE:-json_benchmark_db}

results: ## Copy results from container (if running)
	@echo "📊 Copying results..."
	@if [ -f "./results/benchmark_results.json" ]; then \
	echo "📁 Results found in ./results/benchmark_results.json"; \
	echo "📈 Summary:"; \
	python3 -c "import json; data=json.load(open('./results/benchmark_results.json')); insert=data.get('insert_performance',{}); print(f'INSERT: JSON {insert.get(\"json_time_seconds\",0)}s vs JSONB {insert.get(\"jsonb_time_seconds\",0)}s')" 2>/dev/null || echo "Use 'cat ./results/benchmark_results.json' to view results"; \
	else \
	echo "❌ No results found. Run 'make run' first."; \
	fi

# Advanced targets
rebuild: clean build ## Clean rebuild everything

test-env: ## Test environment setup
	@echo "🧪 Testing environment..."
	@docker version
	@echo "Docker Compose: $(DOCKER_COMPOSE)"
	@$(DOCKER_COMPOSE) version
	@if [ -f .env ]; then echo "✅ .env file exists"; else echo "❌ .env file missing - run 'make setup'"; fi

# Development targets
dev-db: ## Start database in development mode with exposed port
	@echo "🔧 Starting development database..."
	@$(DOCKER_COMPOSE) up postgres -d
	@echo "📡 Database available on localhost:5432"
	@echo "🔐 Connection: postgresql://benchmark_user:benchmark_pass_2024@localhost:5432/json_benchmark_db"

stop: ## Stop all services
	@$(DOCKER_COMPOSE) stop

restart: stop run ## Restart benchmark

# CI/CD targets  
ci-test: ## Run benchmark for CI/CD (quick test)
	@echo "🤖 Running CI test..."
	@BENCHMARK_RECORDS=1000 $(DOCKER_COMPOSE) --profile benchmark up --abort-on-container-exit --exit-code-from benchmark_runner
	@$(DOCKER_COMPOSE) down -v

# Custom record count
run-custom: ## Run with custom record count (use RECORDS=number)
	@echo "🎯 Running with $(RECORDS) records..."
	@BENCHMARK_RECORDS=$(RECORDS) $(DOCKER_COMPOSE) --profile benchmark up --abort-on-container-exit --exit-code-from benchmark_runner
