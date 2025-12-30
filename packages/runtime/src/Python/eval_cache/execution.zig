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
pub fn executeWithScope(
    allocator: std.mem.Allocator,
    program: *const bytecode.BytecodeProgram,
    globals: ?*PyObject,
    locals: ?*PyObject,
) !*PyObject {
    // Initialize VM with scope dicts
    var vm = bytecode.VM.initWithScope(allocator, globals, locals);
    defer vm.deinit();
    return vm.execute(program);
}

/// Execute with globals/locals scope (anyopaque version for backward compatibility)
pub fn executeWithScopeAnyopaque(
    allocator: std.mem.Allocator,
    program: *const bytecode.BytecodeProgram,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
) !*PyObject {
    // Cast anyopaque to PyObject and execute with scope
    const globals_obj: ?*PyObject = if (globals) |g| @ptrCast(@alignCast(g)) else null;
    const locals_obj: ?*PyObject = if (locals) |l| @ptrCast(@alignCast(l)) else null;
    return executeWithScope(allocator, program, globals_obj, locals_obj);
}

/// Execute with full scope: globals, locals, and builtins
pub fn executeWithFullScope(
    allocator: std.mem.Allocator,
    program: *const bytecode.BytecodeProgram,
    globals: ?*PyObject,
    locals: ?*PyObject,
    builtins: ?*PyObject,
) !*PyObject {
    // Initialize VM with full scope dicts
    var vm = bytecode.VM.initWithFullScope(allocator, globals, locals, builtins);
    defer vm.deinit();
    return vm.execute(program);
}
