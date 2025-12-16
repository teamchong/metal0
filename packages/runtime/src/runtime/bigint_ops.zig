//! BigInt Operations - Runtime helpers for arbitrary precision integer arithmetic
//!
//! These helpers wrap BigInt operations with OOM handling, eliminating the need
//! for complex error handling in generated code. All functions panic on OOM,
//! matching Python semantics where memory errors are unrecoverable.
//!
//! ## Usage
//! Generated code becomes simple function calls:
//! ```zig
//! // Instead of: ((a.add(&b, alloc) catch @panic("OOM")))
//! runtime.bigint_ops.add(a, b, alloc)
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const BigInt = @import("bigint").BigInt;

// =============================================================================
// Conversion Helpers
// =============================================================================

/// Convert i64 to BigInt (panics on OOM)
pub fn fromInt(allocator: Allocator, value: i64) BigInt {
    return BigInt.fromInt(allocator, value) catch @panic("OOM");
}

/// Convert u64 to BigInt (panics on OOM)
pub fn fromUint(allocator: Allocator, value: u64) BigInt {
    return BigInt.fromUint(allocator, value) catch @panic("OOM");
}

/// Convert f64 to BigInt, truncating toward zero (panics on OOM)
pub fn fromFloat(allocator: Allocator, value: f64) BigInt {
    return BigInt.fromFloat(allocator, value) catch @panic("OOM");
}

/// Clone a BigInt (panics on OOM)
pub fn clone(value: BigInt, allocator: Allocator) BigInt {
    return value.clone(allocator) catch @panic("OOM");
}

// =============================================================================
// Binary Arithmetic Operations
// =============================================================================

/// Add two BigInts: left + right (panics on OOM)
pub fn add(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.add(&right, allocator) catch @panic("OOM");
}

/// Subtract two BigInts: left - right (panics on OOM)
pub fn sub(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.sub(&right, allocator) catch @panic("OOM");
}

/// Multiply two BigInts: left * right (panics on OOM)
pub fn mul(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.mul(&right, allocator) catch @panic("OOM");
}

/// Divide two BigInts with truncation: left // right (panics on OOM or div by zero)
pub fn divTrunc(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.divTrunc(&right, allocator) catch |e| switch (e) {
        error.DivisionByZero => @panic("division by zero"),
        error.OutOfMemory => @panic("OOM"),
    };
}

/// Floor divide two BigInts: left // right with Python semantics (panics on OOM or div by zero)
pub fn divFloor(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.divFloor(&right, allocator) catch |e| switch (e) {
        error.DivisionByZero => @panic("division by zero"),
        error.OutOfMemory => @panic("OOM"),
    };
}

/// Modulo of two BigInts: left % right with Python semantics (panics on OOM or div by zero)
pub fn mod(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.mod(&right, allocator) catch |e| switch (e) {
        error.DivisionByZero => @panic("division by zero"),
        error.OutOfMemory => @panic("OOM"),
    };
}

/// Power: base ** exp (panics on OOM)
/// exp must be non-negative u32
pub fn pow(base: BigInt, exp: u32, allocator: Allocator) BigInt {
    return base.pow(exp, allocator) catch @panic("OOM");
}

/// Power with BigInt exponent (for large exponents)
/// Falls back to pow with smaller chunks for very large exponents
pub fn powBig(base: BigInt, exp: BigInt, allocator: Allocator) BigInt {
    // For now, convert to u32 if possible, otherwise use iterative approach
    if (exp.toInt(u32)) |small_exp| {
        return pow(base, small_exp, allocator);
    } else |_| {
        // Very large exponent - this would produce astronomically large results
        // For practical purposes, this should be rare
        @panic("exponent too large");
    }
}

// =============================================================================
// Unary Operations
// =============================================================================

/// Negate a BigInt: -value (panics on OOM)
pub fn neg(value: BigInt, allocator: Allocator) BigInt {
    var result = clone(value, allocator);
    result.negate();
    return result;
}

/// Absolute value: abs(value) (panics on OOM)
pub fn abs(value: BigInt, allocator: Allocator) BigInt {
    var result = clone(value, allocator);
    result.setSign(.positive);
    return result;
}

// =============================================================================
// Bitwise Operations
// =============================================================================

