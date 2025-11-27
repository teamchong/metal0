#!/bin/bash
# JSON Parse and Stringify Benchmark (separated)
# Compares Zig vs Rust vs Python vs Go on JSON operations
set -e
cd "$(dirname "$0")"

echo "📊 JSON Parse & Stringify Benchmark"
echo "═══════════════════════════════════"
echo "Operations: Parse JSON × 50K | Stringify × 50K"
echo "Data: 62KB realistic JSON with nested structures"
echo "Total: 3.1GB processed per benchmark (50K × 62KB)"
echo "Runtime: ~5 minutes (reduced from 20min for faster iteration)"
echo ""

# Create realistic large JSON data if not exists
if [ ! -f sample.json ]; then
    python3 <<'PYGEN'
import json

# Generate realistic large JSON data (~10-15KB)
data = {
    "metadata": {
        "version": "2.0.0",
        "timestamp": "2025-01-23T12:00:00Z",
        "source": "PyAOT Benchmark",
        "description": "Realistic JSON benchmark data with various structures and data types for fair performance comparison across libraries"
    },
    "users": [
        {
            "id": i,
            "name": f"User {i}",
            "email": f"user{i}@example.com",
            "active": i % 2 == 0,
            "score": float(i * 3.14159),
            "tags": ["python", "rust", "zig"] if i % 3 == 0 else ["go", "typescript"],
            "profile": {
                "bio": f"This is a longer biography text for user {i} with various characters: \n\t• Special chars: \"quoted\", \\backslash\\, /slash/\n\t• Unicode: 世界 🌍\n\t• Numbers and symbols: $100, 50%, #hashtag",
                "settings": {
                    "notifications": True,
                    "theme": "dark" if i % 2 == 0 else "light",
                    "language": "en-US"
                }
            }
        }
        for i in range(50)
    ],
    "products": [
        {
            "sku": f"PROD-{i:04d}",
            "name": f"Product {i}",
            "description": "Long product description with multiple lines.\nThis includes features like:\n- Fast performance\n- Easy integration\n- Cross-platform support\n- Unicode: 日本語, Español, 中文",
            "price": round(19.99 + i * 5.50, 2),
            "inStock": i % 3 != 0,
            "categories": ["electronics", "software", "tools"],
            "reviews": [
                {
                    "rating": 4.5,
                    "comment": "Great product! Works as expected.",
                    "reviewer": f"reviewer{j}@test.com"
                }
                for j in range(3)
            ]
        }
        for i in range(30)
    ],
    "analytics": {
        "daily_stats": [
            {
                "date": f"2025-01-{day:02d}",
                "visits": 1000 + day * 50,
                "conversions": 10 + day,
                "revenue": round(500.50 + day * 25.75, 2),
                "metrics": {
                    "bounce_rate": 0.35 + day * 0.01,
                    "avg_session": 180 + day * 5,
                    "pages_per_session": 3.5 + day * 0.1
                }
            }
            for day in range(1, 32)
        ],
        "traffic_sources": {
            "direct": 45.2,
            "search": 28.7,
            "social": 15.3,
            "referral": 8.5,
            "email": 2.3
        }
    },
    "configuration": {
        "api_endpoints": [
            "https://api.example.com/v1/users",
            "https://api.example.com/v1/products",
            "https://api.example.com/v1/orders"
        ],
        "features": {
            "authentication": True,
            "caching": True,
            "rate_limiting": True,
            "compression": True
        },
        "limits": {
            "max_requests_per_minute": 1000,
            "max_payload_size_mb": 10,
            "timeout_seconds": 30
        }
    }
}

