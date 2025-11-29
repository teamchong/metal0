/// Python integer type implementation (CPython ABI compatible)
const std = @import("std");
const runtime = @import("runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyLongObject = runtime.PyLongObject;
pub const PyLong_Type = &runtime.PyLong_Type;

/// Python integer type - wrapper around CPython-compatible PyLongObject
pub const PyInt = struct {
    /// Create a new PyLongObject with the given value
    pub fn create(allocator: std.mem.Allocator, val: i64) !*PyObject {
        const long_obj = try allocator.create(PyLongObject);
        long_obj.* = PyLongObject{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1,
                    .ob_type = PyLong_Type,
                },
                .ob_size = 1, // Single digit (simplified)
            },
            .ob_digit = val,
        };
        return @ptrCast(long_obj);
    }

    /// Get the integer value from a PyLongObject
    pub fn getValue(obj: *PyObject) i64 {
        std.debug.assert(runtime.PyLong_Check(obj));
        const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
        return long_obj.ob_digit;
    }

    /// Convert integer to string representation
    pub fn toString(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        const val = getValue(obj);
        const str = try std.fmt.allocPrint(allocator, "{}", .{val});
        return try runtime.PyString.create(allocator, str);
    }
};

// CPython-compatible C API functions
pub fn PyLong_FromLong(val: c_long) callconv(.C) *PyObject {
    // Note: This uses a global allocator - in practice you'd want arena/pool
    const allocator = std.heap.page_allocator;
    return PyInt.create(allocator, val) catch @panic("PyLong_FromLong allocation failed");
}

pub fn PyLong_AsLong(obj: *PyObject) callconv(.C) c_long {
    return @intCast(PyInt.getValue(obj));
}

pub fn PyLong_AsLongLong(obj: *PyObject) callconv(.C) c_longlong {
    return PyInt.getValue(obj);
}
