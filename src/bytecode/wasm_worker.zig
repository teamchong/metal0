/// Browser WASM Web Worker Spawning for eval()/exec()
///
/// Enables parallel eval() execution in browser WASM targets.
/// Uses Web Workers with viral WASM module sharing.
///
/// Architecture:
/// 1. Main thread compiles bytecode
/// 2. Spawns Web Worker with same WASM module
/// 3. Worker executes bytecode in isolation
/// 4. Returns result via postMessage
const std = @import("std");
const builtin = @import("builtin");
const opcode = @import("opcode.zig");
const vm = @import("vm.zig");

const Program = opcode.Program;
const VM = vm.VM;
const StackValue = vm.StackValue;
const VMError = vm.VMError;

/// Check if running in browser WASM context
pub const is_browser_wasm = builtin.cpu.arch.isWasm() and
    builtin.os.tag != .wasi;

/// JavaScript extern declarations for browser WASM
const js = if (is_browser_wasm) struct {
    /// Spawn a Web Worker to execute bytecode
    /// Returns a promise handle that resolves to the result
    extern "js" fn spawnEvalWorker(
        bytecode_ptr: [*]const u8,
        bytecode_len: usize,
        constants_ptr: [*]const u8,
        constants_len: usize,
    ) i32;

    /// Wait for worker result (blocking - use with caution)
    extern "js" fn waitWorkerResult(handle: i32) i64;

    /// Check if worker is done (non-blocking)
    extern "js" fn isWorkerDone(handle: i32) bool;

    /// Get worker result (only valid after isWorkerDone returns true)
    extern "js" fn getWorkerResult(handle: i32) i64;

    /// Cancel worker execution
    extern "js" fn cancelWorker(handle: i32) void;

    /// Log to browser console (for debugging)
    extern "js" fn consoleLog(ptr: [*]const u8, len: usize) void;
} else struct {
    // Stub implementations for non-browser targets
    fn spawnEvalWorker(_: [*]const u8, _: usize, _: [*]const u8, _: usize) i32 {
        return -1;
    }
    fn waitWorkerResult(_: i32) i64 {
        return 0;
    }
    fn isWorkerDone(_: i32) bool {
        return true;
    }
    fn getWorkerResult(_: i32) i64 {
        return 0;
    }
    fn cancelWorker(_: i32) void {}
    fn consoleLog(_: [*]const u8, _: usize) void {}
};

/// Worker handle for async eval
pub const WorkerHandle = struct {
    id: i32,
    program: *const Program,
    allocator: std.mem.Allocator,

    /// Check if worker has completed
    pub fn isDone(self: *const WorkerHandle) bool {
        return js.isWorkerDone(self.id);
    }

    /// Get result (blocks if not done)
    pub fn getResult(self: *const WorkerHandle) VMError!StackValue {
        if (!is_browser_wasm) {
            return error.NotImplemented;
        }

        // Wait for result
        const result_int = js.waitWorkerResult(self.id);

        // Convert result back to StackValue
        return intToStackValue(result_int);
    }

    /// Get result if ready (non-blocking)
    pub fn tryGetResult(self: *const WorkerHandle) ?StackValue {
        if (!self.isDone()) {
            return null;
        }
        const result_int = js.getWorkerResult(self.id);
        return intToStackValue(result_int);
    }

    /// Cancel the worker
    pub fn cancel(self: *WorkerHandle) void {
        js.cancelWorker(self.id);
    }

    fn intToStackValue(result: i64) StackValue {
        // Simple encoding: int values directly
        // TODO: extend for other types
        return .{ .int = result };
    }
};

/// Spawn a Web Worker to execute bytecode
/// Returns a handle for async result retrieval
pub fn spawnWorker(
    allocator: std.mem.Allocator,
    program: *const Program,
) VMError!WorkerHandle {
    if (!is_browser_wasm) {
        return error.NotImplemented;
    }

    // Serialize bytecode for transfer
    const bytecode_data = opcode.serialize(allocator, program) catch {
        return error.OutOfMemory;
    };
    defer allocator.free(bytecode_data);

    // Spawn worker with serialized bytecode
    const handle_id = js.spawnEvalWorker(
        bytecode_data.ptr,
        bytecode_data.len,
        @as([*]const u8, &.{}), // constants (TODO: serialize)
        0,
    );

    if (handle_id < 0) {
        return error.RuntimeError;
    }

    return WorkerHandle{
        .id = handle_id,
        .program = program,
        .allocator = allocator,
    };
}

/// Execute bytecode in browser WASM context
/// Uses Web Worker if needsIsolation, otherwise runs in main thread
pub fn executeBrowser(
    allocator: std.mem.Allocator,
    program: *const Program,
) VMError!StackValue {
    if (!is_browser_wasm) {
        return error.NotImplemented;
    }

    // For simple expressions, run in main thread
    if (!needsIsolation(program)) {
        var executor = VM.init(allocator);
        defer executor.deinit();
        return executor.execute(program);
    }

    // For complex code, spawn worker
    var handle = try spawnWorker(allocator, program);
    return handle.getResult();
}

/// Determine if bytecode needs isolation (Web Worker)
/// Returns true for:
/// - Long-running loops
/// - Import statements
/// - Class definitions
/// - Potentially blocking operations
fn needsIsolation(program: *const Program) bool {
    // Check for operations that benefit from isolation
    for (program.instructions) |inst| {
        switch (inst.opcode) {
            // Loops can be long-running
            .FOR_ITER, .SETUP_LOOP => return true,
            // Imports may have side effects
            .IMPORT_NAME, .IMPORT_FROM => return true,
            // Class definitions are complex
            .BUILD_CLASS => return true,
            // Exception handling is complex
            .SETUP_EXCEPT, .RAISE_VARARGS => return true,
            else => {},
        }
    }
    return false;
}