with open('sample.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

# Print size
import os
size_kb = os.path.getsize('sample.json') / 1024
print(f"✅ Created sample.json ({size_kb:.1f} KB)")
PYGEN
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

    for (0..50_000) |_| {
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

# Skip Zig STRINGIFY benchmark (Zig 0.15.2 API changed - stringifyAlloc removed)
echo "⚠️  Skipping Zig stringify benchmark (API incompatible with 0.15.2)"
ZIG_STRINGIFY_AVAILABLE=false

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

    for _ in 0..50_000 {
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

    for _ in 0..100_000 {
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

    for i := 0; i < 50000; i++ {
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

    for i := 0; i < 50000; i++ {
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

for _ in range(50_000):
    parsed = json.loads(json_data)
PYEOF

# Create Python STRINGIFY benchmark
cat > /tmp/bench_json_stringify_python.py <<'PYEOF'
import json

with open('sample.json') as f:
    json_data = f.read()

parsed = json.loads(json_data)

for _ in range(50_000):
    stringified = json.dumps(parsed)
PYEOF

echo ""
echo "═══════════════════════════════════"
echo "Running PARSE benchmarks..."
echo "═══════════════════════════════════"

# Build PyAOT parse benchmark (use pre-built binary from build system)
echo "🔨 Building PyAOT parse benchmark..."
PYAOT_ROOT="$(cd ../../.. && pwd)"
cd "$PYAOT_ROOT" && zig build -Doptimize=ReleaseFast && cd - >/dev/null
if [ -f "$PYAOT_ROOT/zig-out/bin/bench_pyaot_json_parse" ]; then
    ln -sf "$PYAOT_ROOT/zig-out/bin/bench_pyaot_json_parse" /tmp/bench_pyaot_json_parse
    echo "✅ PyAOT parse benchmark built (C allocator)"
    PYAOT_AVAILABLE=true
else
    echo "⚠️  PyAOT build failed"
    PYAOT_AVAILABLE=false
fi

# Build hyperfine command for PARSE
PARSE_CMD=(
    hyperfine
    --warmup 2
    --runs 3
    --export-markdown bench_json_parse_results.md
)

if [ "$RUST_AVAILABLE" = true ]; then
    PARSE_CMD+=(--command-name "Rust (serde_json)" "/tmp/bench_json_parse_rust")
fi

if [ "$PYAOT_AVAILABLE" = true ]; then
    PARSE_CMD+=(--command-name "PyAOT" "/tmp/bench_pyaot_json_parse")
fi

PARSE_CMD+=(--command-name "Zig (std.json)" "/tmp/bench_json_parse_zig")
PARSE_CMD+=(--command-name "Python" "python3 /tmp/bench_json_parse_python.py")

if command -v pypy3 &> /dev/null; then
    PARSE_CMD+=(--command-name "PyPy" "pypy3 /tmp/bench_json_parse_python.py")
fi

if [ "$GO_AVAILABLE" = true ]; then
    PARSE_CMD+=(--command-name "Go" "/tmp/bench_json_parse_go")
fi

"${PARSE_CMD[@]}"

echo ""
echo "═══════════════════════════════════"
echo "Running STRINGIFY benchmarks..."
echo "═══════════════════════════════════"

# Use pre-built PyAOT stringify benchmark
echo "🔨 Using PyAOT stringify benchmark..."
if [ -f "$PYAOT_ROOT/zig-out/bin/bench_pyaot_json_stringify" ]; then
    ln -sf "$PYAOT_ROOT/zig-out/bin/bench_pyaot_json_stringify" /tmp/bench_pyaot_json_stringify
    echo "✅ PyAOT stringify benchmark ready (C allocator)"
    PYAOT_STRINGIFY_AVAILABLE=true
else
    echo "⚠️  PyAOT stringify benchmark not found"
    PYAOT_STRINGIFY_AVAILABLE=false
fi

# Build hyperfine command for STRINGIFY
STRINGIFY_CMD=(
    hyperfine
    --warmup 2
    --runs 3
    --export-markdown bench_json_stringify_results.md
)

if [ "$RUST_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "Rust (serde_json)" "/tmp/bench_json_stringify_rust")
fi

if [ "$PYAOT_STRINGIFY_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "PyAOT" "/tmp/bench_pyaot_json_stringify")
fi

STRINGIFY_CMD+=(--command-name "Python" "python3 /tmp/bench_json_stringify_python.py")

if command -v pypy3 &> /dev/null; then
    STRINGIFY_CMD+=(--command-name "PyPy" "pypy3 /tmp/bench_json_stringify_python.py")
fi

if [ "$GO_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "Go" "/tmp/bench_json_stringify_go")
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
