/#!/usr/bin/env bash
set -euo pipefail

echo "🔬 metal0 JSON Optimization Comparison"
echo "═══════════════════════════════════════"
echo ""

# Build both versions
echo "🔨 Building baseline metal0 parse..."
zig build-exe bench_metal0_json_parse.zig -O ReleaseFast -femit-bin=/tmp/bench_metal0_json_parse 2>&1 | head -5
echo "✅ Baseline parse built"

echo "🔨 Building optimized metal0 parse..."
zig build-exe bench_metal0_json_parse_opt.zig -O ReleaseFast -femit-bin=/tmp/bench_metal0_json_parse_opt 2>&1 | head -5
echo "✅ Optimized parse built"

echo "🔨 Building baseline metal0 stringify..."
zig build-exe bench_metal0_json_stringify.zig -O ReleaseFast -femit-bin=/tmp/bench_metal0_json_stringify 2>&1 | head -5
echo "✅ Baseline stringify built"

echo "🔨 Building optimized metal0 stringify..."
zig build-exe bench_metal0_json_stringify_opt.zig -O ReleaseFast -femit-bin=/tmp/bench_metal0_json_stringify_opt 2>&1 | head -5
echo "✅ Optimized stringify built"

echo ""
echo "═══════════════════════════════════════"
echo "PARSE Benchmark Comparison"
echo "═══════════════════════════════════════"

hyperfine \
    --warmup 2 \
    --runs 5 \
    --export-markdown bench_metal0_parse_comparison.md \
    --command-name "metal0 Baseline (parse)" "/tmp/bench_metal0_json_parse" \
    --command-name "metal0 Optimized (parse)" "/tmp/bench_metal0_json_parse_opt"

echo ""
echo "═══════════════════════════════════════"
echo "STRINGIFY Benchmark Comparison"
echo "═══════════════════════════════════════"

hyperfine \
    --warmup 2 \
    --runs 5 \
    --export-markdown bench_metal0_stringify_comparison.md \
    --command-name "metal0 Baseline (stringify)" "/tmp/bench_metal0_json_stringify" \
    --command-name "metal0 Optimized (stringify)" "/tmp/bench_metal0_json_stringify_opt"

echo ""
echo "📊 PARSE Comparison Results:"
cat bench_metal0_parse_comparison.md
echo ""
echo "📊 STRINGIFY Comparison Results:"
cat bench_metal0_stringify_comparison.md
echo ""
echo "✅ Benchmark comparison complete!"
