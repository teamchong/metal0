#!/bin/bash
# WebSocket Client Benchmark
# Compares metal0 vs Rust vs Go vs Python vs PyPy
#
# Tests WebSocket message exchange against echo server

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

ITERATIONS=100
MESSAGE_SIZE=1024

# Public WebSocket echo server (TLS)
WS_URL="wss://ws.postman-echo.com/raw"
# Local echo server for metal0 (no TLS)
LOCAL_WS_URL="ws://127.0.0.1:9876"

# Create Go echo server source
cat > echo_server.go <<'SERVEREOF'
package main

import (
	"net/http"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func echo(w http.ResponseWriter, r *http.Request) {
	c, _ := upgrader.Upgrade(w, r, nil)
	defer c.Close()
	for {
		mt, msg, err := c.ReadMessage()
		if err != nil { break }
		c.WriteMessage(mt, msg)
	}
}

func main() {
	http.HandleFunc("/", echo)
	http.ListenAndServe(":9876", nil)
}
SERVEREOF

init_benchmark_compiled "WebSocket Client Benchmark"
echo ""
echo "URL (all local): $LOCAL_WS_URL"
echo "Message size: $MESSAGE_SIZE bytes"
echo "Iterations: $ITERATIONS messages per test"
echo ""

# Python source for metal0 (uses local server)
cat > ws_client_metal0.py <<EOF
import websocket

ws = websocket.connect("$LOCAL_WS_URL")
msg = "x" * $MESSAGE_SIZE

total = 0
for i in range($ITERATIONS):
    ws.send(msg)
    result = ws.recv()
    total = total + len(result)

ws.close()
EOF

# Python source for CPython/PyPy - also use local server for fair comparison
cat > ws_client.py <<EOF
from websocket import create_connection

ws = create_connection("$LOCAL_WS_URL")
msg = "x" * $MESSAGE_SIZE

for _ in range($ITERATIONS):
    ws.send(msg)
    _ = ws.recv()

ws.close()
EOF

# Go source - use local server for fair comparison
cat > ws_client.go <<EOF
package main

import (
	"github.com/gorilla/websocket"
)

const wsURL = "$LOCAL_WS_URL"
const iterations = $ITERATIONS
const messageSize = $MESSAGE_SIZE

func main() {
	msg := make([]byte, messageSize)
	for i := range msg {
		msg[i] = 'x'
	}

	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	for i := 0; i < iterations; i++ {
		conn.WriteMessage(websocket.TextMessage, msg)
		_, _, _ = conn.ReadMessage()
	}
}
EOF

# Rust source (using tungstenite with native-tls for wss://)
mkdir -p rust/src
cat > rust/Cargo.toml <<'EOF'
[package]
name = "ws_client"
version = "0.1.0"
edition = "2021"

[dependencies]
tungstenite = { version = "0.24", features = ["native-tls"] }
native-tls = "0.2"

[profile.release]
lto = true
codegen-units = 1
EOF

cat > rust/src/main.rs <<EOF
use tungstenite::{connect, Message};

const WS_URL: &str = "$LOCAL_WS_URL";
const ITERATIONS: usize = $ITERATIONS;
const MESSAGE_SIZE: usize = $MESSAGE_SIZE;

fn main() {
    let msg: String = "x".repeat(MESSAGE_SIZE);
    let (mut socket, _) = connect(WS_URL).expect("Can't connect");
    for _ in 0..ITERATIONS {
        socket.send(Message::Text(msg.clone())).unwrap();
        let _ = socket.read();
    }
    socket.close(None).ok();
}
EOF

print_header "Installing Dependencies"
ensure_python_pkg websocket-client
ensure_pypy_pkg websocket-client

print_header "Building"

build_metal0_compiler

# Build and start local echo server for metal0
echo "  Building echo server..."
cat > go.mod <<EOF
module ws_bench
go 1.21
require github.com/gorilla/websocket v1.5.3
EOF
go mod tidy 2>/dev/null
go build -o echo_server echo_server.go 2>/dev/null
if [ -f echo_server ]; then
    echo -e "  ${GREEN}✓${NC} Echo server"
    # Start in background
    ./echo_server &
    ECHO_SERVER_PID=$!
    sleep 1
else
    echo -e "  ${YELLOW}⚠${NC} Echo server build failed"
    ECHO_SERVER_PID=""
fi

# Build metal0 client
METAL0_BUILT=false
if [ -n "$ECHO_SERVER_PID" ]; then
    if compile_metal0 ws_client_metal0.py ws_client_metal0; then
        METAL0_BUILT=true
    else
        echo -e "  ${YELLOW}⚠${NC} metal0: Build failed"
    fi
fi

# Build Go client (requires gorilla/websocket)
if [ "$GO_AVAILABLE" = true ]; then
    echo "  Building Go..."
    cat > go.mod <<EOF
module ws_bench
go 1.21
require github.com/gorilla/websocket v1.5.3
EOF
    go mod tidy 2>/dev/null
    if compile_go ws_client.go ws_client_go; then
        :
    fi
fi

# Build Rust client
if [ "$RUST_AVAILABLE" = true ]; then
    echo "  Building Rust..."
    cd rust && cargo build --release --quiet 2>/dev/null && cd ..
    if [ -f rust/target/release/ws_client ]; then
        cp rust/target/release/ws_client ws_client_rust
        echo -e "  ${GREEN}✓${NC} Rust"
    else
        echo -e "  ${YELLOW}⚠${NC} Rust build failed"
    fi
fi

# Cleanup function
cleanup() {
    # Kill echo server if running
    if [ -n "$ECHO_SERVER_PID" ]; then
        kill $ECHO_SERVER_PID 2>/dev/null || true
    fi
    rm -f ws_client.py ws_client_metal0.py ws_client.go ws_client_metal0 ws_client_go ws_client_rust
    rm -f go.mod go.sum echo_server.go echo_server
    rm -rf rust
}
trap cleanup EXIT

print_header "Running Benchmark"
echo "URL: $LOCAL_WS_URL"
echo "Message size: $MESSAGE_SIZE bytes"
echo "Iterations: $ITERATIONS"
echo ""

BENCH_CMD=(hyperfine --warmup 1 --runs 5 --ignore-failure)

if [ "$METAL0_BUILT" = true ] && [ -f ws_client_metal0 ]; then
    BENCH_CMD+=(--command-name "metal0" "./ws_client_metal0")
fi

if [ "$RUST_AVAILABLE" = true ] && [ -f ws_client_rust ]; then
    BENCH_CMD+=(--command-name "Rust" "./ws_client_rust")
fi

if [ "$GO_AVAILABLE" = true ] && [ -f ws_client_go ]; then
    BENCH_CMD+=(--command-name "Go" "./ws_client_go")
fi

if [ "$PYPY_AVAILABLE" = true ]; then
    if pypy3 -c "import websocket" 2>/dev/null; then
        BENCH_CMD+=(--command-name "PyPy" "pypy3 ws_client.py")
    fi
fi

# Add Python (websocket-client was auto-installed above)
if python3 -c "import websocket" 2>/dev/null; then
    BENCH_CMD+=(--command-name "Python" "python3 ws_client.py")
fi

if [ ${#BENCH_CMD[@]} -gt 4 ]; then
    "${BENCH_CMD[@]}"
else
    echo -e "${RED}No implementations available to benchmark${NC}"
fi

print_header "Done"
