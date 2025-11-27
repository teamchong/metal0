#!/bin/bash
# JSON Parse and Stringify Benchmark
# Compares PyAOT vs Rust vs Go vs Python vs PyPy
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "JSON Benchmark - 50K iterations"
echo ""
echo "Parse and Stringify ~38KB realistic JSON"
echo ""

# Generate sample.json if not exists
if [ ! -f sample.json ]; then
    echo "Generating sample.json..."
    python3 <<'PYGEN'
import json, os

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
            "tags": ["python", "rust", "zig"] if i % 3 == 0 else ["go", "typescript"],
            "profile": {
                "bio": f"Biography for user {i}",
                "settings": {"notifications": True, "theme": "dark" if i % 2 == 0 else "light"}
            }
        }
        for i in range(50)
    ],
    "products": [
        {
            "sku": f"PROD-{i:04d}",
            "name": f"Product {i}",
            "price": round(19.99 + i * 5.50, 2),
            "inStock": i % 3 != 0,
            "reviews": [{"rating": 4.5, "reviewer": f"reviewer{j}@test.com"} for j in range(3)]
        }
        for i in range(30)
    ],
    "analytics": {
        "daily_stats": [
            {"date": f"2025-01-{d:02d}", "visits": 1000 + d * 50, "revenue": round(500.50 + d * 25.75, 2)}
            for d in range(1, 32)
        ]
    }
}

with open('sample.json', 'w') as f:
    json.dump(data, f, indent=2)
print(f"Created sample.json ({os.path.getsize('sample.json') / 1024:.1f} KB)")
PYGEN
fi

# Python source for PARSE (SAME code for PyAOT, Python, PyPy)
cat > json_parse.py <<'EOF'
import json

f = open("sample.json", "r")
data = f.read()
f.close()

i = 0
while i < 50000:
    parsed = json.loads(data)
    i = i + 1
EOF

# Python source for STRINGIFY (SAME code for PyAOT, Python, PyPy)
cat > json_stringify.py <<'EOF'
import json

f = open("sample.json", "r")
data = f.read()
f.close()

parsed = json.loads(data)
i = 0
while i < 100000:
    s = json.dumps(parsed)
    i = i + 1
EOF

# Rust source
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "json_bench"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "parse"
path = "src/parse.rs"

[[bin]]
name = "stringify"
path = "src/stringify.rs"

[dependencies]
serde_json = "1.0"
EOF

cat > rust/src/parse.rs <<'EOF'
use std::fs;
fn main() {
    let data = fs::read_to_string("sample.json").unwrap();
    for _ in 0..50_000 { let _: serde_json::Value = serde_json::from_str(&data).unwrap(); }
}
EOF

cat > rust/src/stringify.rs <<'EOF'
use std::fs;
fn main() {
    let data = fs::read_to_string("sample.json").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&data).unwrap();
    for _ in 0..100_000 { let _ = serde_json::to_string(&parsed).unwrap(); }
}
EOF

# Go source
mkdir -p go
cat > go/parse.go <<'EOF'
package main
import ("encoding/json"; "os")
func main() {
    data, _ := os.ReadFile("sample.json")
    for i := 0; i < 50000; i++ { var p interface{}; json.Unmarshal(data, &p) }
}
EOF

cat > go/stringify.go <<'EOF'
package main
import ("encoding/json"; "os")
func main() {
    data, _ := os.ReadFile("sample.json")
    var p interface{}; json.Unmarshal(data, &p)
    for i := 0; i < 100000; i++ { json.Marshal(p) }
}
EOF

echo "Building..."
build_pyaot_compiler
compile_pyaot json_parse.py json_parse_pyaot
compile_pyaot json_stringify.py json_stringify_pyaot

# Build Rust
if [ "$RUST_AVAILABLE" = true ]; then
    cd rust && cargo build --release --quiet 2>/dev/null && cd ..
    [ -f rust/target/release/parse ] && echo -e "  ${GREEN}✓${NC} Rust: parse"
    [ -f rust/target/release/stringify ] && echo -e "  ${GREEN}✓${NC} Rust: stringify"
fi

# Build Go
if [ "$GO_AVAILABLE" = true ]; then
    CGO_ENABLED=0 go build -ldflags="-s -w" -o go/parse go/parse.go 2>/dev/null
    CGO_ENABLED=0 go build -ldflags="-s -w" -o go/stringify go/stringify.go 2>/dev/null
    [ -f go/parse ] && echo -e "  ${GREEN}✓${NC} Go: parse"
    [ -f go/stringify ] && echo -e "  ${GREEN}✓${NC} Go: stringify"
fi

# PARSE benchmarks
print_header "PARSE Benchmarks"
PARSE_CMD=(hyperfine --warmup 2 --runs 3 --export-markdown results_parse.md)

add_pyaot PARSE_CMD json_parse_pyaot
[ "$RUST_AVAILABLE" = true ] && [ -f rust/target/release/parse ] && PARSE_CMD+=(--command-name "Rust" "./rust/target/release/parse")
[ "$GO_AVAILABLE" = true ] && [ -f go/parse ] && PARSE_CMD+=(--command-name "Go" "./go/parse")
add_pypy PARSE_CMD json_parse.py
add_python PARSE_CMD json_parse.py

"${PARSE_CMD[@]}"

# STRINGIFY benchmarks
print_header "STRINGIFY Benchmarks"
STRINGIFY_CMD=(hyperfine --warmup 2 --runs 3 --export-markdown results_stringify.md)

add_pyaot STRINGIFY_CMD json_stringify_pyaot
[ "$RUST_AVAILABLE" = true ] && [ -f rust/target/release/stringify ] && STRINGIFY_CMD+=(--command-name "Rust" "./rust/target/release/stringify")
[ "$GO_AVAILABLE" = true ] && [ -f go/stringify ] && STRINGIFY_CMD+=(--command-name "Go" "./go/stringify")
add_pypy STRINGIFY_CMD json_stringify.py
add_python STRINGIFY_CMD json_stringify.py

"${STRINGIFY_CMD[@]}"

# Cleanup binaries
rm -f json_parse_pyaot json_stringify_pyaot

echo ""
echo "Results saved to: results_parse.md, results_stringify.md"
