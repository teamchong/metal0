/// Constant Folding
/// Compile-time evaluation of constant expressions

/// Constant value for folding
pub const ConstValue = union(enum) {
    none: void,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,
    bytes_val: []const u8,

    /// Check if value is truthy
    pub fn isTruthy(self: ConstValue) bool {
        return switch (self) {
            .none => false,
            .bool_val => |v| v,
            .int_val => |v| v != 0,
            .float_val => |v| v != 0.0,
            .str_val => |v| v.len > 0,
            .bytes_val => |v| v.len > 0,
        };
    }
};

/// Binary operation for constant folding
pub const BinOp = enum {
    add,
    sub,
    mult,
    div,
    floor_div,
    mod,
    pow,
    lshift,
    rshift,
    bit_or,
    bit_xor,
    bit_and,
};

/// Fold binary operation on constants
pub fn foldBinaryOp(op: BinOp, left: ConstValue, right: ConstValue) ?ConstValue {
    // Both must be numeric
    const left_int = switch (left) {
        .int_val => |v| v,
        else => return null,
    };
    const right_int = switch (right) {
        .int_val => |v| v,
        else => return null,
    };

    return switch (op) {
        .add => .{ .int_val = left_int +| right_int },
        .sub => .{ .int_val = left_int -| right_int },
        .mult => .{ .int_val = left_int *| right_int },
        .floor_div => blk: {
            if (right_int == 0) break :blk null;
            break :blk .{ .int_val = @divFloor(left_int, right_int) };
        },
        .mod => blk: {
            if (right_int == 0) break :blk null;
            break :blk .{ .int_val = @mod(left_int, right_int) };
        },
        .lshift => blk: {
            if (right_int < 0 or right_int > 63) break :blk null;
            break :blk .{ .int_val = left_int << @intCast(right_int) };
        },
        .rshift => blk: {
            if (right_int < 0 or right_int > 63) break :blk null;
            break :blk .{ .int_val = left_int >> @intCast(right_int) };
        },
        .bit_or => .{ .int_val = left_int | right_int },
        .bit_xor => .{ .int_val = left_int ^ right_int },
        .bit_and => .{ .int_val = left_int & right_int },
        else => null,
    };
}

/// Unary operation for constant folding
pub const UnaryOp = enum {
    invert,
    not_op,
    uadd,
    usub,
};

/// Fold unary operation on constant
pub fn foldUnaryOp(op: UnaryOp, operand: ConstValue) ?ConstValue {
    return switch (op) {
        .not_op => .{ .bool_val = !operand.isTruthy() },
        .invert => switch (operand) {
            .int_val => |v| .{ .int_val = ~v },
            else => null,
        },
        .uadd => switch (operand) {
            .int_val => operand,
            .float_val => operand,
            else => null,
        },
        .usub => switch (operand) {
            .int_val => |v| .{ .int_val = -v },
            .float_val => |v| .{ .float_val = -v },
            else => null,
        },
    };
}
