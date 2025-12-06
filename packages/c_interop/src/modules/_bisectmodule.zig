/// _bisect Module - Binary Search C Accelerator
///
/// Implements CPython's Modules/_bisectmodule.c
/// Provides C acceleration for bisect module (binary search algorithms)
///
/// Reference: cpython/Modules/_bisectmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

// ============================================================================
// BINARY SEARCH FUNCTIONS
// ============================================================================

/// Find insertion point in sorted list using bisect_right algorithm
/// Returns index where x should be inserted to keep list sorted
pub export fn _bisect_bisect_right(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const pylong = @import("../objects/longobject.zig");
    const object_mod = @import("../objects/object.zig");

    // Get arguments: (a, x, lo=0, hi=len(a))
    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 2) return null;

    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const x = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    // Get list length
    var hi: isize = undefined;
    if (list.PyList_Check(a) != 0) {
        hi = list.PyList_Size(a);
    } else {
        // Use len() for other sequences
        hi = 0; // Simplified
    }

    var lo: isize = 0;

    // Optional lo argument
    if (nargs >= 3) {
        if (tuple.PyTuple_GetItem(args.?, 2)) |lo_obj| {
            lo = pylong.PyLong_AsLongLong(lo_obj);
        }
    }

    // Optional hi argument
    if (nargs >= 4) {
        if (tuple.PyTuple_GetItem(args.?, 3)) |hi_obj| {
            hi = pylong.PyLong_AsLongLong(hi_obj);
        }
    }

    // Binary search
    while (lo < hi) {
        const mid = lo + @divFloor(hi - lo, 2);
        const mid_val = list.PyList_GetItem(a, mid) orelse break;

        // Compare: if x < mid_val then hi = mid, else lo = mid + 1
        const cmp = object_mod.PyObject_RichCompareBool(x, mid_val, object_mod.Py_LT);
        if (cmp < 0) break; // Error

        if (cmp != 0) {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }

    return pylong.PyLong_FromLongLong(lo);
}

/// Find insertion point using bisect_left algorithm
pub export fn _bisect_bisect_left(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const pylong = @import("../objects/longobject.zig");
    const object_mod = @import("../objects/object.zig");

    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 2) return null;

    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const x = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    var hi: isize = undefined;
    if (list.PyList_Check(a) != 0) {
        hi = list.PyList_Size(a);
    } else {
        hi = 0;
    }

    var lo: isize = 0;

    if (nargs >= 3) {
        if (tuple.PyTuple_GetItem(args.?, 2)) |lo_obj| {
            lo = pylong.PyLong_AsLongLong(lo_obj);
        }
    }

    if (nargs >= 4) {
        if (tuple.PyTuple_GetItem(args.?, 3)) |hi_obj| {
            hi = pylong.PyLong_AsLongLong(hi_obj);
        }
    }

    // Binary search
    while (lo < hi) {
        const mid = lo + @divFloor(hi - lo, 2);
        const mid_val = list.PyList_GetItem(a, mid) orelse break;

        // Compare: if mid_val < x then lo = mid + 1, else hi = mid
        const cmp = object_mod.PyObject_RichCompareBool(mid_val, x, object_mod.Py_LT);
        if (cmp < 0) break;

        if (cmp != 0) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }

    return pylong.PyLong_FromLongLong(lo);
}

/// Insert x into sorted list a using bisect_right
pub export fn _bisect_insort_right(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const pylong = @import("../objects/longobject.zig");
    const object_mod = @import("../objects/object.zig");

    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 2) return null;

    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const x = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    // Find insertion point
    const idx_obj = _bisect_bisect_right(null, args) orelse return null;
    const idx = pylong.PyLong_AsLongLong(idx_obj);
    idx_obj.ob_refcnt -= 1;

    // Insert
    if (list.PyList_Check(a) != 0) {
        _ = list.PyList_Insert(a, idx, x);
    }

    return &object_mod._Py_NoneStruct;
}

/// Insert x into sorted list a using bisect_left
pub export fn _bisect_insort_left(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const pylong = @import("../objects/longobject.zig");
    const object_mod = @import("../objects/object.zig");

    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 2) return null;

    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const x = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    const idx_obj = _bisect_bisect_left(null, args) orelse return null;
    const idx = pylong.PyLong_AsLongLong(idx_obj);
    idx_obj.ob_refcnt -= 1;

    if (list.PyList_Check(a) != 0) {
        _ = list.PyList_Insert(a, idx, x);
    }

    return &object_mod._Py_NoneStruct;
}

// ============================================================================
// MODULE DEFINITION
// ============================================================================

const bisect_methods = [_]cpython.PyMethodDef{
    .{
        .ml_name = "bisect_right",
        .ml_meth = @ptrCast(&_bisect_bisect_right),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Return the index where to insert item x in list a, assuming a is sorted.",
    },
    .{
        .ml_name = "bisect_left",
        .ml_meth = @ptrCast(&_bisect_bisect_left),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Return the index where to insert item x in list a, assuming a is sorted.",
    },
    .{
        .ml_name = "insort_right",
        .ml_meth = @ptrCast(&_bisect_insort_right),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Insert item x in list a, and keep it sorted assuming a is sorted.",
    },
    .{
        .ml_name = "insort_left",
        .ml_meth = @ptrCast(&_bisect_insort_left),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Insert item x in list a, and keep it sorted assuming a is sorted.",
    },
    .{
        .ml_name = "bisect",
        .ml_meth = @ptrCast(&_bisect_bisect_right),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Alias for bisect_right().",
    },
    .{
        .ml_name = "insort",
        .ml_meth = @ptrCast(&_bisect_insort_right),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Alias for insort_right().",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var _bisectmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_bisect",
    .m_doc = "C implementation of bisection algorithms.",
    .m_size = -1,
    .m_methods = @constCast(&bisect_methods),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__bisect() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_bisectmodule);
}
