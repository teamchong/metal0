#!/bin/bash
# JSON Parse and Stringify Benchmark (separated)
# Compares Zig vs Rust vs Python vs Go on JSON operations
set -e
cd "$(dirname "$0")"

echo "📊 JSON Parse & Stringify Benchmark"
echo "═══════════════════════════════════"
echo "Operations: Parse JSON × 10000 | Stringify × 10000"
echo "Languages: Zig, Rust, Python, Go"
echo ""

# Create sample JSON data if not exists
if [ ! -f sample.json ]; then
    cat > sample.json <<'EOF'
{
  "name": "PyAOT Tokenizer",
  "version": "1.0.0",
  "description": "Fast BPE tokenizer in Zig",
  "performance": {
    "encoding": "2.489s",
    "vs_rs_bpe": "1.55x faster",
    "correctness": true
  },
  "features": ["BPE encoding", "Training", "WASM support"],
  "benchmarks": [
    {"library": "PyAOT", "time": 2.489},
    {"library": "rs-bpe", "time": 3.866},
    {"library": "tiktoken", "time": 9.311}
  ],
  "metadata": {
    "author": "PyAOT Team",
    "license": "MIT",
    "repo": "https://github.com/teamchong/pyaot"
  }
}
EOF
    echo "✅ Created sample.json"
fi

# Build Zig PARSE benchmark
echo "🔨 Building Zig parse benchmark..."
cat > /tmp/bench_json_parse_zig.zig <<'ZIGEOF'
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile("sample.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_data);

    for (0..10000) |_| {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_data,
            .{}
        );
        defer parsed.deinit();
    }
}
ZIGEOF

zig build-exe /tmp/bench_json_parse_zig.zig -O ReleaseFast -femit-bin=/tmp/bench_json_parse_zig 2>&1 | head -20
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Zig parse build failed"
    exit 1
fi
echo "✅ Zig parse benchmark built"

# Build Rust PARSE benchmark
echo "🔨 Building Rust parse benchmark..."
mkdir -p /tmp/bench_json_parse_rust_project/src
cd /tmp/bench_json_parse_rust_project

cat > Cargo.toml <<'CARGOEOF'
[package]
name = "bench_json_parse_rust"
version = "0.1.0"
edition = "2021"

[dependencies]
serde_json = "1.0"
CARGOEOF

cat > src/main.rs <<'RUSTEOF'
use std::fs;

fn main() {
    let json_data = fs::read_to_string("sample.json").expect("Failed to read");

    for _ in 0..10000 {
        let _parsed: serde_json::Value = serde_json::from_str(&json_data).expect("Failed to parse");
    }
}
RUSTEOF

if command -v cargo &> /dev/null; then
    cargo build --release 2>&1 | tail -5
    cp target/release/bench_json_parse_rust /tmp/bench_json_parse_rust 2>/dev/null || true
    cd - > /dev/null
    if [ -f /tmp/bench_json_parse_rust ]; then
        echo "✅ Rust parse benchmark built"
        RUST_AVAILABLE=true
    else
        echo "⚠️  Rust build failed"
        RUST_AVAILABLE=false
    fi
else
    echo "⚠️  Rust not available"
    RUST_AVAILABLE=false
    cd - > /dev/null
fi

# Build Rust STRINGIFY benchmark
echo "🔨 Building Rust stringify benchmark..."
mkdir -p /tmp/bench_json_stringify_rust_project/src
cd /tmp/bench_json_stringify_rust_project

cat > Cargo.toml <<'CARGOEOF'
[package]
name = "bench_json_stringify_rust"
version = "0.1.0"
edition = "2021"

[dependencies]
serde_json = "1.0"
CARGOEOF

cat > src/main.rs <<'RUSTEOF'
use std::fs;

fn main() {
    let json_data = fs::read_to_string("sample.json").expect("Failed to read");
    let parsed: serde_json::Value = serde_json::from_str(&json_data).expect("Failed to parse");

    for _ in 0..10000 {
        let _stringified = serde_json::to_string(&parsed).expect("Failed to stringify");
    }
}
RUSTEOF

if command -v cargo &> /dev/null && [ "$RUST_AVAILABLE" = true ]; then
    cargo build --release 2>&1 | tail -5
    cp target/release/bench_json_stringify_rust /tmp/bench_json_stringify_rust 2>/dev/null || true
    cd - > /dev/null
    if [ ! -f /tmp/bench_json_stringify_rust ]; then
        echo "⚠️  Rust stringify build failed"
        RUST_AVAILABLE=false
    else
        echo "✅ Rust stringify benchmark built"
    fi
else
    cd - > /dev/null
fi

# Build Go PARSE benchmark
echo "🔨 Building Go parse benchmark..."
cat > /tmp/bench_json_parse_go.go <<'GOEOF'
package main

import (
    "encoding/json"
    "os"
)

func main() {
    data, _ := os.ReadFile("sample.json")

    for i := 0; i < 10000; i++ {
        var parsed interface{}
        json.Unmarshal(data, &parsed)
    }
}
GOEOF

if command -v go &> /dev/null; then
    go build -o /tmp/bench_json_parse_go /tmp/bench_json_parse_go.go 2>&1 | tail -5
    if [ -f /tmp/bench_json_parse_go ]; then
        echo "✅ Go parse benchmark built"
        GO_AVAILABLE=true
    else
        echo "⚠️  Go build failed"
        GO_AVAILABLE=false
    fi
