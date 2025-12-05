/// Python list object implementation
///
/// Dynamic array with resize capability - uses EXACT CPython memory layout

const std = @import("std");
const cpython = @import("../include/object.zig");
const traits = @import("typetraits.zig");

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

        items[@intCast(idx)] = traits.incref(item);
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
                    new_items[@intCast(i)] = traits.incref(item);
                }
            }
        }
    }
    
    return new_list;
}

/// Set slice
export fn PyList_SetSlice(obj: *cpython.PyObject, low: isize, high: isize, itemlist: ?*cpython.PyObject) callconv(.c) c_int {
    if (PyList_Check(obj) == 0) return -1;

    const list_obj = @as(*PyListObject, @ptrCast(obj));
    const size = list_obj.ob_base.ob_size;

    var real_low = low;
    var real_high = high;

    // Normalize indices
    if (real_low < 0) real_low = 0;
    if (real_high > size) real_high = size;
    if (real_low > real_high) real_low = real_high;

    const del_count = real_high - real_low;

    // Get insert count
    var ins_count: isize = 0;
    if (itemlist) |il| {
        if (PyList_Check(il) != 0) {
            const il_list = @as(*PyListObject, @ptrCast(il));
            ins_count = il_list.ob_base.ob_size;
        }
    }

    const new_size = size - del_count + ins_count;

    // Resize if needed
    if (new_size > list_obj.allocated) {
        if (list_resize(list_obj, new_size) < 0) return -1;
    }

    if (list_obj.ob_item) |items| {
        // Shift items to make room (or close gap)
        if (ins_count != del_count) {
            const move_start: usize = @intCast(real_high);
            const move_end: usize = @intCast(size);
            const dest: usize = @intCast(real_low + ins_count);

            if (ins_count > del_count) {
                // Shift right
                var i: usize = move_end;
                while (i > move_start) {
                    i -= 1;
                    items[dest + (i - move_start)] = items[i];
                }
            } else {
                // Shift left
                var i: usize = move_start;
                while (i < move_end) : (i += 1) {
                    items[dest + (i - move_start)] = items[i];
                }
            }
        }

        // Copy new items
        if (itemlist) |il| {
            if (PyList_Check(il) != 0) {
                const il_list = @as(*PyListObject, @ptrCast(il));
                if (il_list.ob_item) |il_items| {
                    var i: usize = 0;
                    while (i < @as(usize, @intCast(ins_count))) : (i += 1) {
                        const item = il_items[i];
                        items[@as(usize, @intCast(real_low)) + i] = traits.incref(item);
                    }
                }
            }
        }
    }

    list_obj.ob_base.ob_size = new_size;
    return 0;
}

