#!/bin/bash
# Web Server Benchmark using wrk
# Tests HTTP server throughput (requests/sec)
# Same Python code runs on: metal0, Python, PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

echo "Web Server Benchmark - HTTP throughput"
echo "======================================="
echo ""
echo "Testing: Hello World JSON endpoint"
echo "Tool: wrk (HTTP benchmarking tool)"
echo ""

# Check for wrk
if ! command -v wrk &> /dev/null; then
    echo -e "${RED}Error: wrk not found${NC}"
    echo "Install: brew install wrk"
    exit 1
fi

# Ports for each server
PORT_METAL0_FLASK=8081
PORT_PYTHON_FLASK=8082
PORT_PYPY_FLASK=8083
PORT_METAL0_DJANGO=8084
PORT_PYTHON_DJANGO=8085
PORT_PYPY_DJANGO=8086
PORT_RUST=8087
PORT_GO=8088

# Flask server - SAME CODE for metal0, Python, PyPy
cat > server_flask.py <<'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify(message="Hello, World!")

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    app.run(host='127.0.0.1', port=port, threaded=True)
EOF

# Django server - SAME CODE for metal0, Python, PyPy
cat > server_django.py <<'EOF'
import sys
import json
from django.conf import settings
from django.http import JsonResponse
from django.urls import path

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

settings.configure(
    DEBUG=False,
    ROOT_URLCONF=__name__,
    SECRET_KEY='benchmark-secret-key',
    ALLOWED_HOSTS=['*'],
)

def hello(request):
    return JsonResponse({"message": "Hello, World!"})

urlpatterns = [path('', hello)]

if __name__ == '__main__':
    from django.core.management import execute_from_command_line
    execute_from_command_line(['manage.py', 'runserver', f'127.0.0.1:{port}', '--noreload'])
EOF

# Go source (for comparison)
cat > server_go.go <<'EOF'
package main

import (
	"encoding/json"
	"net/http"
	"os"
)

type Message struct {
	Message string `json:"message"`
}

func handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Message{Message: "Hello, World!"})
}

func main() {
	port := "8088"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}
	http.HandleFunc("/", handler)
	http.ListenAndServe(":"+port, nil)
}
EOF

# Rust source (actix-web, for comparison)
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "server_bench"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4"
serde = { version = "1", features = ["derive"] }

[profile.release]
lto = true
codegen-units = 1
EOF

cat > rust/src/main.rs <<'EOF'
use actix_web::{get, App, HttpServer, Responder, HttpResponse};
use serde::Serialize;
use std::env;

#[derive(Serialize)]
struct Message { message: String }

#[get("/")]
async fn hello() -> impl Responder {
    HttpResponse::Ok().json(Message { message: "Hello, World!".to_string() })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port = env::args().nth(1).unwrap_or("8087".to_string());
    HttpServer::new(|| App::new().service(hello))
        .bind(format!("127.0.0.1:{}", port))?
        .run()
        .await
}
EOF

echo "=== Building ==="

# Build metal0 Flask
build_metal0_compiler
if command -v flask &> /dev/null || python3 -c "import flask" 2>/dev/null; then
    echo "  Building metal0 Flask..."
    compile_metal0 server_flask.py server_flask_metal0 2>/dev/null && echo -e "  ${GREEN}✓${NC} metal0 Flask" || echo -e "  ${YELLOW}⚠${NC} metal0 Flask build failed"
fi

# Build Go
if command -v go &> /dev/null; then
    echo "  Building Go..."
    go build -o server_go server_go.go 2>/dev/null && echo -e "  ${GREEN}✓${NC} Go"
fi

# Build Rust
if command -v cargo &> /dev/null; then
    echo "  Building Rust (actix-web)..."
    cd rust && cargo build --release --quiet 2>/dev/null && cd ..
    if [ -f rust/target/release/server_bench ]; then
        cp rust/target/release/server_bench server_rust
        echo -e "  ${GREEN}✓${NC} Rust"
    fi
fi

echo ""
echo "=== Running Benchmark ==="
echo "Parameters: 4 threads, 100 connections, 10 seconds"
echo ""

# Results file
cat > results.md <<'EOF'
# Web Server Benchmark Results

| Server | Requests/sec | Latency (avg) | Transfer/sec |
|--------|-------------|---------------|--------------|
EOF

# Function to run benchmark
run_bench() {
    local name=$1
    local port=$2
    local cmd=$3

    echo -e "\n${CYAN}=== $name ===${NC}"

    # Start server in background
    eval "$cmd &"
    local pid=$!
    sleep 3  # Wait for server to start

    # Check if server is running
    if ! kill -0 $pid 2>/dev/null; then
        echo -e "${RED}Failed to start $name${NC}"
        return
    fi

    # Run wrk
    result=$(wrk -t4 -c100 -d10s http://127.0.0.1:$port/ 2>&1)
    echo "$result"

    # Parse results
    rps=$(echo "$result" | grep "Requests/sec" | awk '{print $2}')
    lat=$(echo "$result" | grep "Latency" | head -1 | awk '{print $2}')
    trans=$(echo "$result" | grep "Transfer/sec" | awk '{print $2}')

    if [ -n "$rps" ]; then
        echo "| $name | $rps | $lat | $trans |" >> results.md
    fi

    # Stop server
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    sleep 1
}

# Rust (fastest, for reference)
if [ -f server_rust ]; then
    run_bench "Rust (actix-web)" $PORT_RUST "./server_rust $PORT_RUST"
fi

# Go (for reference)
if [ -f server_go ]; then
    run_bench "Go (net/http)" $PORT_GO "./server_go $PORT_GO"
fi

# metal0 Flask
if [ -f server_flask_metal0 ]; then
    run_bench "metal0 (Flask)" $PORT_METAL0_FLASK "./server_flask_metal0 $PORT_METAL0_FLASK"
fi

# PyPy Flask
if command -v pypy3 &> /dev/null && pypy3 -c "import flask" 2>/dev/null; then
    run_bench "PyPy (Flask)" $PORT_PYPY_FLASK "pypy3 server_flask.py $PORT_PYPY_FLASK"
fi

# Python Flask
if python3 -c "import flask" 2>/dev/null; then
    run_bench "Python (Flask)" $PORT_PYTHON_FLASK "python3 server_flask.py $PORT_PYTHON_FLASK"
fi

# Django benchmarks (if available)
if python3 -c "import django" 2>/dev/null; then
    # Python Django
    run_bench "Python (Django)" $PORT_PYTHON_DJANGO "python3 server_django.py $PORT_PYTHON_DJANGO"
fi

if command -v pypy3 &> /dev/null && pypy3 -c "import django" 2>/dev/null; then
    # PyPy Django
    run_bench "PyPy (Django)" $PORT_PYPY_DJANGO "pypy3 server_django.py $PORT_PYPY_DJANGO"
fi

echo ""
echo "=== Results ==="
cat results.md

# Cleanup
rm -f server_flask.py server_django.py server_go.go
rm -f server_flask_metal0 server_go server_rust
rm -rf rust
