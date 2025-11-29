/// Python bool type implementation (CPython ABI compatible)
/// In CPython, bool is a subclass of int
const std = @import("std");
const runtime = @import("runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyBoolObject = runtime.PyBoolObject;
pub const PyBool_Type = &runtime.PyBool_Type;

// Bool singletons (like CPython's Py_True and Py_False)
var _Py_TrueStruct: PyBoolObject = .{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1, // Immortal
            .ob_type = PyBool_Type,
        },
        .ob_size = 1,
    },
    .ob_digit = 1,
};

var _Py_FalseStruct: PyBoolObject = .{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1, // Immortal
            .ob_type = PyBool_Type,
        },
        .ob_size = 0,
    },
    .ob_digit = 0,
};

pub const Py_True: *PyObject = @ptrCast(&_Py_TrueStruct);
pub const Py_False: *PyObject = @ptrCast(&_Py_FalseStruct);

/// Python bool type - wrapper around CPython-compatible PyBoolObject
pub const PyBool = struct {
    // Legacy field for backwards compatibility
    value: bool = false,

    /// Create a new PyBoolObject with the given value
    /// Note: In CPython, True and False are singletons, so we return those
    pub fn create(allocator: std.mem.Allocator, val: bool) !*PyObject {
        _ = allocator; // Singletons don't need allocation
        return if (val) Py_True else Py_False;
    }

    /// Get the bool value from a PyBoolObject
    pub fn getValue(obj: *PyObject) bool {
        std.debug.assert(runtime.PyBool_Check(obj));
        const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
        return bool_obj.ob_digit != 0;
    }

    /// Convert bool to string representation
    pub fn toString(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        const val = getValue(obj);
        const str = if (val) "True" else "False";
        return try runtime.PyString.create(allocator, str);
    }
};

// CPython-compatible C API functions
pub fn PyBool_FromLong(val: c_long) callconv(.C) *PyObject {
    runtime.Py_INCREF(if (val != 0) Py_True else Py_False);
    return if (val != 0) Py_True else Py_False;
}
