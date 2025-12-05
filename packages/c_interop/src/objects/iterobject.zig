/// PySeqIterObject / PyCallIterObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/iterobject.h, cpython/Objects/iterobject.c

const std = @import("std");
const cpython = @import("../include/object.zig");
const traits = @import("typetraits.zig");

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
    .tp_iternext = calliter_next,
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
    _ = traits.incref(seq);

    return @ptrCast(&obj.ob_base);
}

/// Create callable iterator
pub export fn PyCallIter_New(callable: *cpython.PyObject, sentinel: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyCallIterObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyCallIter_Type;
    obj.it_callable = callable;
    obj.it_sentinel = sentinel;
    _ = traits.incref(callable);
    _ = traits.incref(sentinel);

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
    if (it.it_seq) |seq| traits.decref(seq);
    allocator.destroy(it);
}

fn seqiter_next(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const it: *PySeqIterObject = @ptrCast(@alignCast(obj));
    const seq = it.it_seq orelse return null;

    const type_obj = cpython.Py_TYPE(seq);

    // Try sequence protocol (sq_item)
    if (type_obj.tp_as_sequence) |seq_methods| {
        if (seq_methods.sq_item) |getitem| {
            const result = getitem(seq, it.it_index);
            if (result) |item| {
                it.it_index += 1;
                return item;
            }
            // IndexError/StopIteration - clear and stop
            return null;
        }
    }

    // Fallback: try mapping protocol (mp_subscript) with int key
    if (type_obj.tp_as_mapping) |map_methods| {
        if (map_methods.mp_subscript) |getitem| {
            const long_mod = @import("longobject.zig");
            const idx_obj = long_mod.PyLong_FromLong(@intCast(it.it_index)) orelse return null;
            defer traits.decref(idx_obj);

            const result = getitem(seq, idx_obj);
            if (result) |item| {
                it.it_index += 1;
                return item;
            }
            return null;
        }
    }

    return null;
}

fn calliter_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const it: *PyCallIterObject = @ptrCast(@alignCast(obj));
    if (it.it_callable) |c| traits.decref(c);
    if (it.it_sentinel) |s| traits.decref(s);
    allocator.destroy(it);
}

fn calliter_next(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const it: *PyCallIterObject = @ptrCast(@alignCast(obj));
    const callable = it.it_callable orelse return null;
    const sentinel = it.it_sentinel orelse return null;

    const type_obj = cpython.Py_TYPE(callable);
    if (type_obj.tp_call) |call_func| {
        // Call with empty args tuple
        var empty_tuple = cpython.PyObject{ .ob_refcnt = 1, .ob_type = undefined };
        const result = call_func(callable, &empty_tuple, null) orelse return null;

        // Check if result equals sentinel
        if (result == sentinel) {
            traits.decref(result);
            it.it_callable = null; // Exhaust iterator
            return null;
        }

        return result;
    }

    return null;
}

// ============================================================================
// GENERIC ITERATOR API
// ============================================================================

/// Get next item from any iterator
///
/// CPython: PyObject* PyIter_Next(PyObject *iter)
/// Returns: Next item or null (check PyErr_Occurred for error vs StopIteration)
pub export fn PyIter_Next(iter: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(iter);
    if (type_obj.tp_iternext) |next_func| {
        return next_func(iter);
    }
    return null;
}

/// Check if object is an iterator
///
/// CPython: int PyIter_Check(PyObject *obj)
/// Returns: 1 if iterator, 0 if not
pub export fn PyIter_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj.tp_iternext != null) 1 else 0;
}

/// Get iterator for object (calls __iter__)
///
/// CPython: PyObject* PyObject_GetIter(PyObject *obj)
/// Returns: Iterator object or null on error
pub export fn PyObject_GetIter(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    // Try tp_iter first
    if (type_obj.tp_iter) |iter_func| {
        return iter_func(obj);
    }

    // Fallback: create sequence iterator if object supports sequence protocol
    if (type_obj.tp_as_sequence) |seq_methods| {
        if (seq_methods.sq_item != null) {
            return PySeqIter_New(obj);
        }
    }

    return null;
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
