.PHONY: help benchmark benchmark-train benchmark-encoding benchmark-web benchmark-quick test-correctness build build-wasm clean

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RESET := \033[0m

# Build flags
ZIG := zig
OPTIMIZE := -O ReleaseFast
BIN_DIR := zig-out/bin

# Default target - show help
help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)PyAOT Tokenizer Benchmarks$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "$(GREEN)Available targets:$(RESET)"
	@echo "  make benchmark          - Run ALL benchmarks (train + encoding + web)"
	@echo "  make benchmark-quick    - PyAOT vs TokenDagger (hyperfine, ~10s)"
	@echo "  make benchmark-train    - BPE training (3 libraries, ~30s)"
	@echo "  make benchmark-encoding - Encoding (5 libraries w/ TokenDagger, ~20s)"
	@echo "  make benchmark-web      - Web/WASM benchmark (4 libraries, ~15s)"
	@echo "  make test-correctness   - Verify PyAOT matches tiktoken (583+ tests)"
	@echo ""
	@echo "$(GREEN)Build targets:$(RESET)"
	@echo "  make build              - Build all native binaries"
	@echo "  make build-wasm         - Build WASM tokenizer"
	@echo "  make clean              - Clean build artifacts"
	@echo ""

# Run all benchmarks (train + encoding + web)
benchmark: benchmark-train benchmark-encoding benchmark-web

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

# Native encoding benchmarks (5 libraries: rs-bpe, tiktoken, TokenDagger, HuggingFace, PyAOT)
benchmark-encoding:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🚀 Encoding Benchmark: 5 libraries$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@./BENCHMARK.sh
	@echo ""

# Test correctness (comprehensive: 583 benchmark texts + edge cases)
test-correctness: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔍 Correctness Test (Comprehensive)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@python3 test_comprehensive.py
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

# Build all native binaries (no build.zig - direct zig commands)
build:
	@echo "$(YELLOW)🔨 Building native binaries...$(RESET)"
	@mkdir -p $(BIN_DIR)
	@$(ZIG) build-exe src/main.zig $(OPTIMIZE) -femit-bin=$(BIN_DIR)/tokenizer_bench
	@$(ZIG) build-exe src/bench_native.zig $(OPTIMIZE) -femit-bin=$(BIN_DIR)/bench_native
	@$(ZIG) build-exe src/bench_train.zig $(OPTIMIZE) -femit-bin=$(BIN_DIR)/bench_train
	@$(ZIG) build-exe src/test_correctness.zig $(OPTIMIZE) -femit-bin=$(BIN_DIR)/test_correctness
	@echo "$(GREEN)✅ Build complete:$(RESET)"
	@echo "   - tokenizer_bench"
	@echo "   - bench_native"
	@echo "   - bench_train"
	@echo "   - test_correctness"
	@echo ""

# Build WASM tokenizer (direct zig command)
build-wasm:
	@echo "$(YELLOW)🔨 Building WASM tokenizer...$(RESET)"
	@mkdir -p dist
	@$(ZIG) build-exe src/wasm.zig \
		-target wasm32-freestanding \
		-fno-entry \
		-O ReleaseSmall \
		-rdynamic \
		-femit-bin=dist/pyaot_tokenizer.wasm
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
	@rm -f *.a *.o *.wasm
	@echo "$(GREEN)✅ Clean complete$(RESET)"
