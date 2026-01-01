/// Integer conversion utilities
const std = @import("std");
const BigInt = @import("bigint").BigInt;
const type_predicates = @import("type_predicates.zig");

// Import from parent Objects
const object = @import("../Objects/object.zig");
const PyValue = object.PyValue;

// Import exceptions
const exceptions = @import("exceptions.zig");
const PythonError = exceptions.PythonError;
const setException = exceptions.setException;

/// Generic int conversion for __len__, __hash__, etc.
/// Handles both native int types and PyValue
/// Returns error for non-convertible types (e.g., string for __len__)
pub fn pyToInt(value: anytype) PythonError!i64 {
    const T = @TypeOf(value);
    if (T == PyValue) {
        // Extract int from PyValue, return error on non-convertible types
        if (value.toInt()) |i| {
            return i;
        } else {
            // Use centralized error message from PyValue (SINGLE SOURCE OF TRUTH)
            setException("TypeError", value.intErrorMessage());
            return PythonError.TypeError;
        }
    } else if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize or T == comptime_int) {
        return @intCast(value);
    } else if (T == bool) {
        return if (value) 1 else 0;
    } else if (@typeInfo(T) == .optional) {
        if (value) |v| return try pyToInt(v);
        return 0;
    } else {
        // Return error for unsupported types at runtime
        // Map Zig types to Python type names for better error messages
        const type_info = @typeInfo(T);
        const py_type_name = comptime blk: {
            // Pointers to arrays are strings
            if (type_info == .pointer and type_info.pointer.size == .one) {
                const child = @typeInfo(type_info.pointer.child);
                if (child == .array and child.array.child == u8) {
                    break :blk "str";
                }
            }
            // Slices of u8 are strings
            if (type_info == .pointer and type_info.pointer.size == .slice and type_info.pointer.child == u8) {
                break :blk "str";
            }
            // Default to Zig type name
            break :blk @typeName(T);
        };
        setException("TypeError", "'" ++ py_type_name ++ "' object cannot be interpreted as an integer");
        return PythonError.TypeError;
    }
}

/// Convert value to integer for struct.pack - handles BigInt and regular integers
pub inline fn packInt(value: anytype) u64 {
    const T = @TypeOf(value);
    // Handle BigInt directly
    if (T == BigInt) {
        // Try toInt64 first, then fallback to truncation for large values
        return @bitCast(value.toInt64() orelse 0);
    }
    // Handle pointer to BigInt
    if (@typeInfo(T) == .pointer) {
        const child = @typeInfo(T).pointer.child;
        if (child == BigInt) {
            return @bitCast(value.toInt64() orelse 0);
        }
    }
    // Handle regular integers and comptime_int
    const info = @typeInfo(T);
    if (type_predicates.isIntInfo(info)) {
        return @as(u64, @intCast(value));
    }
    // Fallback
    return 0;
}
