#!/bin/bash
# HTTP Client Benchmark
# Compares PyAOT vs Rust vs Go vs Python vs PyPy
# Tests HTTPS request performance (ssl, socket, networking)

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "HTTP Client Benchmark - 50 HTTPS requests"
echo ""
echo "Fetching https://httpbin.org/get 50 times"
echo "Tests: SSL/TLS, socket, HTTP client, JSON parsing"
echo ""

# Python source (SAME code for PyAOT, Python, PyPy)
# Note: Using single variable to avoid type inference issues in PyAOT
cat > http_client.py <<'EOF'
import requests

# Benchmark: 50 HTTPS requests
i = 0
success = 0
while i < 50:
    resp = requests.get("https://httpbin.org/get")
    if resp.ok:
        success = success + 1
    i = i + 1

print(success)
EOF

# Go source (with HTTPS support)
mkdir -p go
cat > go/http_client.go <<'EOF'
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
compile_pyaot http_client.py http_client_pyaot || true

# Compile Go (with HTTPS)
compile_go go/http_client.go http_client_go

print_header "Running Benchmark"
echo "Note: Network latency dominates this benchmark"
echo "      Measures: TLS handshake + HTTP round-trip + response parsing"
echo ""

# Build command array
BENCH_CMDS=()

# PyAOT (native Zig HTTP client with HTTPS)
add_pyaot BENCH_CMDS http_client_pyaot

# Go (native HTTPS)
add_go BENCH_CMDS http_client_go

# Python with requests (HTTPS)
add_python BENCH_CMDS http_client.py

# PyPy with requests (HTTPS) - skip if requests not installed
if [ "$PYPY_AVAILABLE" = true ]; then
    if pypy3 -c "import requests" 2>/dev/null; then
        add_pypy BENCH_CMDS http_client.py
    else
        echo -e "  ${YELLOW}⚠${NC} PyPy skipped (requests not installed)"
    fi
fi

# Run benchmark (fewer runs since network-bound)
hyperfine \
    --warmup 1 \
    --runs 3 \
    --export-markdown results.md \
    "${BENCH_CMDS[@]}"

print_header "Results"
cat results.md

# Cleanup
rm -f http_client.py http_client_pyaot http_client_go
rm -rf go
