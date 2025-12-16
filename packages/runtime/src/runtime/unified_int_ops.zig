//! UnifiedInt Operations - Runtime helpers for auto-promoting integer arithmetic
//!
//! These helpers wrap UnifiedInt operations with OOM handling, eliminating the need
//! for error handling in generated code. All functions panic on OOM.
//!
//! UnifiedInt automatically promotes from i64 to BigInt on overflow, matching
//! Python's unlimited precision integer semantics.
//!
//! ## Usage
//! Generated code becomes simple function calls:
//! ```zig
//! // Instead of: (try a.add(b, alloc))
//! runtime.unified_int_ops.add(a, b, alloc)
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const UnifiedInt = @import("../Objects/pyint.zig").UnifiedInt;

// =============================================================================
// Conversion Helpers
// =============================================================================

/// Create UnifiedInt from i64 (no allocation, always fast path)
pub fn fromI64(value: i64) UnifiedInt {
    return UnifiedInt.fromI64(value);
}

/// Create UnifiedInt from usize (for index conversions)
pub fn fromUsize(value: usize) UnifiedInt {
    return UnifiedInt.fromI64(@intCast(value));
}

/// Create UnifiedInt from u64
pub fn fromU64(value: u64) UnifiedInt {
    if (value <= std.math.maxInt(i64)) {
        return UnifiedInt.fromI64(@intCast(value));
    }
    // Value too large for i64 - would need BigInt
    // For now, panic since this is rare
    @panic("u64 value too large for UnifiedInt.fromI64");
}

/// Create UnifiedInt from BigInt value (allocates on heap)
/// Use this when you have a BigInt value from parseIntToBigInt etc.
pub fn fromBigIntVal(allocator: Allocator, big: anytype) UnifiedInt {
    // Import BigInt from runtime
    const BigInt = @import("bigint").BigInt;

    // Handle both BigInt value and *BigInt pointer
    const big_ptr: *const BigInt = switch (@typeInfo(@TypeOf(big))) {
        .pointer => big,
        else => &big, // Take address of value
    };

    // Try to demote to i64 if it fits
    if (big_ptr.toInt64()) |small_val| {
        return .{ .small = small_val };
    }

    // Allocate and clone
    const cloned = allocator.create(BigInt) catch @panic("OOM");
    cloned.* = big_ptr.clone(allocator) catch @panic("OOM");
    return .{ .big = cloned };
}

// =============================================================================
// Binary Arithmetic Operations
// =============================================================================

/// Add two UnifiedInts: left + right (panics on OOM)
pub fn add(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return left.add(right, allocator) catch @panic("OOM");
}

/// Subtract two UnifiedInts: left - right (panics on OOM)
pub fn sub(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return left.sub(right, allocator) catch @panic("OOM");
}

/// Multiply two UnifiedInts: left * right (panics on OOM)
pub fn mul(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return left.mul(right, allocator) catch @panic("OOM");
}

/// Floor divide: left // right (panics on OOM or division by zero)
pub fn floorDiv(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return left.floorDiv(right, allocator) catch |e| switch (e) {
        error.DivisionByZero => @panic("division by zero"),
        error.OutOfMemory => @panic("OOM"),
    };
}

/// Modulo: left % right with Python semantics (panics on OOM or division by zero)
pub fn mod(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return left.mod(right, allocator) catch |e| switch (e) {
        error.DivisionByZero => @panic("division by zero"),
        error.OutOfMemory => @panic("OOM"),
    };
}

/// Power: base ** exp (panics on OOM)
pub fn pow(base: UnifiedInt, exp: u32, allocator: Allocator) UnifiedInt {
    return base.pow(exp, allocator) catch @panic("OOM");
}

/// Left shift: value << shift (panics on OOM)
pub fn shl(value: UnifiedInt, shift: u32, allocator: Allocator) UnifiedInt {
    return value.shl(shift, allocator) catch @panic("OOM");
}

