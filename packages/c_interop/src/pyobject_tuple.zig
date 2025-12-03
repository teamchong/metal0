/// Python tuple object implementation
///
/// Immutable fixed-size array - uses EXACT CPython memory layout
///
/// Reference: cpython/Include/cpython/tupleobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export type from cpython_object.zig for exact CPython layout
pub const PyTupleObject = cpython.PyTupleObject;

/// Sequence protocol for tuples
var tuple_as_sequence: cpython.PySequenceMethods = .{
    .sq_length = tuple_length,
    .sq_concat = tuple_concat,
    .sq_repeat = tuple_repeat,
    .sq_item = tuple_item,
    .sq_ass_item = null, // Immutable
    .sq_contains = null,
    .sq_inplace_concat = null,
    .sq_inplace_repeat = null,
};

/// PyTuple_Type - the 'tuple' type
pub var PyTuple_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "tuple",
    .tp_basicsize = @sizeOf(PyTupleObject),
    .tp_itemsize = @sizeOf(*cpython.PyObject),
    .tp_dealloc = tuple_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = tuple_repr,
    .tp_as_number = null,
    .tp_as_sequence = &tuple_as_sequence,
    .tp_as_mapping = null,
    .tp_hash = tuple_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_TUPLE_SUBCLASS,
    .tp_doc = "tuple() -> empty tuple",
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
// Core API Functions
// ============================================================================

/// Create new tuple
/// CPython layout: PyVarObject(24) + ob_hash(8) + ob_item[size]
pub export fn PyTuple_New(size: isize) callconv(.c) ?*cpython.PyObject {
    if (size < 0) return null;

    // Calculate total size: base struct + additional items (first item is in struct)
    const base_size = @sizeOf(PyTupleObject);
    const extra_items: usize = if (size > 0) @as(usize, @intCast(size)) - 1 else 0;
    const total_size = base_size + (extra_items * @sizeOf(*cpython.PyObject));

    const memory = allocator.alloc(u8, total_size) catch return null;

    const obj: *PyTupleObject = @ptrCast(@alignCast(memory.ptr));
    obj.ob_base.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_base.ob_type = &PyTuple_Type;
    obj.ob_base.ob_size = size;
    obj.ob_hash = -1; // Not computed yet

    // Initialize items to undefined (will be set later)
    if (size > 0) {
        const items_ptr: [*]*cpython.PyObject = @ptrCast(&obj.ob_item);
        @memset(items_ptr[0..@intCast(size)], undefined);
    }

    return @ptrCast(&obj.ob_base.ob_base);
}

/// Get tuple size
export fn PyTuple_Size(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyTuple_Check(obj) == 0) return -1;

    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    return tuple_obj.ob_base.ob_size;
}

/// Get item at index (borrowed reference)
export fn PyTuple_GetItem(obj: *cpython.PyObject, idx: isize) callconv(.c) ?*cpython.PyObject {
    if (PyTuple_Check(obj) == 0) return null;

    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));

    if (idx < 0 or idx >= tuple_obj.ob_base.ob_size) return null;

    const items_ptr: [*]*cpython.PyObject = @ptrCast(&tuple_obj.ob_item);
    return items_ptr[@intCast(idx)];
}

/// Set item at index (steals reference, only for tuple creation)
pub export fn PyTuple_SetItem(obj: *cpython.PyObject, idx: isize, item: *cpython.PyObject) callconv(.c) c_int {
    if (PyTuple_Check(obj) == 0) return -1;

    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));

    if (idx < 0 or idx >= tuple_obj.ob_base.ob_size) return -1;

    // Steals reference - no INCREF
    const items_ptr: [*]*cpython.PyObject = @ptrCast(&tuple_obj.ob_item);
    items_ptr[@intCast(idx)] = item;
    return 0;
}

/// Get slice
export fn PyTuple_GetSlice(obj: *cpython.PyObject, low: isize, high: isize) callconv(.c) ?*cpython.PyObject {
    if (PyTuple_Check(obj) == 0) return null;

    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));

    var real_low = low;
    var real_high = high;

    if (real_low < 0) real_low = 0;
    if (real_high > tuple_obj.ob_base.ob_size) real_high = tuple_obj.ob_base.ob_size;
    if (real_low >= real_high) return PyTuple_New(0);

    const slice_len = real_high - real_low;
    const new_tuple = PyTuple_New(slice_len);

    if (new_tuple) |new_obj| {
        const new_tuple_obj: *PyTupleObject = @ptrCast(@alignCast(new_obj));
        const old_items: [*]*cpython.PyObject = @ptrCast(&tuple_obj.ob_item);
        const new_items: [*]*cpython.PyObject = @ptrCast(&new_tuple_obj.ob_item);

        var i: isize = 0;
        while (i < slice_len) : (i += 1) {
            const item = old_items[@intCast(real_low + i)];
            item.ob_refcnt += 1;
            new_items[@intCast(i)] = item;
        }
    }

    return new_tuple;
}

/// Pack arguments into tuple
export fn PyTuple_Pack(n: isize, ...) callconv(.c) ?*cpython.PyObject {
    if (n < 0) return null;

    const tuple = PyTuple_New(n);
    if (tuple == null) return null;

    // TODO: Extract varargs and fill tuple
    // For now just return empty tuple

    return tuple;
}

/// Type check
pub export fn PyTuple_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return if ((flags & cpython.Py_TPFLAGS_TUPLE_SUBCLASS) != 0) 1 else 0;
}

