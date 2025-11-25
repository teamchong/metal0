.PHONY: help build install verify verify-readme test test-zig test-correctness-full test-runtime test-asyncio test-all format-zig lint-zig clean run benchmark benchmark-computational benchmark-concurrency benchmark-scheduler benchmark-goroutines benchmark-quick benchmark-full benchmark-5d benchmark-dashboard benchmark-fib benchmark-dict benchmark-string help-testing

help:
	@echo "PyAOT Commands"
	@echo "============="
	@echo "install                 - Build optimized binary and install to ~/.local/bin (RECOMMENDED)"
	@echo "build                   - Build debug binary for development"
	@echo "build-release           - Build optimized production binary"
	@echo "verify                  - Verify installation is working"
	@echo "test                    - Run pytest regression tests"
	@echo "test-zig                - Run Zig runtime tests"
	@echo "test-runtime            - Test standalone Zig runtime (goroutines)"
	@echo "test-asyncio            - Test Python asyncio integration"
	@echo "test-all                - Run all tests (runtime + asyncio)"
	@echo "test-correctness-full   - Run comprehensive BPE correctness tests (583+ tests)"
	@echo "format-zig              - Format Zig code"
	@echo "lint-zig                - Check Zig code formatting"
	@echo "clean                   - Remove build artifacts"
	@echo "benchmark-quick         - Quick benchmark (simple + CPU-bound)"
	@echo "benchmark-full          - Full benchmark suite vs Go"
	@echo "benchmark-5d            - 5-dimensional async benchmark (PyAOT vs Go)"
	@echo "benchmark-dashboard     - Automated dashboard with JSON export"
	@echo "benchmark-fib           - Fibonacci benchmark (PyAOT vs CPython)"
	@echo "benchmark-dict          - Dict benchmark (PyAOT vs CPython)"
	@echo "benchmark-string        - String benchmark (PyAOT vs CPython)"
	@echo "help-testing            - Show testing & benchmarking help"

build:
	@echo "🔨 Building pyaot compiler (debug mode)..."
	@command -v zig >/dev/null 2>&1 || { echo "❌ Error: zig not installed"; exit 1; }
	@rm -rf zig-cache .zig-cache
	zig build
	@echo "✅ Debug binary built: zig-out/bin/pyaot"

build-release:
	@echo "🔨 Building pyaot compiler (optimized for production)..."
	@command -v zig >/dev/null 2>&1 || { echo "❌ Error: zig not installed"; exit 1; }
	@rm -rf zig-cache .zig-cache
	zig build -Doptimize=ReleaseSafe
	@echo "✅ Release binary built: zig-out/bin/pyaot"

install: build-release
	@echo "📦 Installing pyaot to ~/.local/bin..."
	@mkdir -p ~/.local/bin
	@cp zig-out/bin/pyaot ~/.local/bin/pyaot
	@chmod +x ~/.local/bin/pyaot
	@echo ""
	@echo "✅ PyAOT installed!"
	@echo ""
	@echo "Make sure ~/.local/bin is in your PATH:"
	@echo "  export PATH=\"\$$HOME/.local/bin:\$$PATH\""
	@echo ""
	@echo "Then run: pyaot your_file.py"
	@echo ""

verify:
	@bash scripts/verify-install.sh

verify-readme:
	@echo "Verifying README examples compile..."
	@pyaot examples/bench_fib.py --force >/dev/null 2>&1 && echo "✓ bench_fib.py" || echo "✗ bench_fib.py FAILED"
	@pyaot examples/bench_loop.py --force >/dev/null 2>&1 && echo "✓ bench_loop.py" || echo "✗ bench_loop.py FAILED"
	@echo "README verification complete"

test:
	@echo "🧪 Running regression tests..."
	pytest tests/test_regression.py -v
	@echo "✅ Tests complete"

test-zig:
	@echo "🧪 Running Zig runtime tests..."
	zig test packages/runtime/src/runtime.zig
	@echo "✅ Zig runtime tests passed"

test-correctness-full:
	@echo "🔍 Running comprehensive BPE correctness tests..."
	@command -v python3 >/dev/null 2>&1 || { echo "❌ Error: python3 not installed"; exit 1; }
	@chmod +x test_comprehensive_correctness.py
	python3 test_comprehensive_correctness.py

