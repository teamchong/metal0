# Unified Bytecode VM for eval()/exec()

## Current State (Broken)

```
eval("x + 1") → AST Executor (minimal, incomplete)
exec("class Foo: pass") → Subprocess fallback (slow, not WASM compatible)
```

**Problems:**
1. AST executor only handles: constants, binops, calls
2. No variables, loops, classes, imports, comprehensions
3. Subprocess fallback doesn't work in WASM
4. Duplicated parsing logic (doesn't reuse metal0's parser)

## Architecture: Unified VM

```
                    ┌─────────────────────────────────────┐
                    │         eval()/exec() entry         │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │    metal0 Parser + Type Inferrer    │
                    │    (REUSE existing src/parser/)     │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │         Bytecode Compiler           │
                    │    (New: src/bytecode/compiler.zig) │
                    └─────────────────┬───────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐   ┌─────────▼─────────┐   ┌─────────▼─────────┐
    │   Native Binary   │   │   Browser WASM    │   │   WasmEdge WASI   │
    │   (stack-based)   │   │   (Web Worker)    │   │   (WASI sockets)  │
    └───────────────────┘   └───────────────────┘   └───────────────────┘
```

## Comptime Target Selection

```zig
const Target = enum { native, wasm_browser, wasm_edge };

pub const target: Target = comptime blk: {
    if (builtin.target.isWasm()) {
        if (@hasDecl(std.os, "wasi")) {
            break :blk .wasm_edge;  // WasmEdge with WASI
        }
        break :blk .wasm_browser;   // Browser (no WASI)
    }
    break :blk .native;
};

pub fn eval(source: []const u8) !*PyObject {
    const bytecode = try compile(source);

    switch (target) {
        .native => return executeNative(bytecode),
        .wasm_browser => return executeBrowser(bytecode),
        .wasm_edge => return executeWasiEdge(bytecode),
    }
}
```

## Bytecode Format (Unified)

```zig
pub const OpCode = enum(u8) {
    // Stack operations
    LOAD_CONST,      // Push constant onto stack
    LOAD_NAME,       // Load variable by name
    STORE_NAME,      // Store TOS to variable

    // Arithmetic
    BINARY_ADD,
    BINARY_SUB,
    BINARY_MUL,
    BINARY_DIV,
    BINARY_MOD,
    BINARY_POW,

    // Comparison
    COMPARE_EQ,
    COMPARE_NE,
    COMPARE_LT,
    COMPARE_GT,

    // Control flow
    JUMP,
    JUMP_IF_FALSE,
    JUMP_IF_TRUE,

    // Functions
    CALL_FUNCTION,
    RETURN_VALUE,
    MAKE_FUNCTION,

    // Classes
    BUILD_CLASS,
    LOAD_ATTR,
    STORE_ATTR,

    // Collections
    BUILD_LIST,
    BUILD_DICT,
    BUILD_SET,
    BUILD_TUPLE,
    LIST_APPEND,
    DICT_SET_ITEM,

    // Comprehensions
    GET_ITER,
    FOR_ITER,

    // Imports
    IMPORT_NAME,
    IMPORT_FROM,

    // Exception handling
    SETUP_EXCEPT,
    POP_EXCEPT,
    RAISE,
};

pub const Instruction = packed struct {
    opcode: OpCode,
    arg: u24,  // 24-bit argument (constant index, jump offset, etc.)
};

pub const Program = struct {
    instructions: []const Instruction,
    constants: []const Value,
    names: []const []const u8,
    source_map: []const SourceLoc,  // For error messages
};
```

## Browser WASM: Viral Spawning

For browser targets, eval()/exec() can spawn new WASM instances:

```zig
// Browser: use Web Workers for parallel eval
pub fn executeBrowser(bytecode: Program) !*PyObject {
    if (bytecode.needsIsolation()) {
        // Spawn new Web Worker with same WASM module
        return spawnWorker(bytecode);
    }
    return vm.execute(bytecode);
}

extern "js" fn spawnWorker(bytecode: [*]const u8, len: usize) *PyObject;
```

