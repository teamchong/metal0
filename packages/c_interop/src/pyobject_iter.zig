/// PySeqIterObject / PyCallIterObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/iterobject.h, cpython/Objects/iterobject.c

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// seqiterobject - sequence iterator
pub const PySeqIterObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    it_index: isize,
    it_seq: ?*cpython.PyObject, // Sequence being iterated
};

/// calliterobject - callable iterator
pub const PyCallIterObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    it_callable: ?*cpython.PyObject, // Callable to call
    it_sentinel: ?*cpython.PyObject, // Sentinel value to stop iteration
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub var PySeqIter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "iterator",
    .tp_basicsize = @sizeOf(PySeqIterObject),
    .tp_itemsize = 0,
    .tp_dealloc = seqiter_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = seqiter_next,
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

pub var PyCallIter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "callable_iterator",
    .tp_basicsize = @sizeOf(PyCallIterObject),
    .tp_itemsize = 0,
    .tp_dealloc = calliter_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
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

/// Create sequence iterator
pub export fn PySeqIter_New(seq: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PySeqIterObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PySeqIter_Type;
    obj.it_index = 0;
    obj.it_seq = seq;
    seq.ob_refcnt += 1;

    return @ptrCast(&obj.ob_base);
}

/// Create callable iterator
pub export fn PyCallIter_New(callable: *cpython.PyObject, sentinel: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyCallIterObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyCallIter_Type;
    obj.it_callable = callable;
    obj.it_sentinel = sentinel;
    callable.ob_refcnt += 1;
    sentinel.ob_refcnt += 1;

    return @ptrCast(&obj.ob_base);
}

/// Type checks
pub export fn PySeqIter_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PySeqIter_Type) 1 else 0;
}

pub export fn PyCallIter_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCallIter_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn seqiter_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const it: *PySeqIterObject = @ptrCast(@alignCast(obj));
    if (it.it_seq) |seq| seq.ob_refcnt -= 1;
    allocator.destroy(it);
}

fn seqiter_next(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const it: *PySeqIterObject = @ptrCast(@alignCast(obj));
    _ = it;
    // TODO: Implement iteration
    return null;
}

fn calliter_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const it: *PyCallIterObject = @ptrCast(@alignCast(obj));
    if (it.it_callable) |c| c.ob_refcnt -= 1;
    if (it.it_sentinel) |s| s.ob_refcnt -= 1;
    allocator.destroy(it);
}

// ============================================================================
// TESTS
// ============================================================================

test "PySeqIterObject layout" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(PySeqIterObject));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PySeqIterObject, "it_index"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PySeqIterObject, "it_seq"));
}

test "PyCallIterObject layout" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(PyCallIterObject));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyCallIterObject, "it_callable"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyCallIterObject, "it_sentinel"));
}
