/// Module Initialization and Tests
/// Module state management and test cases for bytecode operations

const std = @import("std");
const constants = @import("constants.zig");
const metadata = @import("metadata.zig");
const utilities = @import("utilities.zig");

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the bytecodes module
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

test "opcode names" {
    try std.testing.expectEqualStrings("NOP", metadata.opcodeName(constants.NOP));
    try std.testing.expectEqualStrings("LOAD_CONST", metadata.opcodeName(constants.LOAD_CONST));
    try std.testing.expectEqualStrings("RETURN_VALUE", metadata.opcodeName(constants.RETURN_VALUE));
}

test "opcode flags" {
    const load_const = metadata.OPCODE_TABLE[constants.LOAD_CONST];
    try std.testing.expect(load_const.hasArg());
    try std.testing.expect(load_const.hasConst());
    try std.testing.expect(!load_const.isJump());

    const jump_forward = metadata.OPCODE_TABLE[constants.JUMP_FORWARD];
    try std.testing.expect(jump_forward.isJump());
    try std.testing.expect(jump_forward.isRelativeJump());
}

test "stack effects" {
    try std.testing.expectEqual(@as(i32, 1), utilities.stackEffect(constants.LOAD_CONST, 0));
    try std.testing.expectEqual(@as(i32, -1), utilities.stackEffect(constants.RETURN_VALUE, 0));
    try std.testing.expectEqual(@as(i32, -1), utilities.stackEffect(constants.POP_TOP, 0));

    // Variable stack effects
    try std.testing.expectEqual(@as(i32, -2), utilities.stackEffect(constants.BUILD_TUPLE, 3)); // 1 - 3
    try std.testing.expectEqual(@as(i32, -5), utilities.stackEffect(constants.BUILD_MAP, 3)); // 1 - 6
}

test "jump classification" {
    try std.testing.expect(utilities.isUnconditionalJump(constants.JUMP_FORWARD));
    try std.testing.expect(utilities.isUnconditionalJump(constants.JUMP_BACKWARD));
    try std.testing.expect(!utilities.isUnconditionalJump(constants.POP_JUMP_IF_FALSE));

    try std.testing.expect(utilities.isConditionalJump(constants.POP_JUMP_IF_FALSE));
    try std.testing.expect(utilities.isConditionalJump(constants.FOR_ITER));
    try std.testing.expect(!utilities.isConditionalJump(constants.JUMP_FORWARD));
}

test "block terminators" {
    try std.testing.expect(utilities.isBlockTerminator(constants.RETURN_VALUE));
    try std.testing.expect(utilities.isBlockTerminator(constants.RETURN_CONST));
    try std.testing.expect(utilities.isBlockTerminator(constants.RAISE_VARARGS));
    try std.testing.expect(utilities.isBlockTerminator(constants.JUMP_FORWARD));
    try std.testing.expect(!utilities.isBlockTerminator(constants.LOAD_CONST));
}

test "cache entries" {
    try std.testing.expectEqual(@as(u8, 0), metadata.cacheEntries(constants.NOP));
    try std.testing.expectEqual(@as(u8, 1), metadata.cacheEntries(constants.BINARY_OP));
    try std.testing.expectEqual(@as(u8, 4), metadata.cacheEntries(constants.LOAD_GLOBAL));
    try std.testing.expectEqual(@as(u8, 9), metadata.cacheEntries(constants.LOAD_ATTR));
}
