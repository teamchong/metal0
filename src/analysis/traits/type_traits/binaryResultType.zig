//! binaryResultType - Get result type of binary operation (a + b, a * b, etc)
//! USE: When inferring expression types for codegen
//! HANDLES: +, -, *, /, //, %, **, &, |, ^, <<, >>
//!
//! NOTE: For operations that need AST inspection (large shift/pow constants),
//! use binaryResultTypeWithHints() which accepts optional hint parameters.

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const string_traits = @import("../string_traits.zig");
const container_traits = @import("../container_traits.zig");
const isNumeric = @import("isNumeric.zig").isNumeric;
const isIntegral = @import("isIntegral.zig").isIntegral;
const isFloating = @import("isFloating.zig").isFloating;
const isUnknown = @import("isUnknown.zig").isUnknown;

pub const BinOp = enum { Add, Sub, Mult, Div, FloorDiv, Mod, Pow, BitAnd, BitOr, BitXor, LShift, RShift };

/// Hints for operations that need AST-level information
pub const OperationHints = struct {
    /// For LShift: the shift amount if known at compile time
    shift_amount: ?i64 = null,
    /// For Pow: the exponent value if known at compile time
    exponent: ?i64 = null,
};

/// Get result type with optional hints for AST-level information
pub fn binaryResultTypeWithHints(op: BinOp, left: NativeType, right: NativeType, hints: OperationHints) NativeType {
    if (isUnknown(left) or isUnknown(right)) return .unknown;
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);

    // Check if either operand needs BigInt (explicit bigint or unbounded int)
    const left_needs_bigint = left_tag == .bigint or
        (left_tag == .int and left.int.needsBigInt());
    const right_needs_bigint = right_tag == .bigint or
        (right_tag == .int and right.int.needsBigInt());

    switch (op) {
        .Add => {
            // String/bytes concatenation
            if (string_traits.canConcat(left, right)) return string_traits.getConcatResultType(left, right) orelse .unknown;
            // List concatenation: list + list → pyvalue (concatRuntime returns PyValue)
            if (container_traits.isList(left) and container_traits.isList(right)) return .pyvalue;
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            // Numeric promotion
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Sub => {
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Mod => {
            // String formatting: str % value → runtime string
            if (string_traits.isString(left)) return .{ .string = .runtime };
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Mult => {
            // String/bytes repetition
            if (string_traits.canRepeat(left) and isIntegral(right)) return string_traits.getRepeatResultType(left) orelse .unknown;
            if (string_traits.canRepeat(right) and isIntegral(left)) return string_traits.getRepeatResultType(right) orelse .unknown;
            // List repetition: list * int → pyvalue (repeatRuntime returns PyValue)
            if (container_traits.isList(left) and isIntegral(right)) return .pyvalue;
            if (container_traits.isList(right) and isIntegral(left)) return .pyvalue;
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Div => {
            // Path join: Path / string → Path
            if (left_tag == .path) return .path;
            // Python division always returns float for primitives
            if (isNumeric(left) and isNumeric(right)) return .float;
        },
        .FloorDiv => {
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) {
                if (isFloating(left) or isFloating(right)) return .float;
                return promoteNumeric(left, right);
            }
        },
        .Pow => {
            // Large exponent produces BigInt (e.g., 10 ** 30000)
            if (hints.exponent) |exp| {
                if (exp >= 20) return .bigint;
            }
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) {
                if (isFloating(left) or isFloating(right)) return .float;
                return promoteNumeric(left, right);
            }
        },
        .LShift => {
            // Large shift produces BigInt (e.g., 1 << 100000)
            if (hints.shift_amount) |shift| {
                if (shift >= 63) return .bigint;
            } else {
                // Shift amount not comptime-known - use BigInt for safety
                return .bigint;
            }
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right);
        },
        .RShift, .BitAnd, .BitOr, .BitXor => {
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right);
        },
    }
    return .unknown;
}

/// Get result type of binary operation (simple version without hints)
/// For LShift, assumes unknown shift amount → returns bigint for safety
pub fn binaryResultType(op: BinOp, left: NativeType, right: NativeType) NativeType {
    return binaryResultTypeWithHints(op, left, right, .{});
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
