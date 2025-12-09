/// Type-Specific Bool Conversion for Python Truthiness
///
/// This module provides inline bool conversion code generation to avoid
/// `runtime.toBool(anytype)` which causes massive compile-time monomorphization.
///
/// Instead of:
///   runtime.toBool(expr)  // Creates N instantiations for N types
///
/// We generate type-specific inline code:
///   expr != 0             // for int
///   expr != 0.0           // for float
///   expr.len > 0          // for string/slice
///   expr                  // for bool
///   etc.

const std = @import("std");
const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;

/// Returns the inline bool check code suffix for a given type.
/// Returns null if the type needs the full runtime.toBool (unknown/complex types).
///
/// Usage:
///   if (getBoolCheckSuffix(inferred_type)) |suffix| {
///       emit("("); genExpr(expr); emit(suffix);
///   } else {
///       emit("runtime.toBool("); genExpr(expr); emit(")");
///   }
pub fn getBoolCheckSuffix(native_type: NativeType) ?[]const u8 {
    return switch (native_type) {
        // Integer types: != 0
        .int => ") != 0",
        .usize => ") != 0",
        .bigint => ").isZero() == false",
        .unified_int => ").toBool()",

        // Float: != 0.0 (but NaN check is handled by runtime)
        .float => ") != 0.0",

        // Bool: direct use
        .bool => ")",

        // String: .len > 0
        .string => ").len > 0",

        // Bytes: .data.len > 0
        .bytes => ").data.len > 0",

        // List: need runtime.toBool because ArrayList bool check is complex
        // (empty init {} vs actual instance with .items)
        .list => null,

        // Array: .len > 0 (comptime known but still works)
        .array => ").len > 0",

        // Slice: .len > 0
        .slice => ").len > 0",
        .usize_slice => ").len > 0",

        // Tuple: check if has elements (tuples have comptime length)
        // Empty tuple is false in Python
        .tuple => |t| if (t.len == 0) null else ")",

        // Dict: .count() > 0
        .dict => ").count() > 0",

        // Set: .count() > 0
        .set => ").count() > 0",

        // None: always false
        .none => null, // Special case - always emits "false"

        // Optional: != null
        .optional => ") != null",

        // PyValue: use runtime.toBoolValue (concrete, no anytype)
        .pyvalue => null, // Use runtime.toBoolValue

        // Complex types need runtime dispatch - use fallback
        // This includes: unknown, class_instance, closure, function, callable,
        // path, stringio, bytesio, file, hash_object, counter, deque,
        // sqlite_*, complex, exception, cdll, c_func, pyobject,
        // subprocess_*, csv_*, datetime_*, re_*, http_*, list_iterator, etc.
        else => null,
    };
}

/// Check if a type is "trivially true" (never false in Python truthiness)
/// Used to optimize away bool checks for non-empty literals
pub fn isTriviallyTrue(native_type: NativeType) bool {
    return switch (native_type) {
        .closure, .function, .callable => true, // Functions are always truthy
        .class_instance => false, // Could have __bool__ returning False
        else => false,
    };
}

/// Check if a type is "trivially false" (always false in Python truthiness)
pub fn isTriviallyFalse(native_type: NativeType) bool {
    return native_type == .none;
}

/// Generate the bool conversion prefix. Call this before emitting the expression.
/// Returns the prefix string to emit.
pub fn getBoolPrefix(native_type: NativeType) []const u8 {
    if (isTriviallyFalse(native_type)) {
        return "false and ("; // Will short-circuit, expr still evaluated for side effects
    }
    if (isTriviallyTrue(native_type)) {
        return "true or ("; // Will short-circuit
    }
    if (native_type == .pyvalue) {
        return "runtime.toBoolValue(";
    }
    if (getBoolCheckSuffix(native_type)) |_| {
        return "(";
    }
    // Unknown/complex types - use runtime.toBool
    return "runtime.toBool(";
}

/// Generate the bool conversion suffix. Call this after emitting the expression.
/// Returns the suffix string to emit.
pub fn getBoolSuffix(native_type: NativeType) []const u8 {
    if (isTriviallyFalse(native_type)) {
        return ")"; // Matches "false and ("
    }
    if (isTriviallyTrue(native_type)) {
        return ")"; // Matches "true or ("
    }
    if (native_type == .pyvalue) {
        return ")";
    }
    if (getBoolCheckSuffix(native_type)) |suffix| {
        return suffix;
    }
    // Unknown/complex types - use runtime.toBool
    return ")";
}

test "int bool conversion" {
    const suffix = getBoolCheckSuffix(.{ .int = .bounded });
    try std.testing.expectEqualStrings(") != 0", suffix.?);
}

test "bool passthrough" {
    const suffix = getBoolCheckSuffix(.bool);
    try std.testing.expectEqualStrings(")", suffix.?);
}

test "unknown requires runtime" {
    const suffix = getBoolCheckSuffix(.unknown);
    try std.testing.expect(suffix == null);
}
