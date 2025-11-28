#!/bin/bash
# HTTP Client Benchmark (Local Server)
# Compares PyAOT vs Rust vs Go vs Python vs PyPy
# Uses a local server to eliminate network variability

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "HTTP Client Benchmark (Local) - 1000 requests"
echo ""
echo "Fetching from localhost:8888 - 1000 times"
echo "Tests: HTTP client overhead without network latency"
echo ""

# Simple local server (Python)
cat > server.py <<'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response = json.dumps({"origin": "127.0.0.1", "url": "http://localhost:8888/get"})
        self.wfile.write(response.encode())

    def log_message(self, format, *args):
        pass  # Suppress logging

if __name__ == "__main__":
    server = HTTPServer(('127.0.0.1', 8888), Handler)
    server.serve_forever()
EOF

# Python client source (for local server)
cat > http_local.py <<'EOF'
import requests

# Benchmark: 1000 HTTP requests to local server
i = 0
success = 0
while i < 1000:
    resp = requests.get("http://127.0.0.1:8888/get")
    if resp.ok:
        success = success + 1
    i = i + 1

print(success)
EOF

# Go client source (local)
mkdir -p go
cat > go/http_local.go <<'EOF'
package main

import (
	"fmt"
	"io"
	"net/http"
)

func main() {
	success := 0
	client := &http.Client{}

	for i := 0; i < 1000; i++ {
		resp, err := client.Get("http://127.0.0.1:8888/get")
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

# Rust client source (local HTTP)
mkdir -p rust
cat > rust/http_local.rs <<'EOF'
use std::io::{Read, Write};
use std::net::TcpStream;

fn main() {
    let mut success = 0;

    for _ in 0..1000 {
        if let Ok(mut stream) = TcpStream::connect("127.0.0.1:8888") {
            let request = "GET /get HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
            if stream.write_all(request.as_bytes()).is_ok() {
                let mut response = String::new();
                if stream.read_to_string(&mut response).is_ok() && response.contains("200 OK") {
                    success += 1;
                }
            }
        }
    }

    println!("{}", success);
}
EOF

print_header "Building"

build_pyaot_compiler
compile_pyaot http_local.py http_local_pyaot || true
compile_rust rust/http_local.rs http_local_rust
compile_go go/http_local.go http_local_go

print_header "Starting Local Server"
python3 server.py &
SERVER_PID=$!
sleep 1  # Wait for server to start

# Verify server is running
if ! curl -s http://127.0.0.1:8888/get >/dev/null 2>&1; then
    echo -e "${RED}Error: Server failed to start${NC}"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Server running on port 8888"

print_header "Running Benchmark"

# Build command array
BENCH_CMDS=()

add_pyaot BENCH_CMDS http_local_pyaot
add_rust BENCH_CMDS http_local_rust
add_go BENCH_CMDS http_local_go
add_python BENCH_CMDS http_local.py
add_pypy BENCH_CMDS http_local.py

# Run benchmark
hyperfine \
    --warmup 2 \
    --runs 5 \
    --export-markdown results_local.md \
    "${BENCH_CMDS[@]}"

# Stop server
kill $SERVER_PID 2>/dev/null

print_header "Results"
cat results_local.md

# Cleanup
rm -f server.py http_local.py http_local_pyaot http_local_rust http_local_go
rm -rf rust go
