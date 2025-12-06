#!/bin/bash
# HTTP/1.1 Client Benchmark (TLS + Gzip)
# Compares metal0 vs Rust vs Go vs Python vs PyPy
#
# Tests HTTPS + TLS + Gzip against real server (google.com)

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

ITERATIONS=100
URL="https://www.google.com"

init_benchmark_compiled "HTTP/1.1 Client Benchmark (TLS + Gzip)"
echo ""
echo "URL: $URL"
echo "Features: HTTP/1.1, TLS, Gzip (auto-negotiated)"
echo "Iterations: $ITERATIONS requests per test"
echo ""

# Python source for metal0 (uses http module)
cat > http_client_metal0.py <<EOF
import http

for _ in range($ITERATIONS):
    r = http.get("$URL")
    _ = r.body
EOF

# Python source for CPython/PyPy (uses requests)
cat > http_client.py <<EOF
import requests

for _ in range($ITERATIONS):
    r = requests.get("$URL")
    _ = r.text
EOF

# Go source (HTTP/1.1 with TLS)
cat > http_client.go <<EOF
package main

import (
	"crypto/tls"
	"io"
	"net/http"
)

const url = "$URL"
const iterations = $ITERATIONS

func main() {
	// Force HTTP/1.1
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{},
		ForceAttemptHTTP2: false,
	}
	client := &http.Client{Transport: transport}

	for i := 0; i < iterations; i++ {
		resp, err := client.Get(url)
		if err == nil {
			io.ReadAll(resp.Body)
			resp.Body.Close()
		}
	}
}
EOF

# Rust source (using ureq - HTTP/1.1 only)
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "http_client"
version = "0.1.0"
edition = "2021"

[dependencies]
ureq = "2"

[profile.release]
lto = true
codegen-units = 1
EOF

cat > rust/src/main.rs <<EOF
const URL: &str = "$URL";
const ITERATIONS: usize = $ITERATIONS;

fn main() {
    let agent = ureq::Agent::new();

    for _ in 0..ITERATIONS {
        match agent.get(URL).call() {
            Ok(resp) => { let _ = resp.into_string(); }
            Err(_) => {}
        }
    }
}
EOF

print_header "Installing Dependencies"
ensure_python_pkg requests
ensure_pypy_pkg requests

print_header "Building"

build_metal0_compiler

# Build metal0 client
if compile_metal0 http_client_metal0.py http_client_metal0; then
    METAL0_BUILT=true
fi

# Build Go client
compile_go http_client.go http_client_go

# Build Rust client
if [ "$RUST_AVAILABLE" = true ]; then
    echo "  Building Rust..."
    cd rust && cargo build --release --quiet 2>/dev/null && cd ..
    if [ -f rust/target/release/http_client ]; then
        cp rust/target/release/http_client http_client_rust
        echo -e "  ${GREEN}✓${NC} Rust"
    else
        echo -e "  ${YELLOW}⚠${NC} Rust build failed"
    fi
fi

# Cleanup function
cleanup() {
    rm -f http_client.py http_client_metal0.py http_client.go http_client_metal0 http_client_go http_client_rust
    rm -rf rust
}
trap cleanup EXIT

print_header "Running Benchmark"
echo "URL: $URL"
echo "Iterations: $ITERATIONS"
echo ""

BENCH_CMD=(hyperfine --warmup 1 --runs 5)

if [ "$METAL0_BUILT" = true ] && [ -f http_client_metal0 ]; then
    BENCH_CMD+=(--command-name "metal0" "./http_client_metal0")
fi

if [ "$RUST_AVAILABLE" = true ] && [ -f http_client_rust ]; then
    BENCH_CMD+=(--command-name "Rust" "./http_client_rust")
fi

if [ "$GO_AVAILABLE" = true ] && [ -f http_client_go ]; then
    BENCH_CMD+=(--command-name "Go" "./http_client_go")
fi

if [ "$PYPY_AVAILABLE" = true ]; then
    if pypy3 -c "import requests" 2>/dev/null; then
        BENCH_CMD+=(--command-name "PyPy" "pypy3 http_client.py")
    fi
fi

BENCH_CMD+=(--command-name "Python" "python3 http_client.py")

"${BENCH_CMD[@]}"

print_header "Done"
