/// Type name and string conversion utilities
const std = @import("std");

// Import PyPowResult from builtins
const builtins = @import("builtins.zig");
const PyPowResult = builtins.PyPowResult;

/// Get Python type name for type() builtin using runtime dispatch
/// This version uses anytype with runtime type introspection to avoid comptime explosion
/// when used with many different types (prevents O(n²) compilation time)
pub fn pyTypeName(value: anytype) []const u8 {
    const T = @TypeOf(value);

    // Special handling for PyPowResult - check which variant it is
    if (T == PyPowResult) {
        return value.typeName();
    }

    // Map Zig types to Python type names using runtime introspection
    const info = @typeInfo(T);
    switch (info) {
        .float, .comptime_float => return "float",
        .int, .comptime_int => return "int",
        .bool => return "bool",
        .pointer => |ptr_info| {
            // Handle []const u8 and []u8 (strings)
            if (ptr_info.size == .slice) {
                const Child = ptr_info.child;
                if (Child == u8) {
                    return "str";
                }
            }
            // For other pointers, check if pointing to a struct with __name__
            if (@typeInfo(ptr_info.child) == .@"struct") {
                if (@hasDecl(ptr_info.child, "__name__")) {
                    return ptr_info.child.__name__;
                }
            }
        },
        .@"struct" => {
            // Check if struct has __name__ field (Python classes)
            if (@hasDecl(T, "__name__")) {
                return T.__name__;
            }
        },
        else => {},
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