/// Right shift: value >> shift (panics on OOM)
pub fn shr(value: UnifiedInt, shift: u32, allocator: Allocator) UnifiedInt {
    return value.shr(shift, allocator) catch @panic("OOM");
}

// =============================================================================
// Unary Operations
// =============================================================================

/// Negate: -value (panics on OOM)
pub fn neg(value: UnifiedInt, allocator: Allocator) UnifiedInt {
    return value.neg(allocator) catch @panic("OOM");
}

/// Absolute value: abs(value) (panics on OOM)
pub fn abs(value: UnifiedInt, allocator: Allocator) UnifiedInt {
    return value.abs(allocator) catch @panic("OOM");
}

// =============================================================================
// Comparison Operations
// =============================================================================

/// Compare: returns -1 if left < right, 0 if equal, 1 if left > right
pub fn cmp(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) i32 {
    return left.compare(right, allocator) catch @panic("OOM");
}

/// Equality check
pub fn eql(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) bool {
    return left.eql(right, allocator) catch @panic("OOM");
}

/// Less than
pub fn lt(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) bool {
    return cmp(left, right, allocator) < 0;
}

/// Less than or equal
pub fn le(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) bool {
    return cmp(left, right, allocator) <= 0;
}

/// Greater than
pub fn gt(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) bool {
    return cmp(left, right, allocator) > 0;
}

/// Greater than or equal
pub fn ge(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) bool {
    return cmp(left, right, allocator) >= 0;
}

// =============================================================================
// Mixed-type Operations (UnifiedInt with i64)
// =============================================================================

/// i64 + UnifiedInt
pub fn i64Add(left: i64, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return add(fromI64(left), right, allocator);
}

/// UnifiedInt + i64
pub fn addI64(left: UnifiedInt, right: i64, allocator: Allocator) UnifiedInt {
    return add(left, fromI64(right), allocator);
}

/// i64 - UnifiedInt
pub fn i64Sub(left: i64, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return sub(fromI64(left), right, allocator);
}

/// UnifiedInt - i64
pub fn subI64(left: UnifiedInt, right: i64, allocator: Allocator) UnifiedInt {
    return sub(left, fromI64(right), allocator);
}

/// i64 * UnifiedInt
pub fn i64Mul(left: i64, right: UnifiedInt, allocator: Allocator) UnifiedInt {
    return mul(fromI64(left), right, allocator);
}

/// UnifiedInt * i64
pub fn mulI64(left: UnifiedInt, right: i64, allocator: Allocator) UnifiedInt {
    return mul(left, fromI64(right), allocator);
}

// =============================================================================
// Conversion to Primitive Types
// =============================================================================

/// Convert to i64, returns null if out of range
pub fn toI64(value: UnifiedInt) ?i64 {
    return value.toI64();
}

/// Convert to f64
pub fn toF64(value: UnifiedInt) f64 {
    return value.toFloat();
}

/// Check if value is zero
pub fn isZero(value: UnifiedInt) bool {
    return value.isZero();
}

/// Check if value is negative
pub fn isNegative(value: UnifiedInt) bool {
    return value.isNegative();
}

// =============================================================================
// Bitwise Operations
// =============================================================================

/// Bitwise NOT: ~value
/// Python semantics: ~x == -(x+1)
pub fn bitNot(value: UnifiedInt, allocator: Allocator) UnifiedInt {
    // ~x = -(x+1) in Python's two's complement semantics for unlimited precision
    const one = UnifiedInt.fromI64(1);
    const plus_one = value.add(one, allocator) catch @panic("OOM");
    return plus_one.neg(allocator) catch @panic("OOM");
}

// TODO: Add when UnifiedInt is extended with proper bitwise operations
// pub fn bitAnd(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt
// pub fn bitOr(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt
// pub fn bitXor(left: UnifiedInt, right: UnifiedInt, allocator: Allocator) UnifiedInt
