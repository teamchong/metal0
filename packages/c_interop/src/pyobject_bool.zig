/// PyBool - EXACT CPython 3.12 memory layout
///
/// Bool is a subclass of int (PyLongObject). Py_True and Py_False are singletons.
///
/// Reference: cpython/Include/boolobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

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

pub var PyBool_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "bool",
    .tp_basicsize = @sizeOf(cpython.PyLongObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_LONG_SUBCLASS,
    .tp_doc = "bool(x) -> bool",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null, // Should be &PyLong_Type
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

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
