.PHONY: all benchmark benchmark-python benchmark-zig benchmark-rust benchmark-go benchmark-hyperfine benchmark-sizes build test clean help

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
	@echo "  $(GREEN)make benchmark$(NC)           - Run ALL benchmarks (Python, Zig, Rust, Go)"
	@echo "  $(GREEN)make benchmark-hyperfine$(NC) - Official comparison: PyAOT vs Rust (hyperfine)"
	@echo "  $(GREEN)make benchmark-sizes$(NC)     - Multi-size benchmarks (small/medium/large)"
	@echo "  $(GREEN)make benchmark-python$(NC)    - Run Python benchmark only"
	@echo "  $(GREEN)make benchmark-zig$(NC)       - Run Zig/PyAOT benchmark only"
	@echo "  $(GREEN)make benchmark-rust$(NC)      - Run Rust benchmark only"
	@echo "  $(GREEN)make benchmark-go$(NC)        - Run Go benchmark only"
	@echo "  $(GREEN)make build$(NC)               - Build all benchmarks"
	@echo "  $(GREEN)make test$(NC)                - Run regex tests"
	@echo "  $(GREEN)make clean$(NC)               - Clean build artifacts"

# Build all benchmarks
build: build-zig build-rust build-go
	@echo "$(GREEN)✅ All benchmarks built$(NC)"

build-zig:
	@echo "$(YELLOW)🔨 Building Zig benchmark...$(NC)"
	@zig build-exe -O ReleaseFast BENCHMARK.zig
	@zig build-exe -O ReleaseFast BENCHMARK_LARGE.zig

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

# Hyperfine benchmarks (OFFICIAL - Use these for comparisons!)
benchmark-hyperfine: build-zig build-rust
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE)🏆 OFFICIAL BENCHMARK: PyAOT vs Rust$(NC)"
	@echo "$(BLUE)Using hyperfine (10 runs, 3 warmup)$(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@echo ""
	@hyperfine --warmup 3 --runs 10 \
		--export-markdown benchmark_results.md \
		"./BENCHMARK" \
		"./target/release/bench_rust"

benchmark-sizes: build-zig
	@echo "$(BLUE)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)📊 MULTI-SIZE BENCHMARK (Rust regex standard: 1KB/32KB/500KB)$(NC)"
	@echo "$(BLUE)Tests scaling behavior: Linear vs Quadratic vs Exponential$(NC)"
	@echo "$(BLUE)════════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Running SMALL (1KB, 10k iterations)...$(NC)"
	@./BENCHMARK_LARGE small
	@echo ""
	@echo "$(YELLOW)Running MEDIUM (32KB, 1k iterations)...$(NC)"
	@./BENCHMARK_LARGE medium
	@echo ""
	@echo "$(YELLOW)Running LARGE (500KB, 100 iterations)...$(NC)"
	@./BENCHMARK_LARGE large
	@echo ""
	@echo "$(GREEN)✅ Scaling analysis complete!$(NC)"
	@echo ""
	@echo "$(BLUE)Expected behavior:$(NC)"
	@echo "  Linear:       32x data → ~32x time (GOOD)"
	@echo "  Quadratic:    32x data → ~1024x time (BAD)"
	@echo "  Exponential:  32x data → >>1024x time (VERY BAD)"

# Individual benchmarks (use hyperfine for accurate timing)
benchmark-python:
	@echo "$(YELLOW)Running Python benchmark (hyperfine)...$(NC)"
	@hyperfine --warmup 2 --runs 5 "python3 bench_python.py"

benchmark-zig: build-zig
	@echo "$(YELLOW)Running PyAOT benchmark (hyperfine)...$(NC)"
	@hyperfine --warmup 3 --runs 5 "./BENCHMARK"

benchmark-rust: build-rust
	@echo "$(YELLOW)Running Rust benchmark (hyperfine)...$(NC)"
	@hyperfine --warmup 3 --runs 5 "./target/release/bench_rust"

benchmark-go: build-go
	@echo "$(YELLOW)Running Go benchmark (hyperfine)...$(NC)"
	@hyperfine --warmup 3 --runs 5 "./bench_go"

# Run tests
test:
	@echo "$(YELLOW)Running mvzr tests...$(NC)"
	@zig build test

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf zig-cache zig-out target bench_go
	@echo "$(GREEN)✅ Clean complete$(NC)"
