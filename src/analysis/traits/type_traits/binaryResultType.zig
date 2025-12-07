//! binaryResultType - Get result type of binary operation (a + b, a * b, etc)
//! USE: When inferring expression types for codegen
//! HANDLES: +, -, *, /, //, %, **, &, |, ^, <<, >>

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const string_traits = @import("../string_traits.zig");
const isNumeric = @import("isNumeric.zig").isNumeric;
const isIntegral = @import("isIntegral.zig").isIntegral;
const isFloating = @import("isFloating.zig").isFloating;
const isUnknown = @import("isUnknown.zig").isUnknown;

pub const BinOp = enum { Add, Sub, Mult, Div, FloorDiv, Mod, Pow, BitAnd, BitOr, BitXor, LShift, RShift };

pub fn binaryResultType(op: BinOp, left: NativeType, right: NativeType) NativeType {
    if (isUnknown(left) or isUnknown(right)) return .unknown;
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);

    switch (op) {
        .Add => {
            if (string_traits.canConcat(left, right)) return string_traits.getConcatResultType(left, right) orelse .unknown;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
            if (left_tag == .list and right_tag == .list) return left;
        },
        .Sub, .Mod => if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right),
        .Mult => {
            if (string_traits.canRepeat(left) and isIntegral(right)) return string_traits.getRepeatResultType(left) orelse .unknown;
            if (string_traits.canRepeat(right) and isIntegral(left)) return string_traits.getRepeatResultType(right) orelse .unknown;
            if (left_tag == .list and isIntegral(right)) return left;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Div => if (isNumeric(left) and isNumeric(right)) return .float,
        .FloorDiv => if (isNumeric(left) and isNumeric(right)) {
            if (isFloating(left) or isFloating(right)) return .float;
            return promoteNumeric(left, right);
        },
        .Pow => if (isNumeric(left) and isNumeric(right)) {
            if (isFloating(left) or isFloating(right)) return .float;
            return promoteNumeric(left, right);
        },
        .BitAnd, .BitOr, .BitXor, .LShift, .RShift => if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right),
    }
    return .unknown;
}

fn promoteNumeric(left: NativeType, right: NativeType) NativeType {
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);
    if (left_tag == .complex or right_tag == .complex) return .complex;
    if (left_tag == .float or right_tag == .float) return .float;
    if (left_tag == .bigint or right_tag == .bigint) return .bigint;
    if (left_tag == .int and right_tag == .int) {
        if (left.int == .unbounded or right.int == .unbounded) return .{ .int = .unbounded };
        return .{ .int = .bounded };
    }
    if (left_tag == .usize or right_tag == .usize) return .usize;
    return .{ .int = .bounded };
}