**JavaScript side:**
```javascript
// Viral spawning - same WASM, new Worker
function spawnWorker(bytecode) {
    const worker = new Worker(new URL(import.meta.url));
    worker.postMessage({
        wasm: wasmModule,  // Reuse compiled module
        bytecode: bytecode
    });
    return new Promise(resolve => {
        worker.onmessage = e => resolve(e.data);
    });
}
```

## WasmEdge WASI: Socket-Based

For WasmEdge (server-side WASM), use WASI sockets:

```zig
pub fn executeWasiEdge(bytecode: Program) !*PyObject {
    if (bytecode.needsIsolation()) {
        // Use WASI sockets to spawn subprocess-like execution
        const sock = try std.os.socket(std.os.AF.UNIX, std.os.SOCK.STREAM, 0);
        defer std.os.close(sock);

        // Send bytecode to metal0 server process
        try std.os.write(sock, std.mem.asBytes(&bytecode));

        // Wait for result
        var result: [8]u8 = undefined;
        _ = try std.os.read(sock, &result);
        return deserializeResult(result);
    }
    return vm.execute(bytecode);
}
```

**Alternative: WasmEdge Plugin**
```rust
// Rust plugin for WasmEdge that provides eval() capability
#[wasmedge_plugin_sdk::host_function]
fn metal0_eval(caller: &mut Caller, ptr: i32, len: i32) -> i32 {
    let bytecode = caller.memory_read(ptr, len);
    let result = metal0_vm::execute(bytecode);
    caller.memory_write(result)
}
```

## Dead Code Elimination

Zig's comptime + unused code elimination ensures the VM is only included when used:

```zig
// Only compile VM if eval/exec are actually called
pub const VM = struct {
    // Full implementation
};

// If user never calls eval(), this entire module is dead-code eliminated
pub fn eval(source: []const u8) !*PyObject {
    var vm = VM.init(allocator);
    defer vm.deinit();
    return vm.execute(try compile(source));
}
```

**Verification:**
```bash
# Check binary size without eval
./zig-out/bin/metal0 hello.py --force
ls -la build/*/hello*  # ~50KB

# Check binary size with eval
./zig-out/bin/metal0 eval_test.py --force
ls -la build/*/eval_test*  # ~150KB (VM included)
```

## Reusing metal0 Parser

Instead of separate AST types, embed the compiler's parser:

```zig
// packages/runtime/src/eval.zig
const parser = @import("parser");  // From src/parser/
const type_inferrer = @import("analysis").TypeInferrer;

pub fn compile(source: []const u8) !Program {
    // Reuse metal0's parser
    var lexer = parser.Lexer.init(source);
    var p = parser.Parser.init(&lexer, allocator);
    const ast = try p.parse();

    // Reuse metal0's type inference
    var inferrer = type_inferrer.init(allocator);
    try inferrer.inferTypes(ast);

    // Generate bytecode (new)
    var compiler = BytecodeCompiler.init(allocator);
    return compiler.compile(ast);
}
```

## Implementation Order

1. **Phase 1: Unified Bytecode Format**
   - Define OpCode enum with all Python operations
   - Create Program struct with constants pool
   - Source maps for error messages

2. **Phase 2: Reuse Parser**
   - Import src/parser into runtime package
   - Wire up type inference
   - Full Python syntax support

3. **Phase 3: Native VM**
   - Stack-based interpreter
   - Full control flow (if/for/while/try)
   - Function calls and closures

4. **Phase 4: WASM Targets**
   - Browser: Web Worker spawning
   - WasmEdge: WASI socket communication
   - Comptime target selection

5. **Phase 5: Dead Code Elimination**
   - Verify VM only included when eval() used
   - Benchmark binary size impact

## Files to Create/Modify

| File | Action |
|------|--------|
| `src/bytecode/opcode.zig` | NEW - OpCode definitions |
| `src/bytecode/compiler.zig` | NEW - AST to bytecode |
| `src/bytecode/vm.zig` | NEW - Unified VM |
| `packages/runtime/src/eval.zig` | MODIFY - Use new VM |
| `packages/runtime/src/exec.zig` | MODIFY - Use new VM |
| `build.zig` | MODIFY - Link parser to runtime |
