# metal0 WasmEdge Examples

Run Python compiled to WASM on WasmEdge (WASI runtime).

## Quick Start

```bash
# Install WasmEdge
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash

# Compile to WASM (WASI target)
cd examples/wasmedge
../../zig-out/bin/metal0 build --target wasm-edge hello.py

# Run with WasmEdge
wasmedge hello.wasm
```

## Files

- `hello.py` - Simple hello world example with print output

## WasmEdge vs Browser WASM

| Feature | Browser (`wasm-browser`) | WasmEdge (`wasm-edge`) |
|---------|--------------------------|------------------------|
| Target | `wasm32-freestanding` | `wasm32-wasi` |
| I/O | No (pure compute) | Yes (`print`, file I/O) |
| Use case | Web apps, compute | Server, CLI, edge |
| Runtime | Browser | WasmEdge, Wasmtime |

## Eval Server

For dynamic code execution, see the eval server:

```bash
# Start eval server with WasmEdge backend
metal0 server --socket /tmp/metal0.sock --vm metal0_vm.wasm

# Client can send Python code for execution
```
