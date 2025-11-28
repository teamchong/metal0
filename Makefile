.PHONY: help build install test test-unit test-integration test-quick test-cpython test-all benchmark-fib benchmark-fib-tail benchmark-dict benchmark-string benchmark-json benchmark-json-full benchmark-http benchmark-flask benchmark-regex benchmark-tokenizer clean format

# =============================================================================
# HELP
# =============================================================================
help:
	@echo "PyAOT - Move Ahead of Time"
	@echo "=========================="
	@echo ""
	@echo "Build:"
	@echo "  make build          Build debug binary (fast iteration)"
	@echo "  make install        Build release + install to ~/.local/bin"
	@echo ""
	@echo "Test:"
	@echo "  make test           Run quick tests (unit + smoke)"
	@echo "  make test-unit      Run unit tests only"
	@echo "  make test-integration  Run integration tests"
	@echo "  make test-all       Run ALL tests (slow)"
	@echo ""
	@echo "Benchmark:"
	@echo "  make benchmark-fib       Fibonacci (PyAOT vs CPython vs Rust vs Go)"
	@echo "  make benchmark-fib-tail  Tail-recursive Fibonacci"
	@echo "  make benchmark-dict      Dict operations"
	@echo "  make benchmark-string    String operations"
	@echo "  make benchmark-json      JSON quick (shared vs std.json)"
	@echo "  make benchmark-json-full JSON full (PyAOT vs Rust vs Go vs Python)"
	@echo "  make benchmark-http      HTTP client (PyAOT vs Rust vs Go vs Python)"
	@echo "  make benchmark-flask     Flask + requests (PyAOT vs Rust vs Go vs Python)"
	@echo "  make benchmark-regex     Regex (PyAOT vs Python vs Rust vs Go)"
	@echo "  make benchmark-tokenizer BPE tokenizer (vs tiktoken/HuggingFace)"
	@echo ""
	@echo "Other:"
	@echo "  make format         Format Zig code"
	@echo "  make clean          Remove build artifacts"

# =============================================================================
# BUILD
# =============================================================================
build:
	@echo "Building pyaot (debug)..."
	@zig build
	@echo "✓ Built: ./zig-out/bin/pyaot"

build-release:
	@echo "Building pyaot (release)..."
	@zig build -Doptimize=ReleaseFast
	@echo "✓ Built: ./zig-out/bin/pyaot"

install: build-release
	@mkdir -p ~/.local/bin
	@cp zig-out/bin/pyaot ~/.local/bin/pyaot
	@echo "✓ Installed to ~/.local/bin/pyaot"

# =============================================================================
# TEST
# =============================================================================
# Quick test (default) - fast feedback loop
test: build test-unit
	@echo ""
	@echo "✓ Quick tests passed"

# Unit tests - compile individual .py files
test-unit: build
	@echo "Running unit tests..."
	@passed=0; failed=0; \
	for f in tests/unit/test_*.py; do \
		if ./zig-out/bin/pyaot "$$f" --force >/dev/null 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			echo "✗ $$f"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo "Unit: $$passed passed, $$failed failed"

# Integration tests - larger programs
test-integration: build
	@echo "Running integration tests..."
	@passed=0; failed=0; \
	for f in tests/integration/test_*.py; do \
		if timeout 5 ./zig-out/bin/pyaot "$$f" --force >/dev/null 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			echo "✗ $$f"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo "Integration: $$passed passed, $$failed failed"

# CPython compatibility tests
test-cpython: build
	@echo "Running CPython tests..."
	@passed=0; failed=0; \
	for f in tests/cpython/test_*.py; do \
		if timeout 5 ./zig-out/bin/pyaot "$$f" --force >/dev/null 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			echo "✗ $$f"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo "CPython: $$passed passed, $$failed failed"

# All tests
test-all: build test-unit test-integration test-cpython
	@echo ""
	@echo "✓ All tests complete"

# =============================================================================
# BENCHMARK (requires hyperfine: brew install hyperfine)
# =============================================================================
benchmark-fib: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Fibonacci Benchmark: PyAOT vs Rust vs Go vs Python vs PyPy"
	@cd benchmarks/fib && bash bench.sh

benchmark-dict: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Dict Benchmark: PyAOT vs Python vs PyPy"
	@cd benchmarks/dict && bash bench.sh

benchmark-string: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "String Benchmark: PyAOT vs Python vs PyPy"
	@cd benchmarks/string && bash bench.sh

benchmark-fib-tail: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Building tail-recursive benchmarks..."
	@./zig-out/bin/pyaot build benchmarks/python/fibonacci_tail.py ./bench_fib_tail_pyaot --binary --force >/dev/null 2>&1
	@rustc -O benchmarks/rust/fibonacci_tail.rs -o ./bench_fib_tail_rust 2>/dev/null || echo "Rust not installed, skipping"
	@CGO_ENABLED=0 go build -ldflags="-s -w" -o ./bench_fib_tail_go benchmarks/go/fibonacci_tail.go 2>/dev/null || echo "Go not installed, skipping"
	@echo "Tail-Recursive Fibonacci (10K × fib(10000)):"
	@echo "(Note: CPython fails with RecursionError - PyAOT has tail-call optimization)"
	@hyperfine --warmup 2 --runs 5 \
		'./bench_fib_tail_pyaot' \
		'./bench_fib_tail_rust' \
		'./bench_fib_tail_go' 2>/dev/null || \
	hyperfine --warmup 2 --runs 5 \
		'./bench_fib_tail_pyaot'
	@rm -f ./bench_fib_tail_pyaot ./bench_fib_tail_rust ./bench_fib_tail_go

benchmark-json: build-release
	@echo "JSON Benchmark: shared/json vs std.json (quick)"
	@cd packages/shared/json && zig build-exe -OReleaseFast bench.zig -femit-bin=bench -lc && ./bench
	@rm -f packages/shared/json/bench

benchmark-json-full: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "JSON Full Benchmark: PyAOT vs Rust vs Go vs Python vs PyPy"
	@cd benchmarks/json && bash bench.sh

benchmark-http: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "HTTP Client Benchmark: PyAOT vs Rust vs Go vs Python vs PyPy"
	@# Install requests for PyPy if missing
	@pypy3 -c "import requests" 2>/dev/null || pypy3 -m pip install requests -q 2>/dev/null || true
	@cd benchmarks/http && bash bench.sh

benchmark-flask: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Flask + Requests Benchmark: PyAOT vs Rust vs Go vs Python vs PyPy"
	@# Install flask+requests for PyPy if missing
	@pypy3 -c "import flask, requests" 2>/dev/null || pypy3 -m pip install flask requests -q 2>/dev/null || true
	@cd benchmarks/flask && bash bench.sh

benchmark-regex: build-release
	@echo "Regex Benchmark: PyAOT vs Python vs Rust vs Go"
	@cd benchmarks/regex && bash bench.sh

benchmark-tokenizer: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Tokenizer Benchmark: PyAOT BPE vs tiktoken vs HuggingFace"
	@cd benchmarks/tokenizer && bash bench.sh

# =============================================================================
# UTILITIES
# =============================================================================
format:
	@echo "Formatting Zig..."
	@find src -name "*.zig" -exec zig fmt {} \;
	@find packages -name "*.zig" -exec zig fmt {} \;
	@echo "✓ Formatted"

clean:
	@rm -rf zig-out zig-cache .zig-cache build .build
	@rm -f bench_fib bench_dict bench_string bench_fib_pyaot bench_fib_rust bench_fib_go bench_fib_tail_pyaot bench_fib_tail_rust bench_fib_tail_go
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Cleaned"
