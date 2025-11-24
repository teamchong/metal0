.PHONY: help build install verify test test-zig test-correctness-full format-zig lint-zig clean run benchmark benchmark-computational

help:
	@echo "PyAOT Commands"
	@echo "============="
	@echo "install                 - Build optimized binary and install to ~/.local/bin (RECOMMENDED)"
	@echo "build                   - Build debug binary for development"
	@echo "build-release           - Build optimized production binary"
	@echo "verify                  - Verify installation is working"
	@echo "test                    - Run pytest regression tests"
	@echo "test-zig                - Run Zig runtime tests"
	@echo "test-correctness-full   - Run comprehensive BPE correctness tests (583+ tests)"
	@echo "format-zig              - Format Zig code"
	@echo "lint-zig                - Check Zig code formatting"
	@echo "clean                   - Remove build artifacts"

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
	@./zig-out/bin/pyaot build examples/bench_computational.py --binary

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
