/// Python logical operations (or, and) for mixed types
const std = @import("std");
const object = @import("../Objects/object.zig");
const PyValue = object.PyValue;
const toPyValue = object.toPyValue;
const bool_ops = @import("bool_ops.zig");
const toBoolWithError = bool_ops.toBoolWithError;

/// Python `or` semantics for incompatible types
/// Returns a if truthy, else b (as PyValue)
/// IMPORTANT: Must call toBool() BEFORE toPyValue() to invoke __bool__ methods
pub fn pyOr(allocator: std.mem.Allocator, a: anytype, b: anytype) !PyValue {
    // Check truthiness using toBool which handles __bool__ methods via comptime introspection
    // This must happen BEFORE toPyValue conversion which loses method information
    const a_truthy = try toBoolWithError(a);
    if (a_truthy) {
        return try toPyValue(allocator, a);
    }
    return try toPyValue(allocator, b);
}

/// Python `and` semantics for incompatible types
/// Returns a if falsy, else b (as PyValue)
/// IMPORTANT: Must call toBool() BEFORE toPyValue() to invoke __bool__ methods
pub fn pyAnd(allocator: std.mem.Allocator, a: anytype, b: anytype) !PyValue {
    // Check truthiness using toBool which handles __bool__ methods via comptime introspection
    // This must happen BEFORE toPyValue conversion which loses method information
    const a_truthy = try toBoolWithError(a);
    if (!a_truthy) {
        return try toPyValue(allocator, a);
    }
    return try toPyValue(allocator, b);
}
