.PHONY: all benchmark benchmark-python benchmark-zig benchmark-rust benchmark-go build test clean help

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

help:
	@echo "$(BLUE)PyAOT Regex Benchmarks$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)make benchmark$(NC)        - Run ALL benchmarks (Python, Zig, Rust, Go)"
	@echo "  $(GREEN)make benchmark-python$(NC) - Run Python benchmark only"
	@echo "  $(GREEN)make benchmark-zig$(NC)    - Run Zig/PyAOT benchmark only"
	@echo "  $(GREEN)make benchmark-rust$(NC)   - Run Rust benchmark only"
	@echo "  $(GREEN)make benchmark-go$(NC)     - Run Go benchmark only"
	@echo "  $(GREEN)make build$(NC)            - Build all benchmarks"
	@echo "  $(GREEN)make test$(NC)             - Run mvzr tests"
	@echo "  $(GREEN)make clean$(NC)            - Clean build artifacts"

# Build all benchmarks
build: build-zig build-rust build-go
	@echo "$(GREEN)✅ All benchmarks built$(NC)"

build-zig:
	@echo "$(YELLOW)🔨 Building Zig benchmark...$(NC)"
	@zig build -Doptimize=ReleaseFast

build-rust:
	@echo "$(YELLOW)🔨 Building Rust benchmark...$(NC)"
	@cargo build --release --quiet

build-go:
	@echo "$(YELLOW)🔨 Building Go benchmark...$(NC)"
	@go build -o bench_go bench_go.go

# Run all benchmarks
benchmark: build
	@echo ""
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE)Running ALL Regex Benchmarks$(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@echo ""
	@$(MAKE) benchmark-python
	@echo ""
	@$(MAKE) benchmark-zig
	@echo ""
	@$(MAKE) benchmark-rust
	@echo ""
	@$(MAKE) benchmark-go
	@echo ""
	@echo "$(GREEN)✅ All benchmarks complete!$(NC)"

# Individual benchmarks
benchmark-python:
	@echo "$(YELLOW)Running Python benchmark...$(NC)"
	@python3 bench_python.py

benchmark-zig:
	@echo "$(YELLOW)Running PyAOT Regex Benchmark...$(NC)"
	@zig run -O ReleaseFast BENCHMARK.zig

benchmark-rust: build-rust
	@echo "$(YELLOW)Running Rust benchmark...$(NC)"
	@./target/release/bench_rust

benchmark-go: build-go
	@echo "$(YELLOW)Running Go benchmark...$(NC)"
	@./bench_go

# Run tests
test:
	@echo "$(YELLOW)Running mvzr tests...$(NC)"
	@zig build test

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf zig-cache zig-out target bench_go
	@echo "$(GREEN)✅ Clean complete$(NC)"
