/// Unified Bytecode Module for eval()/exec()
///
/// Provides:
/// - OpCode definitions (all Python operations)
/// - Program structure (instructions + constants + source map)
/// - VM execution (stack-based interpreter)
/// - Comptime target selection (native, browser WASM, WasmEdge)
///
/// Dead code elimination:
/// - Only included in binary if eval()/exec() are called
/// - Zig's comptime + unused code elimination handles this
pub const opcode = @import("opcode.zig");
pub const compiler = @import("compiler.zig");

pub const OpCode = opcode.OpCode;
pub const Instruction = opcode.Instruction;
pub const Value = opcode.Value;
pub const Program = opcode.Program;
pub const SourceLoc = opcode.SourceLoc;

pub const Compiler = compiler.Compiler;

pub const serialize = opcode.serialize;
pub const deserialize = opcode.deserialize;

/// Target detection at comptime
pub const Target = enum {
    native,
    wasm_browser,
    wasm_edge,
};

const builtin = @import("builtin");

/// Detect target at comptime
pub const target: Target = comptime blk: {
    if (builtin.target.isWasm()) {
        // Check for WASI (WasmEdge has WASI support)
        if (builtin.os.tag == .wasi) {
            break :blk .wasm_edge;
        }
        break :blk .wasm_browser;
    }
    break :blk .native;
};

/// VM will be implemented in vm.zig
/// For now, export placeholder
pub const VM = struct {
    // TODO: implement
};

test "target detection" {
    const std = @import("std");
    // On native build, should be native
    if (!builtin.target.isWasm()) {
        try std.testing.expectEqual(Target.native, target);
    }
}
