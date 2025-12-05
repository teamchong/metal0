# WasmEdge Zig Bindings

Zig bindings for [WasmEdge](https://wasmedge.org/) runtime.

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

## Updating WasmEdge

This package uses system-installed WasmEdge via pkg-config or `WASMEDGE_DIR`.

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

```zig
const wasmedge = @import("wasmedge");

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
        &.{ wasmedge.Value.i32(1), wasmedge.Value.i32(2) },
        &results,
    );

    std.debug.print("Result: {}\n", .{results[0].getI32()});
}
```

## For metal0 eval() Support

The eval server uses WasmEdge to execute bytecode in isolated WASM instances:

```zig
const wasmedge = @import("wasmedge");
const bytecode = @import("bytecode");

pub fn executeInWasm(program: *const bytecode.Program) !bytecode.StackValue {
    var vm = try wasmedge.VM.create();
    defer vm.destroy();

    // Load the bytecode VM WASM module
    try vm.loadFromFile("metal0_vm.wasm");
    try vm.validate();
    try vm.instantiate();

    // Serialize bytecode and pass to WASM
    const bc_bytes = try bytecode.serialize(program);
    defer allocator.free(bc_bytes);

    // Execute
    var results: [1]wasmedge.Value = undefined;
    try vm.execute("execute_bytecode", &.{
        wasmedge.Value.i32(@intCast(@intFromPtr(bc_bytes.ptr))),
        wasmedge.Value.i32(@intCast(bc_bytes.len)),
    }, &results);

    return bytecode.deserializeResult(results[0].getI64());
}
```
