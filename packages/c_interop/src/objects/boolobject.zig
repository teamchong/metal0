/// PyBool - CPython memory layout (version-aware)
///
/// Bool is a subclass of int (PyLongObject). Py_True and Py_False are singletons.
/// Layout differs between Python 3.12+ (lv_tag) and 3.10-3.11 (ob_size).
///
/// Reference: cpython/Include/boolobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");
const helpers = @import("../optimization_helpers.zig");
const version = @import("../include/version.zig");

// Bool is just a PyLongObject with value 0 or 1
pub const PyBoolObject = cpython.PyLongObject;

// ============================================================================
// SINGLETONS - Py_True and Py_False (version-dependent layout)
// ============================================================================

/// _Py_FalseStruct - the singleton False value
pub export var _Py_FalseStruct: cpython.PyLongObject = if (version.hasLvTag(cpython.PYTHON_VERSION))
    // Python 3.12+: lv_tag encoding
    .{
        .ob_base = .{
            .ob_refcnt = 1000000, // Immortal
            .ob_type = &PyBool_Type,
        },
        .long_value = .{
            .lv_tag = 1, // zero = sign mask 1
            .ob_digit = .{0},
        },
    }
else
    // Python 3.10-3.11: ob_size encoding
    .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1000000, // Immortal
                .ob_type = &PyBool_Type,
            },
            .ob_size = 0,
        },
        .ob_digit = .{0},
    };

/// _Py_TrueStruct - the singleton True value
pub export var _Py_TrueStruct: cpython.PyLongObject = if (version.hasLvTag(cpython.PYTHON_VERSION))
    // Python 3.12+: lv_tag encoding (1 digit, positive sign = (1 << 3) | 0 = 8)
    .{
        .ob_base = .{
            .ob_refcnt = 1000000, // Immortal
            .ob_type = &PyBool_Type,
        },
        .long_value = .{
            .lv_tag = (1 << 3) | 0, // 1 digit, non-negative
            .ob_digit = .{1},
        },
    }
else
    // Python 3.10-3.11: ob_size encoding
    .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1000000, // Immortal
                .ob_type = &PyBool_Type,
            },
            .ob_size = 1,
        },
        .ob_digit = .{1},
    };

/// Py_FalseStruct - alias for _Py_FalseStruct (some extensions use this)
pub export const Py_FalseStruct: *cpython.PyLongObject = &_Py_FalseStruct;

/// Py_TrueStruct - alias for _Py_TrueStruct (some extensions use this)
pub export const Py_TrueStruct: *cpython.PyLongObject = &_Py_TrueStruct;

// ============================================================================
// TYPE OBJECT
// ============================================================================

/// PyBool_Type - exported as C symbol for C extensions
pub export var PyBool_Type: cpython.PyTypeObject = helpers.makeTypeObject(.{
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
