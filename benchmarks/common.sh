#!/bin/bash
# Common benchmark infrastructure
# Source this file in all bench.sh scripts

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_hyperfine() {
    if ! command -v hyperfine &>/dev/null; then
        echo -e "${RED}Error: hyperfine not found${NC}"
        echo "Install: brew install hyperfine"
        exit 1
    fi
}

# Check PyPy availability
check_pypy() {
    if command -v pypy3 &>/dev/null; then
        PYPY_AVAILABLE=true
        echo -e "  ${GREEN}✓${NC} PyPy3"
    else
        PYPY_AVAILABLE=false
        echo -e "  ${YELLOW}⚠${NC} PyPy3 not found (skipping)"
    fi
}

# Check Rust availability
check_rust() {
    if command -v rustc &>/dev/null; then
        RUST_AVAILABLE=true
        echo -e "  ${GREEN}✓${NC} Rust"
    else
        RUST_AVAILABLE=false
        echo -e "  ${YELLOW}⚠${NC} Rust not found (skipping)"
    fi
}

# Check Go availability
check_go() {
    if command -v go &>/dev/null; then
        GO_AVAILABLE=true
        echo -e "  ${GREEN}✓${NC} Go"
    else
        GO_AVAILABLE=false
        echo -e "  ${YELLOW}⚠${NC} Go not found (skipping)"
    fi
}

# Build metal0 compiler (ReleaseFast)
build_metal0_compiler() {
    echo "Building metal0 compiler..."
    cd "$PROJECT_ROOT" && zig build -Doptimize=ReleaseFast >/dev/null 2>&1
    cd "$SCRIPT_DIR"
    echo -e "  ${GREEN}✓${NC} metal0 compiler"
}

# Compile Python file with metal0
# Usage: compile_metal0 <source.py> <output_binary>
compile_metal0() {
    local src="$1"
    local out="$2"
    # Must run from PROJECT_ROOT for metal0 to find dependencies
    cd "$PROJECT_ROOT"
    ./zig-out/bin/metal0 build "$SCRIPT_DIR/$src" "$SCRIPT_DIR/$out" --binary --force >/dev/null 2>&1
    local result=$?
    cd "$SCRIPT_DIR"
    if [ $result -eq 0 ] && [ -f "$SCRIPT_DIR/$out" ]; then
        echo -e "  ${GREEN}✓${NC} metal0: $src"
        return 0
    else
        echo -e "  ${RED}✗${NC} metal0: $src failed"
        return 1
    fi
}

# Compile Rust file
# Usage: compile_rust <source.rs> <output_binary>
compile_rust() {
    local src="$1"
    local out="$2"
    if [ "$RUST_AVAILABLE" = true ]; then
        rustc -O "$SCRIPT_DIR/$src" -o "$SCRIPT_DIR/$out" 2>/dev/null
        if [ -f "$SCRIPT_DIR/$out" ]; then
            echo -e "  ${GREEN}✓${NC} Rust: $src"
            return 0
        fi
    fi
    return 1
}

# Compile Go file (with optimizations)
# Usage: compile_go <source.go> <output_binary>
compile_go() {
    local src="$1"
    local out="$2"
    if [ "$GO_AVAILABLE" = true ]; then
        CGO_ENABLED=0 go build -ldflags="-s -w" -o "$SCRIPT_DIR/$out" "$SCRIPT_DIR/$src" 2>/dev/null
        if [ -f "$SCRIPT_DIR/$out" ]; then
            echo -e "  ${GREEN}✓${NC} Go: $src"
            return 0
        fi
    fi
    return 1
}

# Helper functions to add benchmark commands
# These use eval to work around bash version differences with nameref

# Add benchmark command for metal0 binary
# Usage: add_metal0 <cmd_array_name> <binary_name>
add_metal0() {
    local arr_name=$1
    local bin="$2"
    if [ -f "$SCRIPT_DIR/$bin" ]; then
        eval "$arr_name+=(--command-name \"metal0\" \"./$bin\")"
    fi
}

# Add benchmark command for Rust binary
add_rust() {
    local arr_name=$1
    local bin="$2"
    if [ "$RUST_AVAILABLE" = true ] && [ -f "$SCRIPT_DIR/$bin" ]; then
        eval "$arr_name+=(--command-name \"Rust\" \"./$bin\")"
    fi
}

# Add benchmark command for Go binary
add_go() {
    local arr_name=$1
    local bin="$2"
    if [ "$GO_AVAILABLE" = true ] && [ -f "$SCRIPT_DIR/$bin" ]; then
        eval "$arr_name+=(--command-name \"Go\" \"./$bin\")"
    fi
}

# Add benchmark command for Python
# Usage: add_python <cmd_array_name> <script> [deps...]
# Example: add_python BENCH_CMD script.py requests flask
add_python() {
    local arr_name=$1
    local script="$2"
    shift 2
    local deps="$*"

    if [ -n "$deps" ]; then
        # Install deps first, then run
        metal0 install $deps 2>/dev/null || true
        eval "$arr_name+=(--command-name \"Python\" \"python3 $script\")"
    else
        # Simple case - no deps
        eval "$arr_name+=(--command-name \"Python\" \"python3 $script\")"
    fi
}

# Add benchmark command for PyPy
add_pypy() {
    local arr_name=$1
    local script="$2"
    if [ "$PYPY_AVAILABLE" = true ]; then
        eval "$arr_name+=(--command-name \"PyPy\" \"pypy3 $script\")"
    fi
}

# Print section header
print_header() {
    echo ""
    echo "=== $1 ==="
}

# Initialize benchmark (call at start of each bench.sh)
init_benchmark() {
    local name="$1"
    echo "$name"
    echo "$(printf '=%.0s' $(seq 1 ${#name}))"
    echo ""
    echo "Checking dependencies..."
    check_hyperfine
    check_pypy
}

# Initialize with compiled languages
init_benchmark_compiled() {
    local name="$1"
    echo "$name"
    echo "$(printf '=%.0s' $(seq 1 ${#name}))"
    echo ""
    echo "Checking dependencies..."
    check_hyperfine
    check_pypy
    check_rust
    check_go
}
