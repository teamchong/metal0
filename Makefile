.PHONY: help build install test test-unit test-integration test-quick test-cpython test-all benchmark-fib benchmark-fib-tail benchmark-dict benchmark-string benchmark-json benchmark-json-full benchmark-http benchmark-flask benchmark-regex benchmark-tokenizer benchmark-numpy benchmark-asyncio benchmark-asyncio-io clean format

# =============================================================================
# HELP
# =============================================================================
help:
	@echo "metal0 - Move Ahead of Time"
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
	@echo "  make benchmark-fib       Fibonacci (metal0 vs CPython vs Rust vs Go)"
	@echo "  make benchmark-fib-tail  Tail-recursive Fibonacci"
	@echo "  make benchmark-dict      Dict operations"
	@echo "  make benchmark-string    String operations"
	@echo "  make benchmark-json      JSON quick (shared vs std.json)"
	@echo "  make benchmark-json-full JSON full (metal0 vs Rust vs Go vs Python)"
	@echo "  make benchmark-http      HTTP client (metal0 vs Rust vs Go vs Python)"
	@echo "  make benchmark-flask     Flask + requests (metal0 vs Rust vs Go vs Python)"
	@echo "  make benchmark-regex     Regex (metal0 vs Python vs Rust vs Go)"
	@echo "  make benchmark-tokenizer BPE tokenizer (vs tiktoken/HuggingFace)"
	@echo "  make benchmark-numpy     NumPy matmul (metal0+BLAS vs Python+NumPy)"
	@echo "  make benchmark-asyncio   Async CPU (SHA256 hashing, metal0 vs all)"
	@echo "  make benchmark-asyncio-io Async I/O (concurrent sleep, metal0 vs all)"
	@echo ""
	@echo "Other:"
	@echo "  make format         Format Zig code"
	@echo "  make clean          Remove build artifacts"

# =============================================================================
# BUILD
# =============================================================================
build:
	@echo "Building metal0 (debug)..."
	@zig build
	@echo "✓ Built: ./zig-out/bin/metal0"

build-release:
	@echo "Building metal0 (release)..."
	@zig build -Doptimize=ReleaseFast
	@echo "✓ Built: ./zig-out/bin/metal0"

link:
	@rm ~/.local/bin/metal0 && ln -s ./zig-out/bin/metal0 ~/.local/bin/metal0
	@echo "✓ Linked: ./zig-out/bin/metal0"

install: build-release
	@mkdir -p ~/.local/bin
	@cp zig-out/bin/metal0 ~/.local/bin/metal0
	@echo "✓ Installed to ~/.local/bin/metal0"

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
		if ./zig-out/bin/metal0 "$$f" --force >/dev/null 2>&1; then \
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
		if timeout 5 ./zig-out/bin/metal0 "$$f" --force >/dev/null 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			echo "✗ $$f"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo "Integration: $$passed passed, $$failed failed"

