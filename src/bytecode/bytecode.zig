/// Unified Bytecode Module for eval()/exec()
///
/// Provides:
/// - OpCode definitions (all Python operations)
/// - Program structure (instructions + constants + source map)
/// - VM execution (stack-based interpreter)
/// - Comptime target selection (native, browser WASM, WasmEdge)
/// - Browser WASM Web Worker spawning
/// - WasmEdge WASI socket communication
///
/// Dead code elimination:
/// - Only included in binary if eval()/exec() are called
/// - Zig's comptime + unused code elimination handles this
const builtin = @import("builtin");

pub const opcode = @import("opcode.zig");
pub const vm = @import("vm.zig");
pub const compiler = @import("compiler.zig");
pub const wasm_worker = @import("wasm_worker.zig");
pub const wasi_socket = @import("wasi_socket.zig");

pub const OpCode = opcode.OpCode;
pub const Instruction = opcode.Instruction;
pub const Value = opcode.Value;
pub const Program = opcode.Program;
pub const SourceLoc = opcode.SourceLoc;

pub const Compiler = compiler.Compiler;
pub const VM = vm.VM;
pub const VMError = vm.VMError;
pub const StackValue = vm.StackValue;

pub const serialize = opcode.serialize;
pub const deserialize = opcode.deserialize;
pub const compile = compiler.compile;

/// Execute bytecode with automatic target selection
/// - Native: Direct VM execution
/// - Browser WASM: Web Worker spawning for isolation
/// - WasmEdge WASI: Socket communication for subprocess-like execution
pub fn execute(allocator: std.mem.Allocator, program: *const Program) vm.VMError!vm.StackValue {
    switch (target) {
        .native => {
            // Native: use VM directly
            var executor = VM.init(allocator);
            defer executor.deinit();
            return executor.execute(program);
        },
        .wasm_browser => {
            // Browser: use Web Worker for isolation if needed
            return wasm_worker.executeBrowser(allocator, program);
        },
        .wasm_edge => {
            // WasmEdge: use WASI sockets for subprocess-like execution
            return wasi_socket.executeWasiEdge(allocator, program);
        },
    }
}

const std = @import("std");

/// Target detection at comptime
pub const Target = enum {
    native,
    wasm_browser,
    wasm_edge,
};

/// Detect target at comptime
pub const target: Target = blk: {
    if (builtin.target.isWasm()) {
        // Check for WASI (WasmEdge has WASI support)
        if (builtin.os.tag == .wasi) {
            break :blk .wasm_edge;
        }
        break :blk .wasm_browser;
    }
    break :blk .native;
};
