/// _opcode_metadata/operations.zig - Comparison and binary operation definitions
/// Defines the operation codes and naming for comparison (==, <, etc) and
/// binary operations (+, *, //, etc) used by Python bytecode.

const std = @import("std");

/// Comparison operation codes (for COMPARE_OP)
pub const CompareOp = enum(u8) {
    lt = 0,
    le = 1,
    eq = 2,
    ne = 3,
    gt = 4,
    ge = 5,

    pub fn getName(self: CompareOp) []const u8 {
        return switch (self) {
            .lt => "<",
            .le => "<=",
            .eq => "==",
            .ne => "!=",
            .gt => ">",
            .ge => ">=",
        };
    }
};

/// Binary operation codes (for BINARY_OP)
pub const BinaryOp = enum(u8) {
    add = 0,
    and_ = 1,
    floor_divide = 2,
    lshift = 3,
    matmul = 4,
    multiply = 5,
    remainder = 6,
    or_ = 7,
    power = 8,
    rshift = 9,
    subtract = 10,
    true_divide = 11,
    xor = 12,
    inplace_add = 13,
    // ... more inplace operations

    pub fn getName(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .and_ => "&",
            .floor_divide => "//",
            .lshift => "<<",
            .matmul => "@",
            .multiply => "*",
            .remainder => "%",
            .or_ => "|",
            .power => "**",
            .rshift => ">>",
            .subtract => "-",
            .true_divide => "/",
            .xor => "^",
            .inplace_add => "+=",
        };
    }
};

test "compare op lt" {
    try std.testing.expectEqualStrings("<", CompareOp.lt.getName());
}

test "compare op eq" {
    try std.testing.expectEqualStrings("==", CompareOp.eq.getName());
}

test "compare op ne" {
    try std.testing.expectEqualStrings("!=", CompareOp.ne.getName());
}

test "binary op add" {
    try std.testing.expectEqualStrings("+", BinaryOp.add.getName());
}

test "binary op multiply" {
    try std.testing.expectEqualStrings("*", BinaryOp.multiply.getName());
}

test "binary op floor divide" {
    try std.testing.expectEqualStrings("//", BinaryOp.floor_divide.getName());
}
