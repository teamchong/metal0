/// PyNone - The None singleton
///
/// Reference: cpython/Include/object.h

const std = @import("std");
const cpython = @import("cpython_object.zig");
const helpers = @import("optimization_helpers.zig");

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyNone_Type: cpython.PyTypeObject = helpers.makeTypeObject(.{
    .name = "NoneType",
    .basicsize = @sizeOf(cpython.PyObject),
    .flags = cpython.Py_TPFLAGS_DEFAULT,
    .doc = "NoneType()",
    .repr = none_repr,
});

// ============================================================================
// SINGLETON
// ============================================================================

/// _Py_NoneStruct - the singleton None value
pub export var _Py_NoneStruct: cpython.PyObject = .{
    .ob_refcnt = 1000000, // Immortal
    .ob_type = &PyNone_Type,
};

// ============================================================================
// API FUNCTIONS
// ============================================================================

/// Get the None singleton
pub export fn Py_None() callconv(.c) *cpython.PyObject {
    return &_Py_NoneStruct;
}

/// Check if object is None
pub export fn Py_IsNone(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (obj == &_Py_NoneStruct) 1 else 0;
}

/// Return None with incremented refcount (macro in CPython)
pub export fn Py_RETURN_NONE() callconv(.c) *cpython.PyObject {
    return &_Py_NoneStruct;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn none_repr(_: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const unicode = @import("cpython_unicode.zig");
    return unicode.PyUnicode_FromString("None");
}

// ============================================================================
// TESTS
// ============================================================================

test "None singleton" {
    try std.testing.expect(_Py_NoneStruct.ob_refcnt >= 1000000);
    try std.testing.expect(Py_IsNone(&_Py_NoneStruct) == 1);
}
