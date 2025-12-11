/// init - Module Initialization and Tests
/// Mirrors cpython/Python/optimizer_bytecodes.c
///
/// Handles module initialization and test cases for optimizer bytecodes.

const std = @import("std");
const bytecode_defs = @import("bytecode_defs.zig");
const translation = @import("translation.zig");
const properties = @import("properties.zig");

pub const MicroOp = bytecode_defs.MicroOp;
pub const Bytecode = bytecode_defs.Bytecode;
pub const TypeId = bytecode_defs.TypeId;

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the optimizer bytecodes module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "bytecode translation" {
    const uops = translation.translateBytecode(.LOAD_FAST);
    try std.testing.expectEqual(@as(usize, 1), uops.len);
    try std.testing.expectEqual(MicroOp._LOAD_FAST, uops[0].op);
    try std.testing.expectEqual(translation.ArgSource.bytecode_arg, uops[0].arg_source);
}

test "specialization" {
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD_INT, translation.specialize(._BINARY_OP_ADD, .int_type));
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD_FLOAT, translation.specialize(._BINARY_OP_ADD, .float_type));
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD_STR, translation.specialize(._BINARY_OP_ADD, .str_type));
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD, translation.specialize(._BINARY_OP_ADD, .unknown));
}

test "guard for type" {
    try std.testing.expectEqual(MicroOp._GUARD_TYPE_INT, translation.guardForType(.int_type).?);
    try std.testing.expectEqual(MicroOp._GUARD_TYPE_LIST, translation.guardForType(.list_type).?);
    try std.testing.expect(translation.guardForType(.unknown) == null);
}

test "micro-op properties" {
    const load_props = properties.getMicroOpProps(._LOAD_FAST);
    try std.testing.expectEqual(@as(i8, 1), load_props.stack_effect);
    try std.testing.expect(load_props.has_arg);
    try std.testing.expect(!load_props.is_guard);

    const guard_props = properties.getMicroOpProps(._GUARD_TYPE_INT);
    try std.testing.expectEqual(@as(i8, 0), guard_props.stack_effect);
    try std.testing.expect(guard_props.is_guard);
    try std.testing.expect(guard_props.can_deopt);
}
