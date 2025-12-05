# WasmEdge Zig Bindings

Zig bindings for [WasmEdge](https://wasmedge.org/) runtime, integrated into metal0 for eval()/exec() support.

## Installation

### macOS (Homebrew)
```bash
brew install wasmedge
```

### Linux (apt)
```bash
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash
source ~/.wasmedge/env
```

### From Source
```bash
git clone https://github.com/WasmEdge/WasmEdge.git
cd WasmEdge
cmake -Bbuild -GNinja -DCMAKE_BUILD_TYPE=Release
cmake --build build
cmake --install build --prefix ~/.local
export WASMEDGE_DIR=~/.local
```

## Building metal0 with WasmEdge

Set `WASMEDGE_DIR` when building:
```bash
WASMEDGE_DIR=~/.wasmedge zig build
```

## Updating WasmEdge

This package uses system-installed WasmEdge via `WASMEDGE_DIR`.

To update:
```bash
# Homebrew
brew upgrade wasmedge

# Installer script
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash -s -- -v 0.14.1

# From source - pull latest and rebuild
cd WasmEdge && git pull && cmake --build build && cmake --install build
```

## Usage

The wasmedge module is available via the unified metal0 module (mirrors Python's `from metal0 import wasmedge`):

```zig
const metal0 = @import("metal0");
const wasmedge = metal0.wasmedge;

pub fn main() !void {
    // Create VM with WASI support
    var config = try wasmedge.Config.create();
    defer config.destroy();
    config.enableWASI();

    var vm = try wasmedge.VM.createWithConfig(&config);
    defer vm.destroy();

    // Run WASM function
    var results: [1]wasmedge.Value = undefined;
    try vm.runFromFile(
        "module.wasm",
        "add",
        &.{ wasmedge.Value.fromI32(1), wasmedge.Value.fromI32(2) },
        &results,
    );

    std.debug.print("Result: {}\n", .{results[0].getI32()});
}
```

## Server

The server is integrated as a metal0 subcommand:

```bash
# Start server
metal0 server --socket /tmp/metal0-server.sock --vm-module metal0_vm.wasm

# Show help
metal0 server --help
```

The server executes Python bytecode in isolated WASM instances for security.
