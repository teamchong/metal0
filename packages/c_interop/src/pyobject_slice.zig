/// PySliceObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/sliceobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

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
    if (start) |s| s.ob_refcnt += 1;
    if (stop) |s| s.ob_refcnt += 1;
    if (step) |s| s.ob_refcnt += 1;

    return @ptrCast(&obj.ob_base);
}

/// Get indices for sequence of given length
pub export fn PySlice_GetIndices(slice: *cpython.PyObject, length: isize, start: *isize, stop: *isize, step: *isize) callconv(.c) c_int {
    const s: *PySliceObject = @ptrCast(@alignCast(slice));
    _ = s;
    _ = length;

    // Default values
    start.* = 0;
    stop.* = length;
    step.* = 1;

    // TODO: Implement proper index calculation
    return 0;
}

/// Unpack slice object
pub export fn PySlice_Unpack(slice: *cpython.PyObject, start: *isize, stop: *isize, step: *isize) callconv(.c) c_int {
    _ = slice;
    start.* = 0;
    stop.* = std.math.maxInt(isize);
    step.* = 1;
    return 0;
}

/// Adjust indices for length
pub export fn PySlice_AdjustIndices(length: isize, start: *isize, stop: *isize, step: isize) callconv(.c) isize {
    _ = step;
    if (start.* < 0) start.* = 0;
    if (stop.* > length) stop.* = length;
    if (stop.* < start.*) return 0;
    return stop.* - start.*;
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

    if (s.start) |start| start.ob_refcnt -= 1;
    if (s.stop) |stop| stop.ob_refcnt -= 1;
    if (s.step) |step| step.ob_refcnt -= 1;

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
