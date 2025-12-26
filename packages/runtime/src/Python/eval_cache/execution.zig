/// Comptime target selection - WASM vs Native bytecode execution
const std = @import("std");
const builtin = @import("builtin");
const bytecode = @import("../compile.zig");
const PyObject = @import("../../runtime.zig").PyObject;

/// Comptime target selection - WASM vs Native
pub fn executeTarget(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    if (builtin.cpu.arch.isWasm()) {
        // WASM: Use bytecode VM (no JIT possible)
        return executeWasm(allocator, program);
    } else {
        // Native: Use bytecode VM for now
        // Future: Could JIT to machine code here
        return executeNative(allocator, program);
    }
}

/// WASM bytecode execution
fn executeWasm(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    var vm = bytecode.VM.init(allocator);
    defer vm.deinit();
    return vm.execute(program);
}

/// Native bytecode execution (same as WASM for now)
fn executeNative(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    var vm = bytecode.VM.init(allocator);
    defer vm.deinit();
    return vm.execute(program);
}

/// Execute with globals/locals scope
/// TODO: Wire globals/locals into VM frame when VM supports it
pub fn executeWithScope(
    allocator: std.mem.Allocator,
    program: *const bytecode.BytecodeProgram,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
) !*PyObject {
    // For now, ignore globals/locals and execute normally
    // TODO: When VM supports scope, pass these to the frame
    _ = globals;
    _ = locals;
    return executeTarget(allocator, program);
}
