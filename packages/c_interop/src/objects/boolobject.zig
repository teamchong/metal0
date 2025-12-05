/// PyBool - EXACT CPython 3.12 memory layout
///
/// Bool is a subclass of int (PyLongObject). Py_True and Py_False are singletons.
///
/// Reference: cpython/Include/boolobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");
const helpers = @import("../optimization_helpers.zig");

// Bool is just a PyLongObject with value 0 or 1
pub const PyBoolObject = cpython.PyLongObject;

// ============================================================================
// SINGLETONS - Py_True and Py_False
// ============================================================================

/// _Py_FalseStruct - the singleton False value
pub export var _Py_FalseStruct: cpython.PyLongObject = .{
    .ob_base = .{
        .ob_refcnt = 1000000, // Immortal
        .ob_type = &PyBool_Type,
    },
    .lv_tag = 0, // 0 digits, non-negative = value 0
    .ob_digit = .{0},
};

/// _Py_TrueStruct - the singleton True value
pub export var _Py_TrueStruct: cpython.PyLongObject = .{
    .ob_base = .{
        .ob_refcnt = 1000000, // Immortal
        .ob_type = &PyBool_Type,
    },
    .lv_tag = (1 << 3) | 0, // 1 digit, non-negative
    .ob_digit = .{1},
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyBool_Type: cpython.PyTypeObject = helpers.makeTypeObject(.{
    .name = "bool",
    .basicsize = @sizeOf(cpython.PyLongObject),
    .flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_LONG_SUBCLASS,
    .doc = "bool(x) -> bool",
});

// ============================================================================
// API FUNCTIONS
// ============================================================================

/// Create bool from C long
pub export fn PyBool_FromLong(v: c_long) callconv(.c) *cpython.PyObject {
    if (v != 0) {
        return @ptrCast(&_Py_TrueStruct.ob_base);
    } else {
        return @ptrCast(&_Py_FalseStruct.ob_base);
    }
}

/// Check if object is bool
pub export fn PyBool_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyBool_Type) 1 else 0;
}

/// Test if object is True singleton
pub export fn Py_IsTrue(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (obj == @as(*cpython.PyObject, @ptrCast(&_Py_TrueStruct.ob_base))) 1 else 0;
}

/// Test if object is False singleton
pub export fn Py_IsFalse(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (obj == @as(*cpython.PyObject, @ptrCast(&_Py_FalseStruct.ob_base))) 1 else 0;
}

/// Get the True singleton
pub export fn Py_True() callconv(.c) *cpython.PyObject {
    return @ptrCast(&_Py_TrueStruct.ob_base);
}

/// Get the False singleton
pub export fn Py_False() callconv(.c) *cpython.PyObject {
    return @ptrCast(&_Py_FalseStruct.ob_base);
}

/// Get True singleton as borrowed reference (macro in CPython)
pub export fn Py_RETURN_TRUE() callconv(.c) *cpython.PyObject {
    return @ptrCast(&_Py_TrueStruct.ob_base);
}

/// Get False singleton as borrowed reference (macro in CPython)
pub export fn Py_RETURN_FALSE() callconv(.c) *cpython.PyObject {
    return @ptrCast(&_Py_FalseStruct.ob_base);
}
