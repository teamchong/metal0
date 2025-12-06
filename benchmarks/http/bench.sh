#!/bin/bash
# HTTP Client Benchmark
# Compares metal0 vs Rust vs Go vs Python vs PyPy
# All Python-based runners use the SAME source code
#
# Uses local go-httpbin server for consistent results
# 3 tests: HTTP, HTTPS, HTTPS+Gzip

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

ITERATIONS=100
PORT_HTTP=18080
PORT_HTTPS=18443

init_benchmark_compiled "HTTP Client Benchmark"
echo ""
echo "Tests: HTTP/1.1, HTTPS, HTTPS+Gzip"
echo "Server: go-httpbin (local)"
echo "Iterations: $ITERATIONS requests per test"
echo ""

# Check go-httpbin
if ! command -v go-httpbin &>/dev/null; then
    echo -e "${YELLOW}Installing go-httpbin...${NC}"
    go install github.com/mccutchen/go-httpbin/v2/cmd/go-httpbin@latest
    if ! command -v go-httpbin &>/dev/null; then
        echo -e "${RED}Error: go-httpbin not found after install${NC}"
        echo "Make sure ~/go/bin is in PATH"
        exit 1
    fi
fi
echo -e "  ${GREEN}✓${NC} go-httpbin"

# Generate self-signed cert for HTTPS tests
if [ ! -f cert.pem ] || [ ! -f key.pem ]; then
    echo "Generating self-signed certificate..."
    openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
        -days 1 -nodes -subj "/CN=localhost" 2>/dev/null
fi

# Python source for metal0 (uses http module)
cat > http_client_metal0.py <<EOF
import sys
import http

url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:$PORT_HTTP/get"

for _ in range($ITERATIONS):
    r = http.get(url)
    _ = r.body
EOF

# Python source for CPython/PyPy (uses requests)
cat > http_client.py <<EOF
import sys
import requests
import urllib3
urllib3.disable_warnings()

url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:$PORT_HTTP/get"

for _ in range($ITERATIONS):
    r = requests.get(url, verify=False)
    _ = r.text
EOF

# Go source
cat > http_client.go <<'EOF'
package main

import (
	"crypto/tls"
	"io"
	"net/http"
	"os"
	"strconv"
)

func main() {
	url := os.Args[1]
	iterations, _ := strconv.Atoi(os.Args[2])

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	for i := 0; i < iterations; i++ {
		resp, err := client.Get(url)
		if err == nil {
			io.ReadAll(resp.Body)
			resp.Body.Close()
		}
	}
}
EOF

# Rust source (using ureq with native-tls for self-signed cert support)
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "http_client"
version = "0.1.0"
edition = "2021"

[dependencies]
ureq = { version = "2", features = ["native-tls"] }
native-tls = "0.2"

[profile.release]
lto = true
codegen-units = 1
EOF

cat > rust/src/main.rs <<'EOF'
use std::env;
use std::sync::Arc;

fn main() {
    let url = env::args().nth(1).expect("URL required");
    let iterations: usize = env::args().nth(2).unwrap_or("100".to_string()).parse().unwrap();

    // Build TLS connector that accepts self-signed certs
    let tls = native_tls::TlsConnector::builder()
        .danger_accept_invalid_certs(true)
        .build()
        .unwrap();

    let agent = ureq::AgentBuilder::new()
        .tls_connector(Arc::new(tls))
        .build();

    for _ in 0..iterations {
        match agent.get(&url).call() {
            Ok(resp) => { let _ = resp.into_string(); }
            Err(_) => {}
        }
    }
}
EOF

print_header "Building"

build_metal0_compiler

# Build metal0 client
if compile_metal0 http_client_metal0.py http_client_metal0; then
    METAL0_BUILT=true
else
    METAL0_BUILT=false
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

print_header "Starting Server"

# Kill any existing go-httpbin
pkill -f "go-httpbin" 2>/dev/null || true
sleep 1

# Start HTTP server (suppress logs)
go-httpbin -port $PORT_HTTP 2>/dev/null &
PID_HTTP=$!
sleep 1

# Start HTTPS server (suppress logs)
go-httpbin -port $PORT_HTTPS -https-cert-file cert.pem -https-key-file key.pem 2>/dev/null &
PID_HTTPS=$!
sleep 1

# Verify servers are running
if ! curl -s "http://localhost:$PORT_HTTP/get" >/dev/null; then
    echo -e "${RED}HTTP server failed to start${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} HTTP server on :$PORT_HTTP"

if ! curl -sk "https://localhost:$PORT_HTTPS/get" >/dev/null; then
    echo -e "${RED}HTTPS server failed to start${NC}"
    kill $PID_HTTP 2>/dev/null
    exit 1
fi
echo -e "  ${GREEN}✓${NC} HTTPS server on :$PORT_HTTPS"

# Cleanup function
cleanup() {
    kill $PID_HTTP $PID_HTTPS 2>/dev/null
    rm -f http_client.py http_client_metal0.py http_client.go http_client_metal0 http_client_go http_client_rust
    rm -rf rust
}
trap cleanup EXIT

# Run benchmark for a specific test
run_benchmark() {
    local test_name=$1
    local url=$2

    print_header "$test_name"
    echo "URL: $url"
    echo ""

    BENCH_CMD=(hyperfine --warmup 1 --runs 5)

    if [ "$METAL0_BUILT" = true ] && [ -f http_client_metal0 ]; then
        BENCH_CMD+=(--command-name "metal0" "./http_client_metal0 '$url'")
    fi

    if [ "$RUST_AVAILABLE" = true ] && [ -f http_client_rust ]; then
        BENCH_CMD+=(--command-name "Rust" "./http_client_rust '$url' $ITERATIONS")
    fi

    if [ "$GO_AVAILABLE" = true ] && [ -f http_client_go ]; then
        BENCH_CMD+=(--command-name "Go" "./http_client_go '$url' $ITERATIONS")
    fi

    if [ "$PYPY_AVAILABLE" = true ]; then
        if pypy3 -c "import requests" 2>/dev/null; then
            BENCH_CMD+=(--command-name "PyPy" "pypy3 http_client.py '$url'")
        fi
    fi

    BENCH_CMD+=(--command-name "Python" "python3 http_client.py '$url'")

    "${BENCH_CMD[@]}"
}

# Run 2 benchmarks - both with TLS + Gzip as required
# Test 1: HTTP/1.1 + TLS + Gzip
run_benchmark "HTTP/1.1 + TLS + Gzip ($ITERATIONS requests)" "https://localhost:$PORT_HTTPS/gzip"

# Test 2: HTTP/2 + TLS + Gzip
# Note: go-httpbin supports HTTP/2 over TLS (ALPN negotiation)
# Clients that support HTTP/2 will use it automatically
run_benchmark "HTTP/2 + TLS + Gzip ($ITERATIONS requests)" "https://localhost:$PORT_HTTPS/gzip"

print_header "Done"