/// Exact type check
export fn PyTuple_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyTuple_Type) 1 else 0;
}

// ============================================================================
// Internal Functions
// ============================================================================

fn tuple_length(obj: *cpython.PyObject) callconv(.c) isize {
    return PyTuple_Size(obj);
}

fn tuple_item(obj: *cpython.PyObject, idx: isize) callconv(.c) ?*cpython.PyObject {
    const item = PyTuple_GetItem(obj, idx);
    if (item) |i| {
        i.ob_refcnt += 1; // Return new reference
    }
    return item;
}

fn tuple_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyTuple_Check(a) == 0 or PyTuple_Check(b) == 0) return null;

    const a_tuple: *PyTupleObject = @ptrCast(@alignCast(a));
    const b_tuple: *PyTupleObject = @ptrCast(@alignCast(b));

    const new_size = a_tuple.ob_base.ob_size + b_tuple.ob_base.ob_size;
    const new_tuple = PyTuple_New(new_size);

    if (new_tuple) |new_obj| {
        const new_tuple_obj: *PyTupleObject = @ptrCast(@alignCast(new_obj));
        const a_items: [*]*cpython.PyObject = @ptrCast(&a_tuple.ob_item);
        const b_items: [*]*cpython.PyObject = @ptrCast(&b_tuple.ob_item);
        const new_items: [*]*cpython.PyObject = @ptrCast(&new_tuple_obj.ob_item);

        // Copy from a
        var i: usize = 0;
        while (i < @as(usize, @intCast(a_tuple.ob_base.ob_size))) : (i += 1) {
            const item = a_items[i];
            item.ob_refcnt += 1;
            new_items[i] = item;
        }

        // Copy from b
        i = 0;
        const offset: usize = @intCast(a_tuple.ob_base.ob_size);
        while (i < @as(usize, @intCast(b_tuple.ob_base.ob_size))) : (i += 1) {
            const item = b_items[i];
            item.ob_refcnt += 1;
            new_items[offset + i] = item;
        }
    }

    return new_tuple;
}

fn tuple_repeat(obj: *cpython.PyObject, n: isize) callconv(.c) ?*cpython.PyObject {
    if (n <= 0) return PyTuple_New(0);

    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    const new_size = tuple_obj.ob_base.ob_size * n;

    const new_tuple = PyTuple_New(new_size);

    if (new_tuple) |new_obj| {
        const new_tuple_obj: *PyTupleObject = @ptrCast(@alignCast(new_obj));
        const old_items: [*]*cpython.PyObject = @ptrCast(&tuple_obj.ob_item);
        const new_items: [*]*cpython.PyObject = @ptrCast(&new_tuple_obj.ob_item);
        const item_count: usize = @intCast(tuple_obj.ob_base.ob_size);

        var rep: usize = 0;
        while (rep < @as(usize, @intCast(n))) : (rep += 1) {
            var i: usize = 0;
            while (i < item_count) : (i += 1) {
                const item = old_items[i];
                item.ob_refcnt += 1;
                new_items[rep * item_count + i] = item;
            }
        }
    }

    return new_tuple;
}

fn tuple_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    const items_ptr: [*]*cpython.PyObject = @ptrCast(&tuple_obj.ob_item);

    // Decref all items
    var i: usize = 0;
    while (i < @as(usize, @intCast(tuple_obj.ob_base.ob_size))) : (i += 1) {
        items_ptr[i].ob_refcnt -= 1;
        // TODO: Check if refcnt == 0 and deallocate
    }

    // Free entire block (struct + items)
    const base_size = @sizeOf(PyTupleObject);
    const extra_items: usize = if (tuple_obj.ob_base.ob_size > 0) @as(usize, @intCast(tuple_obj.ob_base.ob_size)) - 1 else 0;
    const total_size = base_size + (extra_items * @sizeOf(*cpython.PyObject));
    const memory: []align(@alignOf(PyTupleObject)) u8 = @as([*]align(@alignOf(PyTupleObject)) u8, @ptrCast(@alignCast(tuple_obj)))[0..total_size];
    allocator.free(memory);
}

fn tuple_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    return null;
}

fn tuple_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));

    // Return cached hash if available
    if (tuple_obj.ob_hash != -1) {
        return tuple_obj.ob_hash;
    }

    // Compute hash - combine item hashes
    const items_ptr: [*]*cpython.PyObject = @ptrCast(&tuple_obj.ob_item);
    var hash: u64 = 0x345678;
    var i: usize = 0;

    while (i < @as(usize, @intCast(tuple_obj.ob_base.ob_size))) : (i += 1) {
        const item = items_ptr[i];
        const item_hash: u64 = @intCast(@intFromPtr(item));
        hash = (hash ^ item_hash) *% 1000003;
    }

    // Cache the hash
    tuple_obj.ob_hash = @intCast(hash);
    return tuple_obj.ob_hash;
}

// ============================================================================
// Tests
// ============================================================================

test "PyTupleObject layout matches CPython" {
    // PyTupleObject: ob_base(24) + ob_hash(8) + ob_item[1](8) = 40 bytes
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyTupleObject, "ob_hash"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyTupleObject, "ob_item"));
}

test "tuple exports" {
    _ = PyTuple_New;
    _ = PyTuple_GetItem;
    _ = PyTuple_SetItem;
}
