#!/bin/bash
# Quick JSON Stringify Benchmark - PyAOT vs Rust (10K iterations for fast feedback)
set -e
cd "$(dirname "$0")"

echo "⚡ Quick JSON Stringify Benchmark (10K iterations)"
echo "═══════════════════════════════════════════════════"
echo ""

# Create sample.json if not exists
if [ ! -f sample.json ]; then
    python3 <<'PYGEN'
import json

data = {
    "metadata": {
        "version": "2.0.0",
        "timestamp": "2025-01-23T12:00:00Z",
        "source": "PyAOT Benchmark"
    },
    "users": [
        {
            "id": i,
            "name": f"User {i}",
            "email": f"user{i}@example.com",
            "active": i % 2 == 0,
            "score": float(i * 3.14159),
            "tags": ["python", "rust", "zig"] if i % 3 == 0 else ["go", "typescript"]
        }
        for i in range(50)
    ],
    "products": [
        {
            "sku": f"PROD-{i:04d}",
            "name": f"Product {i}",
            "price": round(19.99 + i * 5.50, 2),
            "inStock": i % 3 != 0
        }
        for i in range(30)
    ]
}

with open('sample.json', 'w') as f:
    json.dump(data, f)

import os
size_kb = os.path.getsize('sample.json') / 1024
print(f"✅ Created sample.json ({size_kb:.1f} KB)")
PYGEN
fi

# Build PyAOT stringify benchmark (10K iterations)
echo "🔨 Building PyAOT stringify benchmark..."
cat > bench_pyaot_json_stringify_quick.zig <<'ZIGEOF'
const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("src/utils/allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const base_allocator = allocator_helper.getAllocator(gpa);

    const file = try std.fs.cwd().openFile("sample.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(base_allocator, 1024 * 1024);
    defer base_allocator.free(json_data);

    const json_str = try runtime.PyString.create(base_allocator, json_data);
    defer runtime.decref(json_str, base_allocator);

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const parsed = try json_module.loads(json_str, arena_allocator);

    // Stringify 10K times (10x faster than 100K for quick iteration)
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        const result = try json_module.dumps(parsed, base_allocator);
        runtime.decref(result, base_allocator);
    }
}
ZIGEOF

zig build-exe bench_pyaot_json_stringify_quick.zig -O ReleaseFast -lc -femit-bin=/tmp/bench_pyaot_json_stringify_quick 2>&1 | head -10
if [ -f /tmp/bench_pyaot_json_stringify_quick ]; then
    echo "✅ PyAOT stringify benchmark built"
    PYAOT_AVAILABLE=true
else
    echo "❌ PyAOT build failed"
    PYAOT_AVAILABLE=false
fi

# Build Rust stringify benchmark (10K iterations)
echo "🔨 Building Rust stringify benchmark..."
mkdir -p /tmp/bench_json_stringify_rust_quick_project/src
cd /tmp/bench_json_stringify_rust_quick_project

cat > Cargo.toml <<'CARGOEOF'
[package]
name = "bench_json_stringify_rust_quick"
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

    for _ in 0..10_000 {
        let _stringified = serde_json::to_string(&parsed).expect("Failed to stringify");
    }
}
RUSTEOF

if command -v cargo &> /dev/null; then
    cargo build --release 2>&1 | tail -5
    cp target/release/bench_json_stringify_rust_quick /tmp/bench_json_stringify_rust_quick 2>/dev/null || true
    cd - > /dev/null
    if [ -f /tmp/bench_json_stringify_rust_quick ]; then
        echo "✅ Rust stringify benchmark built"
        RUST_AVAILABLE=true
    else
        echo "❌ Rust build failed"
        RUST_AVAILABLE=false
    fi
else
    echo "⚠️  Rust not available"
    RUST_AVAILABLE=false
    cd - > /dev/null
fi

echo ""
echo "Running benchmarks (10K iterations, 5 runs)..."
echo ""

# Build hyperfine command
STRINGIFY_CMD=(
    hyperfine
    --warmup 2
    --runs 5
    --export-markdown bench_quick_results.md
)

if [ "$PYAOT_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "PyAOT" "/tmp/bench_pyaot_json_stringify_quick")
fi

if [ "$RUST_AVAILABLE" = true ]; then
    STRINGIFY_CMD+=(--command-name "Rust" "/tmp/bench_json_stringify_rust_quick")
fi

"${STRINGIFY_CMD[@]}"

echo ""
echo "📊 Quick results:"
cat bench_quick_results.md
echo ""
echo "✅ Quick benchmark complete!"
echo "💡 For full benchmark (100K iterations, all languages): make benchmark-json"