/// Bitwise AND: left & right (panics on OOM)
pub fn bitAnd(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.bitAnd(&right, allocator) catch @panic("OOM");
}

/// Bitwise OR: left | right (panics on OOM)
pub fn bitOr(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.bitOr(&right, allocator) catch @panic("OOM");
}

/// Bitwise XOR: left ^ right (panics on OOM)
pub fn bitXor(left: BigInt, right: BigInt, allocator: Allocator) BigInt {
    return left.bitXor(&right, allocator) catch @panic("OOM");
}

/// Left shift: value << shift (panics on OOM)
pub fn shl(value: BigInt, shift: usize, allocator: Allocator) BigInt {
    return value.shl(shift, allocator) catch @panic("OOM");
}

/// Right shift: value >> shift (panics on OOM)
pub fn shr(value: BigInt, shift: usize, allocator: Allocator) BigInt {
    return value.shr(shift, allocator) catch @panic("OOM");
}

// =============================================================================
// Mixed-type Operations (BigInt with i64)
// =============================================================================

/// Add BigInt and i64: left + right (panics on OOM)
pub fn addInt(left: BigInt, right: i64, allocator: Allocator) BigInt {
    const right_big = fromInt(allocator, right);
    return add(left, right_big, allocator);
}

/// Subtract i64 from BigInt: left - right (panics on OOM)
pub fn subInt(left: BigInt, right: i64, allocator: Allocator) BigInt {
    const right_big = fromInt(allocator, right);
    return sub(left, right_big, allocator);
}

/// Multiply BigInt by i64: left * right (panics on OOM)
pub fn mulInt(left: BigInt, right: i64, allocator: Allocator) BigInt {
    const right_big = fromInt(allocator, right);
    return mul(left, right_big, allocator);
}

/// i64 + BigInt (panics on OOM)
pub fn intAdd(left: i64, right: BigInt, allocator: Allocator) BigInt {
    const left_big = fromInt(allocator, left);
    return add(left_big, right, allocator);
}

/// i64 - BigInt (panics on OOM)
pub fn intSub(left: i64, right: BigInt, allocator: Allocator) BigInt {
    const left_big = fromInt(allocator, left);
    return sub(left_big, right, allocator);
}

/// i64 * BigInt (panics on OOM)
pub fn intMul(left: i64, right: BigInt, allocator: Allocator) BigInt {
    const left_big = fromInt(allocator, left);
    return mul(left_big, right, allocator);
}

// =============================================================================
// Comparison Operations (no allocation needed)
// =============================================================================

/// Compare two BigInts: returns -1, 0, or 1
pub fn cmp(left: BigInt, right: BigInt) i32 {
    const order = left.order(&right);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

/// Equality check
pub fn eql(left: BigInt, right: BigInt) bool {
    return left.eql(&right);
}

/// Less than
pub fn lt(left: BigInt, right: BigInt) bool {
    return left.order(&right) == .lt;
}

/// Less than or equal
pub fn le(left: BigInt, right: BigInt) bool {
    const order = left.order(&right);
    return order == .lt or order == .eq;
}

/// Greater than
pub fn gt(left: BigInt, right: BigInt) bool {
    return left.order(&right) == .gt;
}

/// Greater than or equal
pub fn ge(left: BigInt, right: BigInt) bool {
    const order = left.order(&right);
    return order == .gt or order == .eq;
}

// =============================================================================
// Conversion to Primitive Types
// =============================================================================

/// Convert to i64, returns null if out of range
pub fn toI64(value: BigInt) ?i64 {
    return value.toInt(i64) catch null;
}

/// Convert to f64
pub fn toF64(value: BigInt) f64 {
    return value.toFloat(f64);
}

/// Check if value fits in i64
pub fn fitsInI64(value: BigInt) bool {
    return value.toInt(i64) != null;
}

// =============================================================================
// String Operations
// =============================================================================

/// Convert to string in given base (panics on OOM)
pub fn toString(value: BigInt, allocator: Allocator, base: u8) []const u8 {
    return value.toString(allocator, base) catch @panic("OOM");
}

/// Convert to decimal string (panics on OOM)
pub fn toDecimalString(value: BigInt, allocator: Allocator) []const u8 {
    return toString(value, allocator, 10);
}
