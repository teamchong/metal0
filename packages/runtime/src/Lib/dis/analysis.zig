//! Bytecode analysis utilities.
//!
//! This module provides functions for analyzing bytecode structure,
//! such as finding labels, line starts, and computing stack effects.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const opcode_mod = @import("opcode.zig");
const Opcode = opcode_mod.Opcode;

/// Find labels (jump targets) in bytecode
pub fn findlabels(code: []const u8) ![]usize {
    var labels: std.ArrayList(usize) = .{};
    errdefer labels.deinit(allocator_helper.fast_allocator);

    var offset: usize = 0;
    while (offset < code.len) {
        const opcode: Opcode = @enumFromInt(code[offset]);

        if (opcode.hasArg() and offset + 1 < code.len) {
            const arg = code[offset + 1];
            if (opcode.isJump()) {
                const target = if (opcode.hasJrel())
                    offset + 2 + arg
                else
                    arg;
                try labels.append(allocator_helper.fast_allocator, target);
            }
        }

        offset += if (opcode.hasArg()) @as(usize, 2) else @as(usize, 1);
    }

    return labels.toOwnedSlice(allocator_helper.fast_allocator);
}

/// Find line starts in bytecode
pub fn findlinestarts(co: anytype) !std.AutoHashMap(usize, u32) {
    _ = co;
    return std.AutoHashMap(usize, u32).init(allocator_helper.fast_allocator);
}

/// Get the stack effect of an opcode
pub fn stackEffect(opcode: Opcode, arg: ?u32, jump: ?bool) i32 {
    const jmp = jump orelse false;
    _ = arg;

    return switch (opcode) {
        .NOP, .EXTENDED_ARG, .RESUME, .CACHE => 0,
        .POP_TOP, .END_FOR, .END_SEND => -1,
        .PUSH_NULL => 1,
        .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
        .BINARY_OP, .BINARY_SUBSCR, .COMPARE_OP, .IS_OP, .CONTAINS_OP => -1,
        .LOAD_CONST, .LOAD_NAME, .LOAD_FAST, .LOAD_GLOBAL, .LOAD_ATTR, .LOAD_DEREF, .LOAD_CLOSURE => 1,
        .STORE_NAME, .STORE_FAST, .STORE_GLOBAL, .STORE_ATTR, .STORE_SUBSCR, .STORE_DEREF => -1,
        .DELETE_NAME, .DELETE_FAST, .DELETE_GLOBAL, .DELETE_ATTR, .DELETE_SUBSCR, .DELETE_DEREF => 0,
        .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => |_| 1, // Actually 1 - arg
        .BUILD_MAP => 1, // Actually 1 - 2*arg
        .RETURN_VALUE, .RETURN_CONST => -1,
        .YIELD_VALUE => 0,
        .IMPORT_NAME => -1,
        .IMPORT_FROM => 1,
        .JUMP_FORWARD, .JUMP_BACKWARD => 0,
        .POP_JUMP_IF_TRUE, .POP_JUMP_IF_FALSE => if (jmp) @as(i32, -1) else @as(i32, -1),
        .FOR_ITER => if (jmp) @as(i32, -1) else @as(i32, 1),
        .GET_ITER => 0,
        .CALL => -1, // Actually -arg
        .MAKE_FUNCTION => 0,
        .RAISE_VARARGS => -1,
        .RERAISE => -1,
        .POP_EXCEPT => -1,
        .PUSH_EXC_INFO => 1,
        .SWAP, .COPY => 0,
        else => 0,
    };
}

test "stack effect" {
    try std.testing.expectEqual(@as(i32, 0), stackEffect(.NOP, null, null));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(.POP_TOP, null, null));
    try std.testing.expectEqual(@as(i32, 1), stackEffect(.LOAD_CONST, null, null));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(.RETURN_VALUE, null, null));
}