else
    echo "⚠️  Go not available"
    GO_AVAILABLE=false
fi

# Build Go STRINGIFY benchmark
echo "🔨 Building Go stringify benchmark..."
cat > /tmp/bench_json_stringify_go.go <<'GOEOF'
package main

import (
    "encoding/json"
    "os"
)

func main() {
    data, _ := os.ReadFile("sample.json")
    var parsed interface{}
    json.Unmarshal(data, &parsed)

    for i := 0; i < 10000; i++ {
        json.Marshal(parsed)
    }
}
GOEOF

if command -v go &> /dev/null && [ "$GO_AVAILABLE" = true ]; then
    go build -o /tmp/bench_json_stringify_go /tmp/bench_json_stringify_go.go 2>&1 | tail -5
    if [ ! -f /tmp/bench_json_stringify_go ]; then
        echo "⚠️  Go stringify build failed"
        GO_AVAILABLE=false
    else
        echo "✅ Go stringify benchmark built"
    fi
fi

# Create Python PARSE benchmark
cat > /tmp/bench_json_parse_python.py <<'PYEOF'
import json

with open('sample.json') as f:
    json_data = f.read()

for _ in range(10000):
    parsed = json.loads(json_data)
PYEOF

# Create Python STRINGIFY benchmark
cat > /tmp/bench_json_stringify_python.py <<'PYEOF'
import json

with open('sample.json') as f:
    json_data = f.read()

parsed = json.loads(json_data)

for _ in range(10000):
    stringified = json.dumps(parsed)
PYEOF

echo ""
echo "═══════════════════════════════════"
echo "Running PARSE benchmarks..."
echo "═══════════════════════════════════"

# Build PyAOT parse benchmark (optimized with C allocator, WASM-compatible)
echo "🔨 Building PyAOT parse benchmark..."
if [ -f bench_pyaot_json_parse_fast.zig ]; then
    zig build-exe bench_pyaot_json_parse_fast.zig -O ReleaseFast -lc -femit-bin=/tmp/bench_pyaot_json_parse 2>&1 | head -10
    if [ -f /tmp/bench_pyaot_json_parse ]; then
        echo "✅ PyAOT parse benchmark built (C allocator)"
        PYAOT_AVAILABLE=true
    else
        echo "⚠️  PyAOT build failed"
        PYAOT_AVAILABLE=false
    fi
else
    echo "⚠️  PyAOT benchmark not found"
    PYAOT_AVAILABLE=false
fi

# Build hyperfine command for PARSE
PARSE_CMD=(
    hyperfine
    --warmup 2
    --runs 5
    --export-markdown bench_json_parse_results.md
    --command-name "Zig (stdlib parse)" "/tmp/bench_json_parse_zig"
    --command-name "Python (parse)" "python3 /tmp/bench_json_parse_python.py"
)

if [ "$PYAOT_AVAILABLE" = true ]; then
    PARSE_CMD+=(--command-name "PyAOT (parse)" "/tmp/bench_pyaot_json_parse")
fi

if [ "$RUST_AVAILABLE" = true ]; then
    PARSE_CMD+=(--command-name "Rust (parse)" "/tmp/bench_json_parse_rust")
fi

if [ "$GO_AVAILABLE" = true ]; then
    PARSE_CMD+=(--command-name "Go (parse)" "/tmp/bench_json_parse_go")
fi

"${PARSE_CMD[@]}"

echo ""
echo "═══════════════════════════════════"
echo "Running STRINGIFY benchmarks..."
echo "═══════════════════════════════════"

# Build PyAOT stringify benchmark (optimized with C allocator, WASM-compatible)
echo "🔨 Building PyAOT stringify benchmark..."
if [ -f bench_pyaot_json_stringify_fast.zig ]; then
    zig build-exe bench_pyaot_json_stringify_fast.zig -O ReleaseFast -lc -femit-bin=/tmp/bench_pyaot_json_stringify 2>&1 | head -10
    if [ -f /tmp/bench_pyaot_json_stringify ]; then
        echo "✅ PyAOT stringify benchmark built (C allocator)"
        PYAOT_STRINGIFY_AVAILABLE=true
    else
        echo "⚠️  PyAOT stringify build failed"
        PYAOT_STRINGIFY_AVAILABLE=false
    fi
else
    echo "⚠️  PyAOT stringify benchmark not found"
    PYAOT_STRINGIFY_AVAILABLE=false
fi

# Build hyperfine command for STRINGIFY
STRINGIFY_CMD=(
    hyperfine
    --warmup 2
    --runs 5
    --export-markdown bench_json_stringify_results.md
    --command-name "Python (stringify)" "python3 /tmp/bench_json_stringify_python.py"
)

if [ "$PYAOT_STRINGIFY_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "PyAOT (stringify)" "/tmp/bench_pyaot_json_stringify")
fi

if [ "$RUST_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "Rust (stringify)" "/tmp/bench_json_stringify_rust")
fi

if [ "$GO_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "Go (stringify)" "/tmp/bench_json_stringify_go")
fi

"${STRINGIFY_CMD[@]}"

echo ""
echo "📊 JSON PARSE results:"
cat bench_json_parse_results.md
echo ""
echo "📊 JSON STRINGIFY results:"
cat bench_json_stringify_results.md
echo ""
echo "✅ Benchmark complete!"
