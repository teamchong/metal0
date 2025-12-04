/// Python float type implementation (CPython ABI compatible)
const std = @import("std");
const runtime = @import("runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyFloatObject = runtime.PyFloatObject;
pub const PyFloat_Type = &runtime.PyFloat_Type;

/// Python float type - wrapper around CPython-compatible PyFloatObject
pub const PyFloat = struct {
    /// Create a new PyFloatObject with the given value
    pub fn create(allocator: std.mem.Allocator, val: f64) !*PyObject {
        const float_obj = try allocator.create(PyFloatObject);
        float_obj.* = PyFloatObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyFloat_Type,
            },
            .ob_fval = val,
        };
        return @ptrCast(float_obj);
    }

    /// Get the float value from a PyFloatObject
    pub fn getValue(obj: *PyObject) f64 {
        std.debug.assert(runtime.PyFloat_Check(obj));
        const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
        return float_obj.ob_fval;
    }

    /// Convert float to string representation
    pub fn toString(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        const val = getValue(obj);
        // Python convention: nan never has sign
        const str = if (std.math.isNan(val))
            try allocator.dupe(u8, "nan")
        else if (std.math.isInf(val))
            try allocator.dupe(u8, if (val < 0) "-inf" else "inf")
        else
            try std.fmt.allocPrint(allocator, "{d}", .{val});
        return try runtime.PyString.create(allocator, str);
    }
};

// CPython-compatible C API functions
pub fn PyFloat_FromDouble(val: f64) callconv(.C) *PyObject {
    const allocator = std.heap.page_allocator;
    return PyFloat.create(allocator, val) catch @panic("PyFloat_FromDouble allocation failed");
}

pub fn PyFloat_AsDouble(obj: *PyObject) callconv(.C) f64 {
    return PyFloat.getValue(obj);
}
