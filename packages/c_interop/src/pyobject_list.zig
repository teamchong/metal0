/// Python list object implementation
///
/// Dynamic array with resize capability - uses EXACT CPython memory layout

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export type from cpython_object.zig for exact CPython layout
pub const PyListObject = cpython.PyListObject;

/// Sequence protocol for lists
var list_as_sequence: cpython.PySequenceMethods = .{
    .sq_length = list_length,
    .sq_concat = list_concat,
    .sq_repeat = list_repeat,
    .sq_item = list_item,
    .sq_ass_item = list_ass_item,
    .sq_contains = null,
    .sq_inplace_concat = null,
    .sq_inplace_repeat = null,
};

/// PyList_Type - the 'list' type
pub var PyList_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "list",
    .tp_basicsize = @sizeOf(PyListObject),
    .tp_itemsize = 0,
    .tp_dealloc = list_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = list_repr,
    .tp_as_number = null,
    .tp_as_sequence = &list_as_sequence,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_LIST_SUBCLASS,
    .tp_doc = "list() -> new empty list",
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

/// Create new empty list
pub export fn PyList_New(size: isize) callconv(.c) ?*cpython.PyObject {
    if (size < 0) return null;
    
    const obj = allocator.create(PyListObject) catch return null;
    obj.ob_base.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_base.ob_type = &PyList_Type;
    obj.ob_base.ob_size = size;
    
    if (size == 0) {
        obj.ob_item = null;
        obj.allocated = 0;
    } else {
        const items = allocator.alloc(*cpython.PyObject, @intCast(size)) catch {
            allocator.destroy(obj);
            return null;
        };
        
        // Initialize all items to null
        @memset(items, undefined);
        
        obj.ob_item = items.ptr;
        obj.allocated = size;
    }
    
    return @ptrCast(&obj.ob_base.ob_base);
}

/// Get list size
export fn PyList_Size(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyList_Check(obj) == 0) return -1;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    return list_obj.ob_base.ob_size;
}

/// Get item at index
export fn PyList_GetItem(obj: *cpython.PyObject, idx: isize) callconv(.c) ?*cpython.PyObject {
    if (PyList_Check(obj) == 0) return null;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    if (idx < 0 or idx >= list_obj.ob_base.ob_size) return null;
    
    if (list_obj.ob_item) |items| {
        return items[@intCast(idx)];
    }
    
    return null;
}

/// Set item at index
pub export fn PyList_SetItem(obj: *cpython.PyObject, idx: isize, item: *cpython.PyObject) callconv(.c) c_int {
    if (PyList_Check(obj) == 0) return -1;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    if (idx < 0 or idx >= list_obj.ob_base.ob_size) return -1;
    
    if (list_obj.ob_item) |items| {
        // Steal reference - no INCREF needed
        items[@intCast(idx)] = item;
        return 0;
    }
    
    return -1;
}

/// Insert item at index
export fn PyList_Insert(obj: *cpython.PyObject, idx: isize, item: *cpython.PyObject) callconv(.c) c_int {
    if (PyList_Check(obj) == 0) return -1;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    // Resize if needed
    if (list_obj.ob_base.ob_size >= list_obj.allocated) {
        if (list_resize(list_obj, list_obj.ob_base.ob_size + 1) < 0) {
            return -1;
        }
    }
    
    if (list_obj.ob_item) |items| {
        // Shift items right
        var i = list_obj.ob_base.ob_size;
        while (i > idx) : (i -= 1) {
            items[@intCast(i)] = items[@intCast(i - 1)];
        }
        
        items[@intCast(idx)] = item;
        item.ob_refcnt += 1;
        list_obj.ob_base.ob_size += 1;
        return 0;
    }
    
    return -1;
}

/// Append item to end
export fn PyList_Append(obj: *cpython.PyObject, item: *cpython.PyObject) callconv(.c) c_int {
    if (PyList_Check(obj) == 0) return -1;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    return PyList_Insert(obj, list_obj.ob_base.ob_size, item);
}

/// Get slice
export fn PyList_GetSlice(obj: *cpython.PyObject, low: isize, high: isize) callconv(.c) ?*cpython.PyObject {
    if (PyList_Check(obj) == 0) return null;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    var real_low = low;
    var real_high = high;
    
    if (real_low < 0) real_low = 0;
    if (real_high > list_obj.ob_base.ob_size) real_high = list_obj.ob_base.ob_size;
    if (real_low >= real_high) return PyList_New(0);
    
    const slice_len = real_high - real_low;
    const new_list = PyList_New(slice_len);
    
    if (new_list) |new_obj| {
        const new_list_obj = @as(*PyListObject, @ptrCast(new_obj));
        
        if (list_obj.ob_item) |items| {
            if (new_list_obj.ob_item) |new_items| {
                var i: isize = 0;
                while (i < slice_len) : (i += 1) {
                    const item = items[@intCast(real_low + i)];
                    item.ob_refcnt += 1;
                    new_items[@intCast(i)] = item;
                }
            }
        }
    }
    
    return new_list;
}

/// Set slice
export fn PyList_SetSlice(obj: *cpython.PyObject, low: isize, high: isize, itemlist: ?*cpython.PyObject) callconv(.c) c_int {
    // TODO: Implement slice assignment
    _ = obj;
    _ = low;
    _ = high;
    _ = itemlist;
    return -1;
}

