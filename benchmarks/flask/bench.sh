#!/bin/bash
# Flask Web Benchmark
# Tests Flask + requests stack (without server - direct function test)
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Flask + Requests Benchmark"
echo ""
echo "Flask app logic + external HTTP fetch"
echo "Tests: Flask app creation + requests + response handling"
echo ""

# Python source (SAME code for PyAOT, Python, PyPy)
# Tests Flask app instantiation + requests fetch (no server needed)
cat > flask_bench.py <<'EOF'
from flask import Flask
import requests

app = Flask(__name__)

# Simulate what a route handler would do
i = 0
success = 0
while i < 10:
    resp = requests.get("https://httpbin.org/json")
    if resp.ok:
        success = success + 1
    i = i + 1

print(success)
EOF

# Go source
cat > flask_bench.go <<'EOF'
package main

import (
	"fmt"
	"io"
	"net/http"
)

func main() {
	success := 0
	client := &http.Client{}

	for i := 0; i < 10; i++ {
		resp, err := client.Get("https://httpbin.org/json")
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

# Rust source
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "flask_bench"
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
    for _ in 0..10 {
        match ureq::get("https://httpbin.org/json").call() {
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

print_header "Building"

build_pyaot_compiler
compile_pyaot flask_bench.py flask_bench_pyaot
compile_go flask_bench.go flask_bench_go

# Rust with cargo
if [ "$RUST_AVAILABLE" = true ]; then
    echo "  Building Rust..."
    cd rust && cargo build --release --quiet 2>/dev/null && cd ..
    if [ -f rust/target/release/flask_bench ]; then
        cp rust/target/release/flask_bench flask_bench_rust
        echo -e "  ${GREEN}✓${NC} Rust: flask_bench"
    else
        echo -e "  ${YELLOW}⚠${NC} Rust build failed"
    fi
fi

print_header "Running Benchmark"
echo "10 HTTPS requests with Flask app context"
echo ""

BENCH_CMD=(hyperfine --warmup 1 --runs 5 --export-markdown results.md)

add_pyaot BENCH_CMD flask_bench_pyaot
add_rust BENCH_CMD flask_bench_rust
add_go BENCH_CMD flask_bench_go

# Check if PyPy has flask+requests
if [ "$PYPY_AVAILABLE" = true ]; then
    if pypy3 -c "import flask, requests" 2>/dev/null; then
        add_pypy BENCH_CMD flask_bench.py
    else
        echo -e "  ${YELLOW}⚠${NC} PyPy skipped (flask/requests not installed: pypy3 -m pip install flask requests)"
    fi
fi

add_python BENCH_CMD flask_bench.py flask requests

"${BENCH_CMD[@]}"

print_header "Results"
cat results.md

# Cleanup
rm -f flask_bench.py flask_bench.go flask_bench_pyaot flask_bench_rust flask_bench_go
rm -rf rust
