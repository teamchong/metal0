.PHONY: help benchmark benchmark-train benchmark-encoding benchmark-web benchmark-quick test-correctness build clean

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RESET := \033[0m

# Default target - show help
help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)PyAOT Tokenizer Benchmarks$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "$(GREEN)Available targets:$(RESET)"
	@echo "  make benchmark          - Run all benchmarks (train + encoding)"
	@echo "  make benchmark-quick    - PyAOT vs TokenDagger (hyperfine, ~10s)"
	@echo "  make benchmark-train    - BPE training (3 libraries, ~30s)"
	@echo "  make benchmark-encoding - PyAOT vs tiktoken (hyperfine, ~20s)"
	@echo "  make benchmark-web      - Web/WASM benchmark (hyperfine, ~15s)"
	@echo "  make test-correctness   - Verify PyAOT matches tiktoken output"
	@echo ""
	@echo "$(GREEN)Build targets:$(RESET)"
	@echo "  make build              - Build native tokenizer"
	@echo "  make build-wasm         - Build WASM tokenizer"
	@echo "  make clean              - Clean build artifacts"
	@echo ""

# Run all benchmarks (skip web - too slow)
benchmark: benchmark-train benchmark-encoding

# Training benchmarks (PyAOT vs HuggingFace vs SentencePiece)
benchmark-train:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)📊 BPE Training Benchmark (hyperfine)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@./bench_training.sh
	@echo ""

# Quick benchmark (PyAOT vs TokenDagger only - for fast iteration)
benchmark-quick: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)⚡ Quick Benchmark: PyAOT vs TokenDagger (hyperfine)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@./bench_hyperfine.sh
	@echo ""

# Native encoding benchmarks (PyAOT vs tiktoken - 60K iterations)
benchmark-encoding: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)⚡ Encoding Benchmark: PyAOT vs tiktoken (hyperfine)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@./bench_encoding.sh
	@echo ""

# Test correctness (verify PyAOT matches tiktoken)
test-correctness: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔍 Correctness Test$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@python3 test_correctness.py
	@echo ""

# Web/WASM benchmarks (hyperfine-based, Node.js)
benchmark-web: build-wasm
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🌐 Web/WASM Benchmark (hyperfine)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@chmod +x bench_web.sh
	@./bench_web.sh
	@echo ""

# Build native tokenizer
build:
	@echo "$(YELLOW)🔨 Building native tokenizer...$(RESET)"
	@zig build --release=fast
	@zig build-exe src/bench_native.zig -O ReleaseFast
	@mv bench_native zig-out/bin/
	@echo "$(GREEN)✅ Build complete$(RESET)"
	@echo ""

# Build WASM tokenizer
build-wasm:
	@echo "$(YELLOW)🔨 Building WASM tokenizer...$(RESET)"
	@mkdir -p dist
	@zig build-exe src/wasm.zig -target wasm32-freestanding -fno-entry -O ReleaseFast -rdynamic
	@mv wasm.wasm dist/pyaot_tokenizer.wasm
	@if [ ! -f dist/cl100k_simple.json ]; then \
		echo "$(YELLOW)⚠️  cl100k_simple.json not found in dist/$(RESET)"; \
		echo "$(YELLOW)   Copy vocab file: cp vocab/cl100k_simple.json dist/$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ WASM build complete$(RESET)"
	@echo ""

# Clean build artifacts
clean:
	@echo "$(YELLOW)🧹 Cleaning build artifacts...$(RESET)"
	@rm -rf zig-out/ zig-cache/ dist/*.wasm
	@rm -f bench_trainer bench_cl100k test_tokendagger
	@rm -f *.a *.o
	@echo "$(GREEN)✅ Clean complete$(RESET)"
