#!/bin/bash
# HTTP Client Benchmark
# Compares PyAOT vs Rust vs Go vs Python vs PyPy
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "HTTP Client Benchmark - 50 HTTPS requests"
echo ""
echo "Fetching https://httpbin.org/get 50 times"
echo "Tests: SSL/TLS, socket, HTTP client"
echo ""

# Python source (SAME code for PyAOT, Python, PyPy)
cat > http_bench.py <<'EOF'
import requests

i = 0
success = 0
while i < 50:
    resp = requests.get("https://httpbin.org/get")
    if resp.ok:
        success = success + 1
    i = i + 1

print(success)
EOF

# Rust source (using ureq - popular simple HTTP client)
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "http_bench"
version = "0.1.0"
edition = "2021"

[dependencies]
ureq = { version = "2", features = ["tls"] }

[profile.release]
lto = true
codegen-units = 1
EOF

cat > rust/src/main.rs <<'EOF'
fn main() {
    let mut success = 0;
    for _ in 0..50 {
        match ureq::get("https://httpbin.org/get").call() {
            Ok(resp) => {
                if resp.status() == 200 {
                    let _ = resp.into_string();
                    success += 1;
                }
            }
            Err(_) => {}
        }
    }
    println!("{}", success);
}
EOF

# Go source (using net/http - standard but very popular)
cat > http_bench.go <<'EOF'
package main

import (
	"fmt"
	"io"
	"net/http"
)

func main() {
	success := 0
	client := &http.Client{}

	for i := 0; i < 50; i++ {
		resp, err := client.Get("https://httpbin.org/get")
		if err == nil {
			io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode == 200 {
				success++
			}
		}
	}

	fmt.Println(success)
}
EOF

print_header "Building"

build_pyaot_compiler
compile_pyaot http_bench.py http_bench_pyaot
compile_go http_bench.go http_bench_go

# Rust with cargo (needs network for deps)
if [ "$RUST_AVAILABLE" = true ]; then
    echo "  Building Rust (may take a moment for deps)..."
    cd rust && cargo build --release --quiet 2>/dev/null && cd ..
    if [ -f rust/target/release/http_bench ]; then
        cp rust/target/release/http_bench http_bench_rust
        echo -e "  ${GREEN}✓${NC} Rust: http_bench"
    else
        echo -e "  ${YELLOW}⚠${NC} Rust build failed"
    fi
fi

print_header "Running Benchmark"
echo "Note: Network latency dominates (~200-300ms per request)"
echo ""

BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results.md)

add_pyaot BENCH_CMD http_bench_pyaot
add_rust BENCH_CMD http_bench_rust
add_go BENCH_CMD http_bench_go

# Check if PyPy has requests installed
if [ "$PYPY_AVAILABLE" = true ]; then
    if pypy3 -c "import requests" 2>/dev/null; then
        add_pypy BENCH_CMD http_bench.py
    else
        echo -e "  ${YELLOW}⚠${NC} PyPy skipped (requests not installed: pypy3 -m pip install requests)"
    fi
fi

add_python BENCH_CMD http_bench.py requests

"${BENCH_CMD[@]}"

print_header "Results"
cat results.md

# Cleanup
rm -f http_bench.py http_bench.go http_bench_pyaot http_bench_rust http_bench_go
rm -rf rust
