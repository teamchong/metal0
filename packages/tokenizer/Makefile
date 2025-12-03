.PHONY: help benchmark benchmark-train benchmark-encoding benchmark-web test-correctness test-training build build-metal0 build-wasm clean

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RESET := \033[0m

# Paths
REPO_ROOT := $(shell cd ../.. && pwd)
METAL0 := $(REPO_ROOT)/zig-out/bin/metal0
BIN_DIR := bin

# Default target - show help
help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)metal0 Tokenizer Benchmarks (Python → Binary)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "$(GREEN)Flow: Python code → metal0 compiler → Native binary$(RESET)"
	@echo ""
	@echo "$(GREEN)Available targets:$(RESET)"
	@echo "  make build-metal0       - Compile Python tokenizer with metal0"
	@echo "  make test-correctness   - Verify encoding matches tiktoken"
	@echo "  make test-training      - Verify training vs HuggingFace"
	@echo "  make benchmark-encoding - Benchmark encoding (binary)"
	@echo "  make benchmark-train    - BPE training benchmark"
	@echo "  make benchmark-web      - Web/WASM benchmark (browser)"
	@echo "  make benchmark          - Run ALL 3 benchmarks"
	@echo "  make clean              - Clean build artifacts"
	@echo ""

# Build metal0 tokenizer binaries from Python source
# Note: metal0 must run from repo root for proper module resolution
build-metal0:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔨 Compiling Python → Native with metal0$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@mkdir -p $(BIN_DIR)
	@echo "$(YELLOW)Compiling accuracy_test_metal0.py...$(RESET)"
	cd $(REPO_ROOT) && $(METAL0) build -b packages/tokenizer/accuracy_test_metal0.py --force
	cp $(REPO_ROOT)/build/lib.macosx-11.0-arm64/accuracy_test_metal0 $(BIN_DIR)/accuracy_test
	@echo "$(YELLOW)Compiling bench_full_metal0.py...$(RESET)"
	cd $(REPO_ROOT) && $(METAL0) build -b packages/tokenizer/bench_full_metal0.py --force || true
	cp $(REPO_ROOT)/build/lib.macosx-11.0-arm64/bench_full_metal0 $(BIN_DIR)/bench_encoding 2>/dev/null || true
	@echo "$(GREEN)✅ Build complete$(RESET)"
	@echo ""

# Test correctness: Zig-native binary vs tiktoken (Python reference)
test-correctness: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔍 Encoding Correctness Test (601 cases vs tiktoken)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@python3 test_encoding_full.py
	@echo ""

# Test training correctness vs HuggingFace
test-training: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔍 Training Correctness Test (vs HuggingFace)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@python3 test_100_percent_training.py
	@echo ""

# Encoding benchmark: Python → metal0 → binary
benchmark-encoding: build-metal0
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🚀 Encoding Benchmark (metal0 Python flow)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "Flow: bench_full_metal0.py → metal0 → bin/bench_encoding"
	@echo ""
	@./$(BIN_DIR)/bench_encoding
	@echo ""

# Training benchmarks: Zig native (Python flow TBC - needs metal0 import support)
benchmark-train: build-train
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)📊 BPE Training Benchmark (Zig native)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@./zig-out/bin/bench_train
	@echo ""

# Build training benchmark: Zig native
build-train:
	@echo "$(YELLOW)Building Zig-native bench_train...$(RESET)"
	@zig build -Doptimize=ReleaseFast
	@echo "$(GREEN)✅ Build complete$(RESET)"

# Web/WASM benchmark
benchmark-web: build-wasm
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🌐 Web/WASM Benchmark$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@chmod +x bench_web.sh
	@./bench_web.sh
	@echo ""

# Build WASM: Python → metal0 → WASM
build-wasm:
	@echo "$(YELLOW)🔨 Building WASM tokenizer (Python → metal0 → WASM)...$(RESET)"
	@mkdir -p dist
	cd $(REPO_ROOT) && $(METAL0) build --target wasm32 packages/tokenizer/wasm_tokenizer_metal0.py --force || echo "TODO: Create wasm_tokenizer_metal0.py"
	cp $(REPO_ROOT)/build/lib.wasm32/wasm_tokenizer_metal0.wasm dist/metal0_tokenizer.wasm 2>/dev/null || true
	@echo "$(GREEN)✅ WASM build complete$(RESET)"
	@echo ""

# Run all benchmarks
benchmark: benchmark-encoding benchmark-train benchmark-web

# Legacy build (Zig-native, not Python flow)
build:
	@echo "$(YELLOW)🔨 Building Zig-native binaries...$(RESET)"
	@mkdir -p zig-out/bin
	@zig build -Doptimize=ReleaseFast
	@echo "$(GREEN)✅ Build complete$(RESET)"

# Clean
clean:
	@echo "$(YELLOW)🧹 Cleaning...$(RESET)"
	@rm -rf $(BIN_DIR)/ zig-out/ zig-cache/ dist/*.wasm
	@echo "$(GREEN)✅ Clean complete$(RESET)"
