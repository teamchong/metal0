/// Python tuple object implementation
///
/// Immutable fixed-size array

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// PyTupleObject - Python tuple (immutable array)
pub const PyTupleObject = extern struct {
    ob_base: cpython.PyVarObject,
    ob_item: [*]*cpython.PyObject,  // Fixed-size array (allocated inline after struct)
};

// Forward declarations
fn tuple_dealloc(obj: *cpython.PyObject) callconv(.c) void;
fn tuple_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn tuple_hash(obj: *cpython.PyObject) callconv(.c) isize;
fn tuple_length(obj: *cpython.PyObject) callconv(.c) isize;
fn tuple_item(obj: *cpython.PyObject, idx: isize) callconv(.c) ?*cpython.PyObject;
fn tuple_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn tuple_repeat(obj: *cpython.PyObject, n: isize) callconv(.c) ?*cpython.PyObject;

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
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "tuple",
    .tp_basicsize = @sizeOf(PyTupleObject),
    .tp_itemsize = @sizeOf(*cpython.PyObject),
    .tp_dealloc = tuple_dealloc,
    .tp_repr = tuple_repr,
    .tp_as_sequence = &tuple_as_sequence,
    .tp_hash = tuple_hash,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "tuple() -> empty tuple",
    // Other slots null
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_as_number = null,
    .tp_as_mapping = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
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
};

// ============================================================================
// Core API Functions
// ============================================================================

/// Create new tuple
export fn PyTuple_New(size: isize) callconv(.c) ?*cpython.PyObject {
    if (size < 0) return null;
    
    // Allocate struct + items in one block
    const total_size = @sizeOf(PyTupleObject) + (@as(usize, @intCast(size)) * @sizeOf(*cpython.PyObject));
    const memory = allocator.alignedAlloc(u8, @alignOf(PyTupleObject), total_size) catch return null;
    
    const obj = @as(*PyTupleObject, @ptrCast(@alignCast(memory.ptr)));
    obj.ob_base.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_base.ob_type = &PyTuple_Type;
    obj.ob_base.ob_size = size;
    
    // Items start right after struct
    if (size > 0) {
        const items_ptr = @as([*]u8, @ptrCast(obj)) + @sizeOf(PyTupleObject);
        obj.ob_item = @ptrCast(@alignCast(items_ptr));
        
        // Initialize to undefined (will be set later)
        @memset(obj.ob_item[0..@intCast(size)], undefined);
    } else {
        obj.ob_item = undefined; // Not used for empty tuple
    }
    
    return @ptrCast(&obj.ob_base.ob_base);
}

/// Get tuple size
export fn PyTuple_Size(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyTuple_Check(obj) == 0) return -1;
    
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    return tuple_obj.ob_base.ob_size;
}

/// Get item at index (borrowed reference)
export fn PyTuple_GetItem(obj: *cpython.PyObject, idx: isize) callconv(.c) ?*cpython.PyObject {
    if (PyTuple_Check(obj) == 0) return null;
    
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    
    if (idx < 0 or idx >= tuple_obj.ob_base.ob_size) return null;
    
    return tuple_obj.ob_item[@intCast(idx)];
}

/// Set item at index (steals reference, only for tuple creation)
export fn PyTuple_SetItem(obj: *cpython.PyObject, idx: isize, item: *cpython.PyObject) callconv(.c) c_int {
    if (PyTuple_Check(obj) == 0) return -1;
    
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    
    if (idx < 0 or idx >= tuple_obj.ob_base.ob_size) return -1;
    
    // Steals reference - no INCREF
    tuple_obj.ob_item[@intCast(idx)] = item;
    return 0;
}