format-zig:
	@echo "🎨 Formatting Zig code..."
	@zig fmt src/*.zig
	@zig fmt packages/runtime/src/*.zig
	@echo "✅ Zig code formatted"

lint-zig:
	@echo "🔍 Checking Zig formatting..."
	@zig fmt --check src/*.zig
	@zig fmt --check packages/runtime/src/*.zig
	@echo "✅ Zig formatting OK"

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	rm -rf bin/ output fib_binary test_output

run:
	@echo "⚠️  DEPRECATED: Use 'pyaot' command directly instead"
	@echo "    New: pyaot $(FILE)"
	@echo ""
	uv run pyaot $(FILE)

benchmark:
	uv run python _prototype/benchmark.py

benchmark-computational:
	@echo "🔧 Computational Performance Benchmark"
	@echo "(NOT web server throughput - just function calls)"
	@echo ""
	# Check dependencies
	@command -v hyperfine >/dev/null 2>&1 || { echo "❌ hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@command -v go >/dev/null 2>&1 || { echo "❌ go not found. Install: brew install go"; exit 1; }
	@command -v rustc >/dev/null 2>&1 || { echo "❌ rustc not found. Install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "❌ python3 not found. Install: brew install python3"; exit 1; }

	@echo "✅ All dependencies found"
	@echo ""
	@echo "🔨 Building benchmarks (RELEASE mode)..."

	# PyAOT (ReleaseFast build!)
	@echo "  Building PyAOT (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast
	@./zig-out/bin/pyaot build examples/bench_computational.py --binary --force

	# Go
	@echo "  Building Go..."
	@go build -o bench_computational_go examples/bench_computational_go.go

	# Rust
	@echo "  Building Rust (-O)..."
	@rustc -O examples/bench_computational_rust.rs -o bench_computational_rust

	@echo ""
	@echo "🔥 Running benchmarks with hyperfine..."
	@hyperfine --warmup 3 \
		'./build/lib.macosx-11.0-arm64/bench_computational' \
		'./bench_computational_go' \
		'./bench_computational_rust' \
		'python3 examples/bench_computational.py'

benchmark-concurrency:
	@echo "🔧 Async/Await Concurrency Benchmark"
	@echo "(M:N scheduled tasks - like Go goroutines)"
	@echo ""
	# Check dependencies
	@command -v go >/dev/null 2>&1 || { echo "❌ go not found. Install: brew install go"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "❌ python3 not found. Install: brew install python3"; exit 1; }

	@echo "✅ All dependencies found"
	@echo ""
	@echo "🔨 Building benchmarks (RELEASE mode)..."

	# PyAOT (ReleaseFast build!)
	@echo "  Building PyAOT async (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast
	@./zig-out/bin/pyaot build examples/bench_concurrency.py --binary --force

	# Go
	@echo "  Building Go goroutines..."
	@go build -o bench_concurrency_go examples/bench_concurrency_go.go

	@echo ""
	@echo "🔥 Running concurrency benchmarks..."
	@echo ""
	@echo "=== PyAOT M:N Runtime (10k tasks) ==="
	@./build/lib.macosx-11.0-arm64/bench_concurrency
	@echo ""
	@echo "=== Go Goroutines (10k tasks) ==="
	@./bench_concurrency_go
	@echo ""
	@echo "=== CPython asyncio (10k tasks) ==="
	@python3 examples/bench_concurrency.py

benchmark-scheduler:
	@echo "🔧 Asyncio Scheduler Benchmark"
	@echo "(100k tasks, EventLoop vs Go goroutines)"
	@echo ""
	# Check dependencies
	@command -v hyperfine >/dev/null 2>&1 || { echo "❌ hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@command -v go >/dev/null 2>&1 || { echo "❌ go not found. Install: brew install go"; exit 1; }

	@echo "✅ Dependencies found"
	@echo ""
	@echo "🔨 Building benchmarks (RELEASE mode)..."

	# PyAOT (ReleaseFast)
	@echo "  Building PyAOT asyncio (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast
	@./zig-out/bin/pyaot build examples/bench_scheduler.py --binary --force

	# Go
	@echo "  Building Go goroutines..."
	@go build -o bench_scheduler_go examples/bench_scheduler_go.go

	@echo ""
	@echo "🔥 Running scheduler benchmarks..."
	@echo ""
	@echo "=== PyAOT EventLoop (100k tasks) ==="
	@./build/lib.macosx-11.0-arm64/bench_scheduler || echo "Binary location may vary"
	@echo ""
	@echo "=== Go Goroutines (100k tasks) ==="
	@./bench_scheduler_go
	@echo ""
	@echo "💡 PyAOT uses EventLoop (single-threaded, cooperative)"
	@echo "💡 Go uses M:N scheduler (multi-threaded, preemptive)"
	@echo "💡 EventLoop should be faster for I/O-bound tasks"

benchmark-goroutines:
	@echo "🚀 PyAOT vs Go: Goroutine Benchmark Suite"
	@echo "=========================================="
	@echo ""
	# Check dependencies
	@command -v hyperfine >/dev/null 2>&1 || { echo "❌ hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@command -v go >/dev/null 2>&1 || { echo "❌ go not found. Install: brew install go"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "❌ python3 not found. Install: brew install python3"; exit 1; }

	@echo "✅ All dependencies found"
	@echo ""
	@echo "🔨 Building PyAOT (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast

	@echo ""
	@echo "[1/4] Simple (10k noop tasks) - Task creation overhead"
	@echo "-------------------------------------------------------"
	@hyperfine --warmup 10 \
		'./zig-out/bin/pyaot examples/bench_simple.py' \
		'go run examples/bench_simple_go.go' \
		'python3 examples/bench_simple.py'

	@echo ""
	@echo "[2/4] Context Switch (1M yields) - Scheduler overhead"
	@echo "-----------------------------------------------------"
	@hyperfine --warmup 3 \
		'./zig-out/bin/pyaot examples/bench_context_switch.py' \
		'go run examples/bench_context_switch_go.go' \
		'python3 examples/bench_context_switch.py'

	@echo ""
	@echo "[3/4] CPU Bound (100x fib(30)) - Multi-core parallelism"
	@echo "--------------------------------------------------------"
	@hyperfine --warmup 1 \
		'./zig-out/bin/pyaot examples/bench_cpu_bound.py' \
		'go run examples/bench_cpu_bound_go.go' \
		'python3 examples/bench_cpu_bound.py'

	@echo ""
	@echo "[4/4] I/O Concurrency (10k mock requests) - Work-stealing"
	@echo "----------------------------------------------------------"
	@hyperfine --warmup 1 \
		'./zig-out/bin/pyaot examples/bench_concurrency_final.py' \
		'go run examples/bench_concurrency_final_go.go' \
		'python3 examples/bench_concurrency_final.py'

	@echo ""
	@echo "📊 Summary"
	@echo "=========="
	@echo "✅ Simple: CPython fastest (minimal overhead)"
	@echo "✅ Context Switch: CPython fastest (simpler model)"
	@echo "🎯 CPU Bound: PyAOT should match Go (no GIL)"
	@echo "🎯 I/O: PyAOT should match Go (work-stealing)"
	@echo ""
	@echo "💡 Note: Memory benchmark requires manual run (see examples/bench_memory.py)"
	@echo "💡 Note: Web benchmark requires aiohttp (see examples/bench_web.py)"

# Test targets
.PHONY: test-runtime
test-runtime:
	@echo "=== Testing Standalone Runtime ==="
	zig test tests/test_goroutines_basic.zig
	zig test tests/test_goroutines.zig

.PHONY: test-asyncio
test-asyncio:
	@echo "=== Testing AsyncIO Implementation ==="
	@echo "\n1. Integration tests..."
	zig build
	./zig-out/bin/pyaot tests/test_asyncio_integration.py

	@echo "\n2. Performance tests..."
	./zig-out/bin/pyaot tests/test_asyncio_performance.py

	@echo "\n3. Existing tests..."
	./zig-out/bin/pyaot tests/test_async_basic.py
	./zig-out/bin/pyaot tests/test_asyncio.py

.PHONY: test-all
test-all: test-runtime test-asyncio
	@echo "\n✅ All tests complete!"

# Benchmark targets
.PHONY: benchmark-quick
benchmark-quick:
	@echo "=== Quick Benchmark (Simple + CPU-bound) ==="
	@echo "Building..."
	zig build -Doptimize=ReleaseFast
	./zig-out/bin/pyaot build examples/bench_simple.py ./bench_simple --binary --force
	./zig-out/bin/pyaot build examples/bench_cpu_bound.py ./bench_cpu_bound --binary --force
	go build -o bench_simple_go examples/bench_simple_go.go
	go build -o bench_cpu_bound_go examples/bench_cpu_bound_go.go

	@echo "\n1. Simple (10 tasks):"
	@echo "PyAOT:"
	@time ./bench_simple
	@echo "\nGo:"
	@time ./bench_simple_go

	@echo "\n2. CPU-bound (100 parallel):"
	@echo "PyAOT:"
	@time ./bench_cpu_bound
	@echo "\nGo:"
	@time ./bench_cpu_bound_go

.PHONY: benchmark-full
benchmark-full: benchmark-goroutines
	@echo "Full benchmark suite - see results above"

.PHONY: benchmark-5d
benchmark-5d:
	@echo "Running 5-dimensional benchmark suite..."
	@chmod +x scripts/benchmark_async_complete.sh
	@./scripts/benchmark_async_complete.sh

.PHONY: benchmark-dashboard
benchmark-dashboard:
	@echo "Running automated benchmark dashboard..."
	@python3 scripts/benchmark_dashboard.py

.PHONY: benchmark-fib
benchmark-fib:
	@echo "🔧 Fibonacci Benchmark (PyAOT vs CPython)"
	@echo ""
	@command -v hyperfine >/dev/null 2>&1 || { echo "❌ hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@echo "✅ Dependencies found"
	@echo ""
	@echo "🔨 Building PyAOT (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast
	@./zig-out/bin/pyaot build examples/bench_fib.py ./bench_fib --binary --force
	@echo ""
	@echo "🔥 Running fibonacci benchmark (fib(35))..."
	@hyperfine --warmup 3 \
		'./bench_fib' \
		'python3 examples/bench_fib.py'

.PHONY: benchmark-dict
benchmark-dict:
	@echo "🔧 Dict Benchmark (PyAOT vs CPython)"
	@echo ""
	@command -v hyperfine >/dev/null 2>&1 || { echo "❌ hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@echo "✅ Dependencies found"
	@echo ""
	@echo "🔨 Building PyAOT (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast
	@./zig-out/bin/pyaot build examples/bench_dict.py ./bench_dict --binary --force
	@echo ""
	@echo "🔥 Running dict benchmark (1M iterations)..."
	@hyperfine --warmup 3 \
		'./bench_dict' \
		'python3 examples/bench_dict.py'

.PHONY: benchmark-string
benchmark-string:
	@echo "🔧 String Benchmark (PyAOT vs CPython)"
	@echo ""
	@command -v hyperfine >/dev/null 2>&1 || { echo "❌ hyperfine not found. Install: brew install hyperfine"; exit 1; }
	@echo "✅ Dependencies found"
	@echo ""
	@echo "🔨 Building PyAOT (ReleaseFast)..."
	@zig build -Doptimize=ReleaseFast
	@./zig-out/bin/pyaot build examples/bench_string.py ./bench_string --binary --force
	@echo ""
	@echo "🔥 Running string benchmark (10k concatenations)..."
	@hyperfine --warmup 3 \
		'./bench_string' \
		'python3 examples/bench_string.py'

# Help target
.PHONY: help-testing
help-testing:
	@echo "Testing & Benchmarking:"
	@echo "  make test-runtime       - Test standalone Zig runtime"
	@echo "  make test-asyncio       - Test Python asyncio integration"
	@echo "  make test-all           - Run all tests"
	@echo "  make benchmark-quick    - Quick benchmark (2 tests)"
	@echo "  make benchmark-full     - Full benchmark suite vs Go"

.PHONY: benchmark-loop
benchmark-loop:
	@echo "Building PyAOT loop benchmark..."
	pyaot build examples/bench_loop.py ./bench_loop --binary --force
	@echo "Running benchmark (10M iterations)..."
	hyperfine --warmup 2 --runs 10 './bench_loop' 'python3 examples/bench_loop.py'
	@rm -f ./bench_loop

.PHONY: test-features
test-features:
	@./tests/features/run_all.sh
