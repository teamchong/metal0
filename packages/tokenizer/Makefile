.PHONY: help benchmark benchmark-train benchmark-encoding benchmark-web test-correctness build build-metal0 build-wasm clean

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RESET := \033[0m

# Paths
METAL0 := ../../zig-out/bin/metal0
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
	@echo "  make test-correctness   - Verify metal0 output matches tiktoken"
	@echo "  make benchmark-encoding - Benchmark encoding (metal0 vs others)"
	@echo "  make benchmark-train    - BPE training benchmark"
	@echo "  make benchmark-web      - Web/WASM benchmark"
	@echo "  make benchmark          - Run ALL benchmarks"
	@echo "  make clean              - Clean build artifacts"
	@echo ""

# Build metal0 tokenizer binaries from Python source
build-metal0:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔨 Compiling Python → Native with metal0$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@mkdir -p $(BIN_DIR)
	@echo "$(YELLOW)Compiling accuracy_test_metal0.py...$(RESET)"
	$(METAL0) accuracy_test_metal0.py -o $(BIN_DIR)/accuracy_test --force
	@echo "$(YELLOW)Compiling bench_full_metal0.py...$(RESET)"
	$(METAL0) bench_full_metal0.py -o $(BIN_DIR)/bench_encoding --force
	@echo "$(GREEN)✅ Build complete$(RESET)"
	@echo ""

# Test correctness: Python → metal0 → binary, compare with tiktoken
test-correctness: build-metal0
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🔍 Encoding Correctness Test (metal0 Python flow)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "Flow: accuracy_test_metal0.py → metal0 → bin/accuracy_test"
	@echo "Compare: metal0 output vs tiktoken (Python)"
	@echo ""
	@python3 test_correctness_metal0.py
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

# Training benchmarks (uses Zig trainer - training is Zig-native)
benchmark-train:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)📊 BPE Training Benchmark$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "Note: Training uses Zig-native implementation (not Python)"
	@./bench_training.sh
	@echo ""

# Web/WASM benchmark
benchmark-web: build-wasm
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🌐 Web/WASM Benchmark$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@chmod +x bench_web.sh
	@./bench_web.sh
	@echo ""

# Build WASM (TODO: Python → metal0 → WASM)
build-wasm:
	@echo "$(YELLOW)🔨 Building WASM tokenizer...$(RESET)"
	@mkdir -p dist
	@zig build-exe src/wasm.zig \
		-target wasm32-freestanding \
		-fno-entry \
		-O ReleaseSmall \
		-rdynamic \
		-femit-bin=dist/metal0_tokenizer.wasm
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
