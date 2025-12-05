/// PySliceObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/sliceobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");
const traits = @import("typetraits.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// PySliceObject - EXACT CPython layout
pub const PySliceObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    start: ?*cpython.PyObject, // not NULL
    stop: ?*cpython.PyObject, // not NULL
    step: ?*cpython.PyObject, // not NULL
};

// ============================================================================
// ELLIPSIS SINGLETON
// ============================================================================

pub export var _Py_EllipsisObject: cpython.PyObject = .{
    .ob_refcnt = 1000000, // Immortal
    .ob_type = &PyEllipsis_Type,
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub var PySlice_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "slice",
    .tp_basicsize = @sizeOf(PySliceObject),
    .tp_itemsize = 0,
    .tp_dealloc = slice_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null, // Unhashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "slice(stop) or slice(start, stop[, step])",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
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

pub var PyEllipsis_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "ellipsis",
    .tp_basicsize = @sizeOf(cpython.PyObject),
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
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

/// Create new slice object
pub export fn PySlice_New(start: ?*cpython.PyObject, stop: ?*cpython.PyObject, step: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PySliceObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PySlice_Type;

    // Use Py_None for NULL values
    obj.start = start;
    obj.stop = stop;
    obj.step = step;

    // INCREF
    if (start) |s| _ = traits.incref(s);
    if (stop) |s| _ = traits.incref(s);
    if (step) |s| _ = traits.incref(s);

    return @ptrCast(&obj.ob_base);
}

/// Get indices for sequence of given length
pub export fn PySlice_GetIndices(slice: *cpython.PyObject, length: isize, start: *isize, stop: *isize, step: *isize) callconv(.c) c_int {
    const s: *PySliceObject = @ptrCast(@alignCast(slice));
    const pylong = @import("longobject.zig");

    // Extract step (default 1)
    if (s.step) |step_obj| {
        if (pylong.PyLong_Check(step_obj) != 0) {
            step.* = pylong.PyLong_AsLong(step_obj);
            if (step.* == 0) return -1; // Zero step is invalid
        } else {
            step.* = 1;
        }
    } else {
        step.* = 1;
    }

    // Extract start
    if (s.start) |start_obj| {
        if (pylong.PyLong_Check(start_obj) != 0) {
            start.* = pylong.PyLong_AsLong(start_obj);
            // Handle negative indices
            if (start.* < 0) {
                start.* += length;
                if (start.* < 0) start.* = if (step.* < 0) -1 else 0;
            } else if (start.* >= length) {
                start.* = if (step.* < 0) length - 1 else length;
            }
        } else {
            start.* = if (step.* < 0) length - 1 else 0;
        }
    } else {
        start.* = if (step.* < 0) length - 1 else 0;
    }

    // Extract stop
    if (s.stop) |stop_obj| {
        if (pylong.PyLong_Check(stop_obj) != 0) {
            stop.* = pylong.PyLong_AsLong(stop_obj);
            // Handle negative indices
            if (stop.* < 0) {
                stop.* += length;
                if (stop.* < 0) stop.* = if (step.* < 0) -1 else 0;
            } else if (stop.* >= length) {
                stop.* = if (step.* < 0) length - 1 else length;
            }
        } else {
            stop.* = if (step.* < 0) -1 else length;
        }
    } else {
        stop.* = if (step.* < 0) -1 else length;
    }

    return 0;
}

/// Unpack slice object into raw values (before adjusting for length)
pub export fn PySlice_Unpack(slice: *cpython.PyObject, start: *isize, stop: *isize, step: *isize) callconv(.c) c_int {
    const s: *PySliceObject = @ptrCast(@alignCast(slice));
    const pylong = @import("longobject.zig");

    // Extract step
    if (s.step) |step_obj| {
        if (pylong.PyLong_Check(step_obj) != 0) {
            step.* = pylong.PyLong_AsLong(step_obj);
            if (step.* == 0) return -1;
        } else {
            step.* = 1;
        }
    } else {
        step.* = 1;
    }

    // Extract start (use placeholder for None)
    if (s.start) |start_obj| {
        if (pylong.PyLong_Check(start_obj) != 0) {
            start.* = pylong.PyLong_AsLong(start_obj);
        } else {
            start.* = if (step.* < 0) std.math.maxInt(isize) else 0;
        }
    } else {
        start.* = if (step.* < 0) std.math.maxInt(isize) else 0;
    }

    // Extract stop
    if (s.stop) |stop_obj| {
        if (pylong.PyLong_Check(stop_obj) != 0) {
            stop.* = pylong.PyLong_AsLong(stop_obj);
        } else {
            stop.* = if (step.* < 0) std.math.minInt(isize) else std.math.maxInt(isize);
        }
    } else {
        stop.* = if (step.* < 0) std.math.minInt(isize) else std.math.maxInt(isize);
    }

    return 0;
}

/// Adjust indices for length and return slice length
pub export fn PySlice_AdjustIndices(length: isize, start: *isize, stop: *isize, step: isize) callconv(.c) isize {
    // Adjust start
    if (start.* < 0) {
        start.* += length;
        if (start.* < 0) {
            start.* = if (step < 0) -1 else 0;
        }
    } else if (start.* >= length) {
        start.* = if (step < 0) length - 1 else length;
    }

    // Adjust stop
    if (stop.* < 0) {
        stop.* += length;
        if (stop.* < 0) {
            stop.* = if (step < 0) -1 else 0;
        }
    } else if (stop.* >= length) {
        stop.* = if (step < 0) length - 1 else length;
    }

    // Calculate slice length
    if (step < 0) {
        if (stop.* < start.*) {
            return @divFloor((start.* - stop.* - 1), (-step)) + 1;
        }
    } else {
        if (start.* < stop.*) {
            return @divFloor((stop.* - start.* - 1), step) + 1;
        }
    }
    return 0;
}

/// Type check
pub export fn PySlice_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PySlice_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn slice_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const s: *PySliceObject = @ptrCast(@alignCast(obj));

    if (s.start) |start| traits.decref(start);
    if (s.stop) |stop| traits.decref(stop);
    if (s.step) |step| traits.decref(step);

    allocator.destroy(s);
}

// ============================================================================
// TESTS
// ============================================================================

test "PySliceObject layout" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(PySliceObject));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PySliceObject, "start"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PySliceObject, "stop"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PySliceObject, "step"));
}