/// Sort list
export fn PyList_Sort(obj: *cpython.PyObject) callconv(.c) c_int {
    // TODO: Implement sorting
    _ = obj;
    return 0;
}

/// Reverse list
export fn PyList_Reverse(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyList_Check(obj) == 0) return -1;
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    if (list_obj.ob_item) |items| {
        var left: usize = 0;
        var right: usize = @intCast(list_obj.ob_base.ob_size - 1);
        
        while (left < right) {
            const temp = items[left];
            items[left] = items[right];
            items[right] = temp;
            left += 1;
            right -= 1;
        }
    }
    
    return 0;
}

/// Convert to tuple
export fn PyList_AsTuple(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Create tuple from list
    _ = obj;
    return null;
}

/// Type check
export fn PyList_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyList_Type) 1 else 0;
}

/// Exact type check
export fn PyList_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyList_Type) 1 else 0;
}

// ============================================================================
// Internal Functions
// ============================================================================

fn list_resize(list: *PyListObject, newsize: isize) c_int {
    const new_allocated = newsize + (newsize >> 3) + 6; // Over-allocate
    
    if (list.ob_item) |old_items| {
        const old_slice = old_items[0..@intCast(list.allocated)];
        const new_items = allocator.realloc(old_slice, @intCast(new_allocated)) catch {
            return -1;
        };
        list.ob_item = new_items.ptr;
    } else {
        const new_items = allocator.alloc(*cpython.PyObject, @intCast(new_allocated)) catch {
            return -1;
        };
        list.ob_item = new_items.ptr;
    }
    
    list.allocated = new_allocated;
    return 0;
}

fn list_length(obj: *cpython.PyObject) callconv(.c) isize {
    return PyList_Size(obj);
}

fn list_item(obj: *cpython.PyObject, idx: isize) callconv(.c) ?*cpython.PyObject {
    const item = PyList_GetItem(obj, idx);
    if (item) |i| {
        i.ob_refcnt += 1; // Return new reference
    }
    return item;
}

fn list_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyList_Check(a) == 0 or PyList_Check(b) == 0) return null;
    
    const a_list = @as(*PyListObject, @ptrCast(a));
    const b_list = @as(*PyListObject, @ptrCast(b));
    
    const new_size = a_list.ob_base.ob_size + b_list.ob_base.ob_size;
    const new_list = PyList_New(new_size);
    
    if (new_list) |new_obj| {
        const new_list_obj = @as(*PyListObject, @ptrCast(new_obj));
        
        if (new_list_obj.ob_item) |new_items| {
            // Copy from a
            if (a_list.ob_item) |a_items| {
                var i: usize = 0;
                while (i < a_list.ob_base.ob_size) : (i += 1) {
                    const item = a_items[i];
                    item.ob_refcnt += 1;
                    new_items[i] = item;
                }
            }
            
            // Copy from b
            if (b_list.ob_item) |b_items| {
                var i: usize = 0;
                const offset: usize = @intCast(a_list.ob_base.ob_size);
                while (i < @as(usize, @intCast(b_list.ob_base.ob_size))) : (i += 1) {
                    const item = b_items[i];
                    item.ob_refcnt += 1;
                    new_items[offset + i] = item;
                }
            }
        }
    }
    
    return new_list;
}

fn list_repeat(obj: *cpython.PyObject, n: isize) callconv(.c) ?*cpython.PyObject {
    if (n <= 0) return PyList_New(0);
    
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    const new_size = list_obj.ob_base.ob_size * n;
    
    const new_list = PyList_New(new_size);
    
    if (new_list) |new_obj| {
        const new_list_obj = @as(*PyListObject, @ptrCast(new_obj));
        
        if (list_obj.ob_item) |items| {
            if (new_list_obj.ob_item) |new_items| {
                var rep: usize = 0;
                while (rep < n) : (rep += 1) {
                    var i: usize = 0;
                    while (i < list_obj.ob_base.ob_size) : (i += 1) {
                        const item = items[i];
                        item.ob_refcnt += 1;
                        new_items[rep * @as(usize, @intCast(list_obj.ob_base.ob_size)) + i] = item;
                    }
                }
            }
        }
    }
    
    return new_list;
}

fn list_ass_item(obj: *cpython.PyObject, idx: isize, value: ?*cpython.PyObject) callconv(.c) c_int {
    if (value) |v| {
        return PyList_SetItem(obj, idx, v);
    } else {
        // Delete item (value is null)
        // TODO: Implement item deletion
        return -1;
    }
}

fn list_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    
    // Decref all items
    if (list_obj.ob_item) |items| {
        var i: usize = 0;
        while (i < list_obj.ob_base.ob_size) : (i += 1) {
            items[i].ob_refcnt -= 1;
            // TODO: Check if refcnt == 0 and deallocate
        }
        
        const slice = items[0..@intCast(list_obj.allocated)];
        allocator.free(slice);
    }
    
    allocator.destroy(list_obj);
}

fn list_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Return string representation "[item1, item2, ...]"
    _ = obj;
    return null;
}

// Tests
test "list exports" {
    _ = PyList_New;
    _ = PyList_Append;
    _ = PyList_GetItem;
}