/// Get slice
export fn PyTuple_GetSlice(obj: *cpython.PyObject, low: isize, high: isize) callconv(.c) ?*cpython.PyObject {
    if (PyTuple_Check(obj) == 0) return null;
    
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    
    var real_low = low;
    var real_high = high;
    
    if (real_low < 0) real_low = 0;
    if (real_high > tuple_obj.ob_base.ob_size) real_high = tuple_obj.ob_base.ob_size;
    if (real_low >= real_high) return PyTuple_New(0);
    
    const slice_len = real_high - real_low;
    const new_tuple = PyTuple_New(slice_len);
    
    if (new_tuple) |new_obj| {
        const new_tuple_obj = @as(*PyTupleObject, @ptrCast(new_obj));
        
        var i: isize = 0;
        while (i < slice_len) : (i += 1) {
            const item = tuple_obj.ob_item[@intCast(real_low + i)];
            item.ob_refcnt += 1;
            new_tuple_obj.ob_item[@intCast(i)] = item;
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
export fn PyTuple_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyTuple_Type) 1 else 0;
}

/// Exact type check
export fn PyTuple_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyTuple_Type) 1 else 0;
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
    
    const a_tuple = @as(*PyTupleObject, @ptrCast(a));
    const b_tuple = @as(*PyTupleObject, @ptrCast(b));
    
    const new_size = a_tuple.ob_base.ob_size + b_tuple.ob_base.ob_size;
    const new_tuple = PyTuple_New(new_size);
    
    if (new_tuple) |new_obj| {
        const new_tuple_obj = @as(*PyTupleObject, @ptrCast(new_obj));
        
        // Copy from a
        var i: usize = 0;
        while (i < a_tuple.ob_base.ob_size) : (i += 1) {
            const item = a_tuple.ob_item[i];
            item.ob_refcnt += 1;
            new_tuple_obj.ob_item[i] = item;
        }
        
        // Copy from b
        i = 0;
        while (i < b_tuple.ob_base.ob_size) : (i += 1) {
            const item = b_tuple.ob_item[i];
            item.ob_refcnt += 1;
            new_tuple_obj.ob_item[@intCast(a_tuple.ob_base.ob_size) + i] = item;
        }
    }
    
    return new_tuple;
}

fn tuple_repeat(obj: *cpython.PyObject, n: isize) callconv(.c) ?*cpython.PyObject {
    if (n <= 0) return PyTuple_New(0);
    
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    const new_size = tuple_obj.ob_base.ob_size * n;
    
    const new_tuple = PyTuple_New(new_size);
    
    if (new_tuple) |new_obj| {
        const new_tuple_obj = @as(*PyTupleObject, @ptrCast(new_obj));
        
        var rep: usize = 0;
        while (rep < n) : (rep += 1) {
            var i: usize = 0;
            while (i < tuple_obj.ob_base.ob_size) : (i += 1) {
                const item = tuple_obj.ob_item[i];
                item.ob_refcnt += 1;
                new_tuple_obj.ob_item[rep * @as(usize, @intCast(tuple_obj.ob_base.ob_size)) + i] = item;
            }
        }
    }
    
    return new_tuple;
}

fn tuple_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    
    // Decref all items
    var i: usize = 0;
    while (i < tuple_obj.ob_base.ob_size) : (i += 1) {
        tuple_obj.ob_item[i].ob_refcnt -= 1;
        // TODO: Check if refcnt == 0 and deallocate
    }
    
    // Free entire block (struct + items)
    const total_size = @sizeOf(PyTupleObject) + (@as(usize, @intCast(tuple_obj.ob_base.ob_size)) * @sizeOf(*cpython.PyObject));
    const memory: []u8 = @as([*]u8, @ptrCast(tuple_obj))[0..total_size];
    allocator.free(memory);
}

fn tuple_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Return string representation "(item1, item2, ...)"
    _ = obj;
    return null;
}

fn tuple_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const tuple_obj = @as(*PyTupleObject, @ptrCast(obj));
    
    // Simple hash - combine item hashes
    var hash: u64 = 0x345678;
    var i: usize = 0;
    
    while (i < tuple_obj.ob_base.ob_size) : (i += 1) {
        const item = tuple_obj.ob_item[i];
        
        // Get item hash (simplified - would call tp_hash)
        const item_hash: u64 = @intCast(@intFromPtr(item));
        hash = (hash ^ item_hash) *% 1000003;
    }
    
    return @intCast(hash);
}

// Tests
test "tuple exports" {
    _ = PyTuple_New;
    _ = PyTuple_GetItem;
    _ = PyTuple_SetItem;
}