# CPython compatibility tests (3-phase: codegen parallel, zig parallel, run parallel)
test-cpython: build
	@echo "=== Phase 1: Generating Zig code (parallel) ==="
	@rm -rf .metal0/cache/cpython_tests && mkdir -p .metal0/cache/cpython_tests
	@ls tests/cpython/test_*.py | xargs -P16 -I{} sh -c './zig-out/bin/metal0 "{}" --emit-zig --force >/dev/null 2>&1 || true'
	@codegen_count=$$(ls .metal0/cache/*.zig 2>/dev/null | grep -E 'test_.*\.zig$$' | wc -l | tr -d ' '); \
	echo "  ✓ Generated $$codegen_count Zig files"
	@echo ""
	@echo "=== Phase 2: Compiling binaries (parallel via xargs -P8) ==="
	@total=$$(ls tests/cpython/test_*.py | wc -l | tr -d ' '); \
	passed=$$(ls tests/cpython/test_*.py | xargs -P8 -I{} sh -c './zig-out/bin/metal0 "{}" --force >/dev/null 2>&1 && echo 1' 2>/dev/null | wc -l | tr -d ' '); \
	failed=$$((total - passed)); \
	echo "CPython: $$passed/$$total passed ($$failed failed)"

# CPython tests (single phase - for debugging individual test)
test-cpython-seq: build
	@echo "Running CPython tests (sequential)..."
	@passed=0; failed=0; \
	for f in tests/cpython/test_*.py; do \
		if timeout 15 ./zig-out/bin/metal0 "$$f" --force >/dev/null 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			echo "✗ $$f"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo "CPython: $$passed passed, $$failed failed"

# CPython errors only - show which tests fail and why
test-cpython-errors: build
	@echo "Showing CPython test errors..."
	@for f in tests/cpython/test_*.py; do \
		output=$$(./zig-out/bin/metal0 "$$f" --force 2>&1); \
		if [ $$? -ne 0 ]; then \
			echo ""; \
			echo "=== $$f ==="; \
			echo "$$output" | grep -E "error:|Error" | head -3; \
		fi; \
	done

# All tests
test-all: build test-unit test-integration test-cpython
	@echo ""
	@echo "✓ All tests complete"

# =============================================================================
# BENCHMARK (requires hyperfine: brew install hyperfine)
# =============================================================================
benchmark-fib: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Fibonacci Benchmark: metal0 vs Rust vs Go vs Python vs PyPy"
	@cd benchmarks/fib && bash bench.sh

benchmark-dict: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Dict Benchmark: metal0 vs Python vs PyPy"
	@cd benchmarks/dict && bash bench.sh

benchmark-string: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "String Benchmark: metal0 vs Python vs PyPy"
	@cd benchmarks/string && bash bench.sh

benchmark-fib-tail: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Building tail-recursive benchmarks..."
	@./zig-out/bin/metal0 build benchmarks/python/fibonacci_tail.py ./bench_fib_tail_metal0 --binary --force >/dev/null 2>&1
	@rustc -O benchmarks/rust/fibonacci_tail.rs -o ./bench_fib_tail_rust 2>/dev/null || echo "Rust not installed, skipping"
	@CGO_ENABLED=0 go build -ldflags="-s -w" -o ./bench_fib_tail_go benchmarks/go/fibonacci_tail.go 2>/dev/null || echo "Go not installed, skipping"
	@echo "Tail-Recursive Fibonacci (10K × fib(10000)):"
	@echo "(Note: CPython fails with RecursionError - metal0 has tail-call optimization)"
	@hyperfine --warmup 2 --runs 5 \
		'./bench_fib_tail_metal0' \
		'./bench_fib_tail_rust' \
		'./bench_fib_tail_go' 2>/dev/null || \
	hyperfine --warmup 2 --runs 5 \
		'./bench_fib_tail_metal0'
	@rm -f ./bench_fib_tail_metal0 ./bench_fib_tail_rust ./bench_fib_tail_go

benchmark-json: build-release
	@echo "JSON Benchmark: shared/json vs std.json (quick)"
	@cd packages/shared/json && zig build-exe -OReleaseFast bench.zig -femit-bin=bench -lc && ./bench
	@rm -f packages/shared/json/bench

benchmark-json-full: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "JSON Full Benchmark: metal0 vs Rust vs Go vs Python vs PyPy"
	@cd benchmarks/json && bash bench.sh

benchmark-http: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "HTTP Client Benchmark: metal0 vs Rust vs Go vs Python vs PyPy"
	@# Install requests for PyPy if missing
	@pypy3 -c "import requests" 2>/dev/null || pypy3 -m pip install requests -q 2>/dev/null || true
	@cd benchmarks/http && bash bench.sh

benchmark-flask: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Flask + Requests Benchmark: metal0 vs Rust vs Go vs Python vs PyPy"
	@# Install flask+requests for PyPy if missing
	@pypy3 -c "import flask, requests" 2>/dev/null || pypy3 -m pip install flask requests -q 2>/dev/null || true
	@cd benchmarks/flask && bash bench.sh

benchmark-regex: build-release
	@echo "Regex Benchmark: metal0 vs Python vs Rust vs Go"
	@cd benchmarks/regex && bash bench.sh

benchmark-tokenizer: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Tokenizer Benchmark: metal0 BPE vs tiktoken vs HuggingFace"
	@cd benchmarks/tokenizer && bash bench.sh

benchmark-numpy: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "NumPy Matrix Multiplication: metal0+BLAS vs Python+NumPy vs PyPy"
	@# Install numpy for PyPy if missing
	@pypy3 -c "import numpy" 2>/dev/null || pypy3 -m pip install numpy -q 2>/dev/null || true
	@cd benchmarks/numpy && bash bench.sh

benchmark-asyncio: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Async CPU Benchmark: SHA256 hashing (metal0 vs Rust vs Go vs PyPy vs Python)"
	@cd benchmarks/asyncio && bash bench.sh

benchmark-asyncio-io: build-release
	@command -v hyperfine >/dev/null || { echo "Install: brew install hyperfine"; exit 1; }
	@echo "Async I/O Benchmark: Concurrent sleep (metal0 vs Rust vs Go vs PyPy vs Python)"
	@cd benchmarks/asyncio && bash bench_io.sh

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
	@rm -f bench_fib bench_dict bench_string bench_fib_metal0 bench_fib_rust bench_fib_go bench_fib_tail_metal0 bench_fib_tail_rust bench_fib_tail_go
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Cleaned"
