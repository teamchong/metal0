//! binaryResultType - Get result type of binary operation (a + b, a * b, etc)
//! USE: When inferring expression types for codegen
//! HANDLES: +, -, *, /, //, %, **, &, |, ^, <<, >>
//!
//! NOTE: For operations that need AST inspection (large shift/pow constants),
//! use binaryResultTypeWithHints() which accepts optional hint parameters.
//!
//! TYPE SIMPLIFICATION: Prefers UnifiedInt over BigInt for most operations.
//! UnifiedInt (i64 fast path + BigInt fallback) handles overflow automatically.

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
    /// For Pow: the base value if known at compile time (for complex check)
    pow_base: ?f64 = null,
    /// For Pow: the float exponent value if known at compile time (for complex check)
    pow_exp: ?f64 = null,
};

/// Get result type with optional hints for AST-level information
pub fn binaryResultTypeWithHints(op: BinOp, left: NativeType, right: NativeType, hints: OperationHints) NativeType {
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);

    // Check if either operand needs UnifiedInt (explicit bigint, unified_int, or unbounded int)
    // UnifiedInt handles both small (i64) and large (BigInt) values automatically
    const left_needs_unified = left_tag == .bigint or left_tag == .unified_int or
        (left_tag == .int and left.int.needsBigInt());
    const right_needs_unified = right_tag == .bigint or right_tag == .unified_int or
        (right_tag == .int and right.int.needsBigInt());

    // SPECIAL CASE: For bitwise operations (BitAnd, BitOr, BitXor), if ONE operand is BigInt/UnifiedInt
    // and the other is unknown, we should return UnifiedInt (since unknown could be any int-like value)
    // This handles: hibit:BigInt | getrandbits():unknown → UnifiedInt
    const is_bitwise = op == .BitAnd or op == .BitOr or op == .BitXor;
    if (is_bitwise) {
        const one_unknown = isUnknown(left) != isUnknown(right); // XOR: exactly one is unknown
        if (one_unknown and (left_needs_unified or right_needs_unified)) {
            return .unified_int;
        }
    }

    // General rule: if both operands are unknown, return unknown
    if (isUnknown(left) and isUnknown(right)) return .unknown;

    // If ONE operand is unknown but the other isn't BigInt, return unknown
    if (isUnknown(left) or isUnknown(right)) return .unknown;

    switch (op) {
        .Add => {
            // String/bytes concatenation
            if (string_traits.canConcat(left, right)) return string_traits.getConcatResultType(left, right) orelse .unknown;
            // List/array concatenation: list/array + list/array → pyvalue (concatRuntime returns PyValue)
            // Note: Both .list and .array types use concatRuntime when variables are involved
            const left_is_listlike = container_traits.isList(left) or left_tag == .array;
            const right_is_listlike = container_traits.isList(right) or right_tag == .array;
            if (left_is_listlike and right_is_listlike) return .pyvalue;
            // UnifiedInt propagation (handles both small i64 and large BigInt)
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool arithmetic returns int (Python: False + False = 0, True + True = 2)
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            // Numeric promotion
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Sub => {
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool arithmetic returns int
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Mod => {
            // String formatting: str % value → runtime string
            if (string_traits.isString(left)) return .{ .string = .runtime };
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool arithmetic returns int
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
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
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool arithmetic returns int
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isNumeric(left) and isNumeric(right)) return promoteNumeric(left, right);
        },
        .Div => {
            // Path join: Path / string → Path
            if (left_tag == .path) return .path;
            // Python division always returns float for primitives
            // Bool division returns float (True / True = 1.0)
            if (left_tag == .bool or right_tag == .bool) return .float;
            if (isNumeric(left) and isNumeric(right)) return .float;
        },
        .FloorDiv => {
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool floor division returns int
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isNumeric(left) and isNumeric(right)) {
                if (isFloating(left) or isFloating(right)) return .float;
                return promoteNumeric(left, right);
            }
        },
        .Pow => {
            // Large exponent produces UnifiedInt (e.g., 10 ** 30000)
            // UnifiedInt will auto-promote to BigInt internally
            if (hints.exponent) |exp| {
                if (exp >= 20) return .unified_int;
            }
            // Float exponent produces PyPowResult (could be complex for negative base)
            // e.g., (-2.0) ** 0.5 = complex, 4.0 ** 0.5 = float 2.0
            // EXCEPTION: If both base and exp are comptime known and base >= 0, result is float
            if (isFloating(right)) {
                if (hints.pow_base != null and hints.pow_exp != null) {
                    const base = hints.pow_base.?;
                    const exp = hints.pow_exp.?;
                    // Positive base with any exponent = float
                    // Negative base with integer exponent = float (or int, but float is safe)
                    // Negative base with non-integer exponent = complex
                    if (base >= 0.0) {
                        return .float;
                    }
                    // Check if exponent is an integer (e.g., 2.0)
                    if (exp == @trunc(exp)) {
                        return .float;
                    }
                    // Negative base, non-integer exponent = complex
                }
                return .pow_result;
            }
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool power returns int (True ** True = 1)
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isNumeric(left) and isNumeric(right)) {
                if (isFloating(left) or isFloating(right)) return .float;
                return promoteNumeric(left, right);
            }
        },
        .LShift => {
            // Large shift produces UnifiedInt (e.g., 1 << 100000)
            // UnifiedInt will auto-promote to BigInt internally
            if (hints.shift_amount) |shift| {
                if (shift >= 63) return .unified_int;
            } else {
                // Shift amount not comptime-known - use UnifiedInt for safety
                return .unified_int;
            }
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool shift returns int (True << 2 = 4)
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right);
        },
        .RShift => {
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool shift returns int
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right);
        },
        .BitAnd, .BitOr, .BitXor => {
            // UnifiedInt propagation
            if (left_needs_unified or right_needs_unified) return .unified_int;
            // Bool & bool returns bool in Python (True & False = False)
            // But bool & int or int & bool returns int
            if (left_tag == .bool and right_tag == .bool) return .bool;
            if (left_tag == .bool or right_tag == .bool) return .{ .int = .bounded };
            if (isIntegral(left) and isIntegral(right)) return promoteNumeric(left, right);
        },
    }
    return .unknown;
}

/// Get result type of binary operation (simple version without hints)
/// For LShift, assumes unknown shift amount → returns unified_int for safety
pub fn binaryResultType(op: BinOp, left: NativeType, right: NativeType) NativeType {
    return binaryResultTypeWithHints(op, left, right, .{});
}

fn promoteNumeric(left: NativeType, right: NativeType) NativeType {
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);
    if (left_tag == .complex or right_tag == .complex) return .complex;
    if (left_tag == .float or right_tag == .float) return .float;
    // UnifiedInt absorbs other int types (it can hold both small i64 and large BigInt)
    if (left_tag == .unified_int or right_tag == .unified_int) return .unified_int;
    // BigInt promotes to UnifiedInt (UnifiedInt is the preferred type)
    if (left_tag == .bigint or right_tag == .bigint) return .unified_int;
    if (left_tag == .int and right_tag == .int) {
        // Unbounded ints use UnifiedInt for auto-promotion
        if (left.int == .unbounded or right.int == .unbounded) return .unified_int;
        return .{ .int = .bounded };
    }
    if (left_tag == .usize or right_tag == .usize) return .usize;
    return .{ .int = .bounded };
}