/// Worker entry point - called by JavaScript worker bootstrap
/// Exported so JavaScript can call it
export fn worker_execute_bytecode(
    bytecode_ptr: [*]const u8,
    bytecode_len: usize,
) i64 {
    // Parse bytecode
    const allocator = std.heap.wasm_allocator;
    const bytecode_slice = bytecode_ptr[0..bytecode_len];

    const program = opcode.deserialize(allocator, bytecode_slice) catch {
        return -1; // Error code
    };

    // Execute
    var executor = VM.init(allocator);
    defer executor.deinit();

    const result = executor.execute(&program) catch {
        return -2; // Execution error
    };

    // Return result as int (simple encoding)
    return switch (result) {
        .int => |v| v,
        .bool => |v| if (v) 1 else 0,
        else => 0,
    };
}

/// JavaScript runtime code for Web Worker spawning
/// This is embedded in the WASM output and used by the JS loader
pub const js_worker_runtime =
    \\// metal0 Web Worker runtime for eval()
    \\const workers = new Map();
    \\let nextWorkerId = 0;
    \\
    \\// Spawn a Web Worker for bytecode execution
    \\function spawnEvalWorker(bytecodePtr, bytecodeLen, constantsPtr, constantsLen) {
    \\    const id = nextWorkerId++;
    \\    const bytecode = new Uint8Array(memory.buffer, bytecodePtr, bytecodeLen);
    \\
    \\    // Create worker with same WASM module (viral spawning)
    \\    const workerBlob = new Blob([`
    \\        let wasmModule, wasmInstance;
    \\
    \\        self.onmessage = async (e) => {
    \\            const { module, bytecode } = e.data;
    \\
    \\            // Instantiate same WASM module
    \\            wasmInstance = await WebAssembly.instantiate(module, {
    \\                env: { memory: new WebAssembly.Memory({ initial: 256 }) }
    \\            });
    \\
    \\            // Execute bytecode
    \\            const result = wasmInstance.exports.worker_execute_bytecode(
    \\                bytecode.byteOffset, bytecode.length
    \\            );
    \\
    \\            self.postMessage({ id: ${id}, result });
    \\        };
    \\    `], { type: 'application/javascript' });
    \\
    \\    const worker = new Worker(URL.createObjectURL(workerBlob));
    \\    workers.set(id, { worker, done: false, result: null });
    \\
    \\    worker.onmessage = (e) => {
    \\        const state = workers.get(e.data.id);
    \\        if (state) {
    \\            state.done = true;
    \\            state.result = e.data.result;
    \\        }
    \\    };
    \\
    \\    // Send bytecode and WASM module to worker
    \\    worker.postMessage({
    \\        module: wasmModule,
    \\        bytecode: bytecode.slice()
    \\    });
    \\
    \\    return id;
    \\}
    \\
    \\function isWorkerDone(id) {
    \\    const state = workers.get(id);
    \\    return state ? state.done : true;
    \\}
    \\
    \\function getWorkerResult(id) {
    \\    const state = workers.get(id);
    \\    if (state && state.done) {
    \\        workers.delete(id);
    \\        return state.result;
    \\    }
    \\    return 0;
    \\}
    \\
    \\function waitWorkerResult(id) {
    \\    // Blocking wait - not ideal for browser, but needed for sync API
    \\    while (!isWorkerDone(id)) {
    \\        // Busy wait (browsers don't have real blocking)
    \\    }
    \\    return getWorkerResult(id);
    \\}
    \\
    \\function cancelWorker(id) {
    \\    const state = workers.get(id);
    \\    if (state) {
    \\        state.worker.terminate();
    \\        workers.delete(id);
    \\    }
    \\}
;

test "browser wasm detection" {
    // On native, is_browser_wasm should be false
    if (!builtin.cpu.arch.isWasm()) {
        try std.testing.expect(!is_browser_wasm);
    }
}

test "needs isolation detection" {
    // Create a simple program with no isolation-requiring ops
    const simple_program = Program{
        .instructions = &[_]opcode.Instruction{
            opcode.Instruction.init(.LOAD_CONST, 0),
            opcode.Instruction.init(.RETURN_VALUE, 0),
        },
        .constants = &[_]opcode.Value{.{ .int = 42 }},
        .varnames = &.{},
        .names = &.{},
        .cellvars = &.{},
        .freevars = &.{},
        .source_map = &.{},
        .filename = "<test>",
        .name = "<expr>",
        .firstlineno = 1,
        .argcount = 0,
        .posonlyargcount = 0,
        .kwonlyargcount = 0,
        .stacksize = 8,
        .flags = .{},
    };

    try std.testing.expect(!needsIsolation(&simple_program));

    // Create a program with FOR_ITER (requires isolation)
    const loop_program = Program{
        .instructions = &[_]opcode.Instruction{
            opcode.Instruction.init(.FOR_ITER, 0),
            opcode.Instruction.init(.RETURN_VALUE, 0),
        },
        .constants = &.{},
        .varnames = &.{},
        .names = &.{},
        .cellvars = &.{},
        .freevars = &.{},
        .source_map = &.{},
        .filename = "<test>",
        .name = "<loop>",
        .firstlineno = 1,
        .argcount = 0,
        .posonlyargcount = 0,
        .kwonlyargcount = 0,
        .stacksize = 8,
        .flags = .{},
    };

    try std.testing.expect(needsIsolation(&loop_program));
}
