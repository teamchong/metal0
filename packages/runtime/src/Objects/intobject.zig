/// Python integer type implementation (CPython ABI compatible)
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const runtime = @import("../runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyLongObject = runtime.PyLongObject;
pub const PyLong_Type = &runtime.cpython.PyLong_Type;

/// Python integer type - wrapper around CPython-compatible PyLongObject
pub const PyInt = struct {
    /// Create a new PyLongObject with the given value (Python 3.12+ layout)
    pub fn create(allocator: std.mem.Allocator, val: i64) !*PyObject {
        const long_obj = try allocator.create(PyLongObject);
        // Determine sign: 0=positive, 1=zero, 2=negative
        const sign: usize = if (val == 0) 1 else if (val < 0) 2 else 0;
        const abs_val: u32 = if (val < 0) @intCast(-val) else @intCast(val);
        long_obj.* = PyLongObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyLong_Type,
            },
            .long_value = .{
                .lv_tag = (1 << runtime.cpython._PyLong_NON_SIZE_BITS) | sign,
                .ob_digit = .{abs_val},
            },
        };
        return @ptrCast(long_obj);
    }

    /// Get the integer value from a PyLongObject
    pub fn getValue(obj: *PyObject) i64 {
        std.debug.assert(runtime.PyLong_Check(obj));
        const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
        return long_obj.getValue();
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
    const allocator = allocator_helper.fast_allocator;
    return PyInt.create(allocator, val) catch @panic("PyLong_FromLong allocation failed");
}

pub fn PyLong_AsLong(obj: *PyObject) callconv(.C) c_long {
    return @intCast(PyInt.getValue(obj));
}

pub fn PyLong_AsLongLong(obj: *PyObject) callconv(.C) c_longlong {
    return PyInt.getValue(obj);
}
