/// PyRangeObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Objects/rangeobject.c

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// rangeobject - EXACT CPython internal layout
pub const PyRangeObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    start: ?*cpython.PyObject,
    stop: ?*cpython.PyObject,
    step: ?*cpython.PyObject,
    length: ?*cpython.PyObject,
};

/// longrangeiterobject - for iterating over ranges
pub const PyLongRangeIterObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    start: ?*cpython.PyObject,
    step: ?*cpython.PyObject,
    len: ?*cpython.PyObject,
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub var PyRange_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "range",
    .tp_basicsize = @sizeOf(PyRangeObject),
    .tp_itemsize = 0,
    .tp_dealloc = range_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = range_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "range(stop) -> range object",
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

pub var PyRangeIter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "range_iterator",
    .tp_basicsize = @sizeOf(PyLongRangeIterObject),
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

pub var PyLongRangeIter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "longrange_iterator",
    .tp_basicsize = @sizeOf(PyLongRangeIterObject),
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

/// Type check
pub export fn PyRange_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyRange_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn range_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const r: *PyRangeObject = @ptrCast(@alignCast(obj));

    if (r.start) |s| s.ob_refcnt -= 1;
    if (r.stop) |s| s.ob_refcnt -= 1;
    if (r.step) |s| s.ob_refcnt -= 1;
    if (r.length) |s| s.ob_refcnt -= 1;

    allocator.destroy(r);
}

fn range_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const r: *PyRangeObject = @ptrCast(@alignCast(obj));
    _ = r;
    // TODO: Implement proper hash
    return 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyRangeObject layout" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(PyRangeObject));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyRangeObject, "start"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyRangeObject, "stop"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyRangeObject, "step"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(PyRangeObject, "length"));
}