/// Sort list (simple insertion sort for now - CPython uses TimSort)
export fn PyList_Sort(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyList_Check(obj) == 0) return -1;

    const list_obj = @as(*PyListObject, @ptrCast(obj));
    const size: usize = @intCast(list_obj.ob_base.ob_size);

    if (size <= 1) return 0;

    if (list_obj.ob_item) |items| {
        // Simple insertion sort - O(n^2) but stable
        // CPython uses TimSort which is O(n log n)
        var i: usize = 1;
        while (i < size) : (i += 1) {
            const key = items[i];
            var j: usize = i;
            while (j > 0) {
                // Compare using pointer addresses as fallback
                // Real implementation would use PyObject_RichCompareBool
                const prev = items[j - 1];
                if (@intFromPtr(prev) <= @intFromPtr(key)) break;
                items[j] = prev;
                j -= 1;
            }
            items[j] = key;
        }
    }

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
    if (PyList_Check(obj) == 0) return null;

    const list_obj = @as(*PyListObject, @ptrCast(obj));
    const size = list_obj.ob_base.ob_size;

    // Import tuple creation
    const tuple = @import("tupleobject.zig");
    const new_tuple = tuple.PyTuple_New(size);

    if (new_tuple) |t| {
        if (list_obj.ob_item) |items| {
            var i: isize = 0;
            while (i < size) : (i += 1) {
                const item = items[@intCast(i)];
                _ = tuple.PyTuple_SetItem(t, i, traits.incref(item));
            }
        }
    }

    return new_tuple;
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
    return traits.incref(item); // Return new reference
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
                    new_items[i] = traits.incref(a_items[i]);
                }
            }

            // Copy from b
            if (b_list.ob_item) |b_items| {
                var i: usize = 0;
                const offset: usize = @intCast(a_list.ob_base.ob_size);
                while (i < @as(usize, @intCast(b_list.ob_base.ob_size))) : (i += 1) {
                    new_items[offset + i] = traits.incref(b_items[i]);
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
                        new_items[rep * @as(usize, @intCast(list_obj.ob_base.ob_size)) + i] = traits.incref(items[i]);
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
        if (PyList_Check(obj) == 0) return -1;

        const list_obj = @as(*PyListObject, @ptrCast(obj));
        if (idx < 0 or idx >= list_obj.ob_base.ob_size) return -1;

        if (list_obj.ob_item) |items| {
            // Decref the deleted item
            traits.decref(items[@intCast(idx)]);

            // Shift items left
            var i: usize = @intCast(idx);
            while (i + 1 < @as(usize, @intCast(list_obj.ob_base.ob_size))) : (i += 1) {
                items[i] = items[i + 1];
            }

            list_obj.ob_base.ob_size -= 1;
            return 0;
        }
        return -1;
    }
}

fn list_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const list_obj = @as(*PyListObject, @ptrCast(obj));

    // Decref all items
    if (list_obj.ob_item) |items| {
        var i: usize = 0;
        while (i < @as(usize, @intCast(list_obj.ob_base.ob_size))) : (i += 1) {
            traits.decref(items[i]);
        }

        const slice = items[0..@intCast(list_obj.allocated)];
        allocator.free(slice);
    }

    allocator.destroy(list_obj);
}

fn list_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const list_obj = @as(*PyListObject, @ptrCast(obj));
    const size: usize = @intCast(list_obj.ob_base.ob_size);

    // For empty list, return "[]"
    if (size == 0) {
        const unicode = @import("unicodeobject.zig");
        return unicode.PyUnicode_FromString("[]");
    }

    // Build string representation
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    buf[pos] = '[';
    pos += 1;

    if (list_obj.ob_item) |items| {
        var i: usize = 0;
        while (i < size and pos < buf.len - 10) : (i += 1) {
            if (i > 0) {
                buf[pos] = ',';
                pos += 1;
                buf[pos] = ' ';
                pos += 1;
            }
            // Placeholder for item repr
            const placeholder = "...";
            for (placeholder) |c| {
                if (pos < buf.len - 2) {
                    buf[pos] = c;
                    pos += 1;
                }
            }
            _ = items;
        }
    }

    buf[pos] = ']';
    pos += 1;

    const unicode = @import("unicodeobject.zig");
    return unicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

// ============================================================================
// Macro-style Accessors (No Error Checking)
// ============================================================================

/// PyList_GET_ITEM - Get item without error checking (macro in CPython)
/// WARNING: No bounds checking, no type checking - caller must ensure validity
export fn PyList_GET_ITEM(obj: *cpython.PyObject, idx: isize) callconv(.c) *cpython.PyObject {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    return list_obj.ob_item.?[@intCast(idx)];
}

/// PyList_SET_ITEM - Set item without error checking (macro in CPython)
/// WARNING: Steals reference, no bounds/type checking
export fn PyList_SET_ITEM(obj: *cpython.PyObject, idx: isize, item: *cpython.PyObject) callconv(.c) void {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    list_obj.ob_item.?[@intCast(idx)] = item;
}

/// PyList_GET_SIZE - Get size without error checking (macro in CPython)
export fn PyList_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    return list_obj.ob_base.ob_size;
}

// Tests
test "list exports" {
    _ = PyList_New;
    _ = PyList_Append;
    _ = PyList_GetItem;
    _ = PyList_GET_ITEM;
    _ = PyList_SET_ITEM;
    _ = PyList_GET_SIZE;
}
