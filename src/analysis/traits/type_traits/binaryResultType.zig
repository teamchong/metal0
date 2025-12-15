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
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);

    // Check if either operand needs BigInt (explicit bigint or unbounded int)
    const left_needs_bigint = left_tag == .bigint or
        (left_tag == .int and left.int.needsBigInt());
    const right_needs_bigint = right_tag == .bigint or
        (right_tag == .int and right.int.needsBigInt());

    // SPECIAL CASE: For bitwise operations (BitAnd, BitOr, BitXor), if ONE operand is BigInt
    // and the other is unknown, we should return BigInt (since unknown could be any int-like value)
    // This handles: hibit:BigInt | getrandbits():unknown → BigInt
    const is_bitwise = op == .BitAnd or op == .BitOr or op == .BitXor;
    if (is_bitwise) {
        const one_unknown = isUnknown(left) != isUnknown(right); // XOR: exactly one is unknown
        if (one_unknown and (left_needs_bigint or right_needs_bigint)) {
            return .bigint;
        }
    }

    // General rule: if both operands are unknown, return unknown
    if (isUnknown(left) and isUnknown(right)) return .unknown;

    // If ONE operand is unknown but the other isn't BigInt, return unknown
    if (isUnknown(left) or isUnknown(right)) return .unknown;

    // Check if either operand is unified_int
    const left_is_unified = left_tag == .unified_int;
    const right_is_unified = right_tag == .unified_int;

    switch (op) {
        .Add => {
            // String/bytes concatenation
            if (string_traits.canConcat(left, right)) return string_traits.getConcatResultType(left, right) orelse .unknown;
            // List/array concatenation: list/array + list/array → pyvalue (concatRuntime returns PyValue)
            // Note: Both .list and .array types use concatRuntime when variables are involved
            const left_is_listlike = container_traits.isList(left) or left_tag == .array;
            const right_is_listlike = container_traits.isList(right) or right_tag == .array;
            if (left_is_listlike and right_is_listlike) return .pyvalue;
            // UnifiedInt propagation (unified_int preserves ability to hold small or big)
            if (left_is_unified or right_is_unified) return .unified_int;
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            // Numeric promotion
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Sub => {
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Mod => {
            // String formatting: str % value → runtime string
            if (string_traits.isString(left)) return .{ .string = .runtime };
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Mult => {
            // String/bytes repetition
            if (string_traits.canRepeat(left) and isIntegral(right)) return string_traits.getRepeatResultType(left) orelse .unknown;
            if (string_traits.canRepeat(right) and isIntegral(left)) return string_traits.getRepeatResultType(right) orelse .unknown;
            // List/array repetition: list/array * int → pyvalue (repeatRuntime returns PyValue)
            const left_is_listlike = container_traits.isList(left) or left_tag == .array;
            const right_is_listlike = container_traits.isList(right) or right_tag == .array;
            if (left_is_listlike and isIntegral(right)) return .pyvalue;
            if (right_is_listlike and isIntegral(left)) return .pyvalue;
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
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
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
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
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
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
                // Shift amount not comptime-known - use unified_int or BigInt for safety
                if (left_is_unified or right_is_unified) return .unified_int;
                return .bigint;
            }
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
            // BigInt propagation
            if (left_needs_bigint or right_needs_bigint) return .bigint;
            if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right);
        },
        .RShift, .BitAnd, .BitOr, .BitXor => {
            // UnifiedInt propagation
            if (left_is_unified or right_is_unified) return .unified_int;
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
    // UnifiedInt absorbs other int types (it can hold both small and big)
    if (left_tag == .unified_int or right_tag == .unified_int) return .unified_int;
    if (left_tag == .bigint or right_tag == .bigint) return .bigint;
    if (left_tag == .int and right_tag == .int) {
        if (left.int == .unbounded or right.int == .unbounded) return .{ .int = .unbounded };
        return .{ .int = .bounded };
    }
    if (left_tag == .usize or right_tag == .usize) return .usize;
    return .{ .int = .bounded };
}
