/// Type name and string conversion utilities
const std = @import("std");

// Import PyPowResult from builtins
const builtins = @import("builtins.zig");
const PyPowResult = builtins.PyPowResult;

/// Get Python type name for type() builtin
/// Handles special cases like PyPowResult which can be float or complex
pub fn pyTypeName(comptime T: type, value: T) []const u8 {
    // Special handling for PyPowResult - check which variant it is
    if (T == PyPowResult) {
        return value.typeName();
    }

    // Map Zig types to Python type names
    const info = @typeInfo(T);
    if (info == .float or info == .comptime_float) {
        return "float";
    }
    if (info == .int or info == .comptime_int) {
        return "int";
    }
    if (info == .bool) {
        return "bool";
    }
    if (T == []const u8 or T == []u8) {
        return "str";
    }

    // For structs, check if it has a Python type name
    if (info == .@"struct") {
        if (@hasDecl(T, "__name__")) {
            return T.__name__;
        }
    }

    // Default: use Zig type name
    return @typeName(T);
}

/// Convert any value to its string representation
/// Used when code calls str(value) on an anytype parameter
pub fn pyStrFromAny(value: anytype) []const u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // String types - return as-is
    if (T == []const u8 or T == []u8) {
        return value;
    }

    // Pointer to array (string literal like *const [N:0]u8)
    if (info == .pointer) {
        const Child = info.pointer.child;
        if (@typeInfo(Child) == .array) {
            return value[0..];
        }
    }

    // Struct with .data field (PyBytes)
    if (info == .@"struct" and @hasField(T, "data")) {
        return value.data;
    }

    // For other types, return empty string - caller should use pyStr with allocator
    return "";
}
