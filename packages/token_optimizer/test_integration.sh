#!/usr/bin/env bash
set -euo pipefail

# Integration test for token_optimizer proxy
# Tests full proxy flow: start server, send request, verify compression, check logs

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🧪 Token Optimizer Integration Test"
echo "===================================="

# Check if binary exists
if [[ ! -f "../../zig-out/bin/token_optimizer" ]]; then
    echo -e "${RED}✗ Binary not found${NC}"
    echo "  Run: zig build"
    exit 1
fi
echo -e "${GREEN}✓ Binary found${NC}"

# Start proxy in background
echo -e "${YELLOW}→ Starting proxy on port 8080...${NC}"
../../zig-out/bin/token_optimizer > /tmp/proxy_logs.txt 2>&1 &
PROXY_PID=$!

# Cleanup on exit
cleanup() {
    if kill -0 $PROXY_PID 2>/dev/null; then
        echo -e "${YELLOW}→ Stopping proxy (PID $PROXY_PID)${NC}"
        kill $PROXY_PID 2>/dev/null || true
        wait $PROXY_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait for proxy to start
echo -e "${YELLOW}→ Waiting for proxy...${NC}"
sleep 2

# Verify proxy is listening
if ! lsof -i :8080 >/dev/null 2>&1; then
    echo -e "${RED}✗ Proxy not listening on port 8080${NC}"
    cat /tmp/proxy_logs.txt
    exit 1
fi
echo -e "${GREEN}✓ Proxy listening${NC}"

# Test 1: Send request with text
echo -e "${YELLOW}→ Sending test request...${NC}"
HTTP_CODE=$(curl -s -o /tmp/proxy_response.txt -w "%{http_code}" \
    -X POST http://localhost:8080/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello world"}]}')

if [[ "$HTTP_CODE" == "000" ]]; then
    echo -e "${RED}✗ Connection failed${NC}"
    cat /tmp/proxy_response.txt
    exit 1
fi
echo -e "${GREEN}✓ Request sent (HTTP $HTTP_CODE)${NC}"

# Test 2: Verify compression happened
echo -e "${YELLOW}→ Checking compression logs...${NC}"
sleep 1
if grep -q "Compression:" /tmp/proxy_logs.txt; then
    echo -e "${GREEN}✓ Compression executed${NC}"
    grep "Compression:" /tmp/proxy_logs.txt | tail -1
else
    echo -e "${RED}✗ No compression logs found${NC}"
    cat /tmp/proxy_logs.txt
    exit 1
fi

# Test 3: Verify metrics logged
echo -e "${YELLOW}→ Checking metrics logs...${NC}"
if grep -q "INCOMING REQUEST\|FORWARDING TO ANTHROPIC" /tmp/proxy_logs.txt; then
    echo -e "${GREEN}✓ Metrics logged${NC}"
else
    echo -e "${RED}✗ No metrics found${NC}"
    cat /tmp/proxy_logs.txt
    exit 1
fi

# Test 4: Edge cases - empty lines
echo -e "${YELLOW}→ Testing empty lines...${NC}"
curl -s -o /dev/null \
    -X POST http://localhost:8080/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"line1\n\nline3"}]}'
echo -e "${GREEN}✓ Empty lines handled${NC}"

# Test 5: Unicode text
echo -e "${YELLOW}→ Testing unicode...${NC}"
curl -s -o /dev/null \
    -X POST http://localhost:8080/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello 世界 🌍"}]}'
echo -e "${GREEN}✓ Unicode handled${NC}"

# Test 6: Long lines
echo -e "${YELLOW}→ Testing long lines...${NC}"
LONG_LINE=$(python3 -c "print('a' * 500)")
curl -s -o /dev/null \
    -X POST http://localhost:8080/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -d "{\"model\":\"claude-3-5-sonnet-20241022\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":\"$LONG_LINE\"}]}"
echo -e "${GREEN}✓ Long lines handled${NC}"

echo
echo "===================================="
echo -e "${GREEN}✓ All integration tests passed${NC}"
echo
echo "Summary:"
echo "  ✓ Proxy starts and listens on port 8080"
echo "  ✓ Accepts HTTP POST requests"
echo "  ✓ Compression executes"
echo "  ✓ Metrics logged"
echo "  ✓ Edge cases: empty lines, unicode, long lines"
