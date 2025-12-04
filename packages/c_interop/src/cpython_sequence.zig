/// CPython Sequence Protocol Implementation
///
/// This implements the sequence protocol for list-like operations.
/// Critical for NumPy array indexing and slicing.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

/// Check if object is a sequence
export fn PySequence_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |_| {
        return 1;
    }
    
    return 0;
}

/// Get sequence length
export fn PySequence_Size(obj: *cpython.PyObject) callconv(.c) isize {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_length) |len_func| {
            return len_func(obj);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object has no len()");
    return -1;
}

/// Alias for PySequence_Size
export fn PySequence_Length(obj: *cpython.PyObject) callconv(.c) isize {
    return PySequence_Size(obj);
}

/// Concatenate sequences
export fn PySequence_Concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_concat) |concat_func| {
            return concat_func(a, b);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object can't be concatenated");
    return null;
}

/// Repeat sequence
export fn PySequence_Repeat(obj: *cpython.PyObject, count: isize) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_repeat) |repeat_func| {
            return repeat_func(obj, count);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object can't be repeated");
    return null;
}

/// Get item by index
export fn PySequence_GetItem(obj: *cpython.PyObject, i: isize) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_item) |item_func| {
            return item_func(obj, i);
        }
    }
    
    // Try mapping protocol
    if (type_obj.tp_as_mapping) |map_procs| {
        if (map_procs.mp_subscript) |subscript_func| {
            // Create integer object for index
            // TODO: Use PyLong_FromSsize_t when available
            _ = subscript_func;
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object does not support indexing");
    return null;
}

/// Set item by index
export fn PySequence_SetItem(obj: *cpython.PyObject, i: isize, value: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_ass_item) |ass_item_func| {
            return ass_item_func(obj, i, value);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object does not support item assignment");
    return -1;
}

/// Delete item by index
export fn PySequence_DelItem(obj: *cpython.PyObject, i: isize) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_ass_item) |ass_item_func| {
            return ass_item_func(obj, i, null);
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object doesn't support item deletion");
    return -1;
}

/// Get slice [i:j]
export fn PySequence_GetSlice(obj: *cpython.PyObject, i: isize, j: isize) callconv(.c) ?*cpython.PyObject {
    const list = @import("pyobject_list.zig");
    const tuple = @import("pyobject_tuple.zig");

    // Normalize indices
    const len = PySequence_Size(obj);
    if (len < 0) return null;

    var start = i;
    var stop = j;

    // Handle negative indices
    if (start < 0) start += len;
    if (stop < 0) stop += len;

    // Clamp to bounds
    if (start < 0) start = 0;
    if (stop > len) stop = len;
    if (start > stop) start = stop;

    const slice_len = stop - start;

    // Check if it's a list
    if (list.PyList_Check(obj) != 0) {
        const result = list.PyList_New(slice_len);
        if (result == null) return null;

        var idx: isize = 0;
        while (idx < slice_len) : (idx += 1) {
            if (list.PyList_GetItem(obj, start + idx)) |item| {
                Py_INCREF(item);
                _ = list.PyList_SetItem(result.?, idx, item);
            }
        }
        return result;
    }

    // Check if it's a tuple
    if (tuple.PyTuple_Check(obj) != 0) {
        const result = tuple.PyTuple_New(slice_len);
        if (result == null) return null;

        var idx: isize = 0;
        while (idx < slice_len) : (idx += 1) {
            if (tuple.PyTuple_GetItem(obj, start + idx)) |item| {
                Py_INCREF(item);
                _ = tuple.PyTuple_SetItem(result.?, idx, item);
            }
        }
        return result;
    }

    // Generic fallback using sequence protocol
    const result = list.PyList_New(slice_len);
    if (result == null) return null;

    var idx: isize = 0;
    while (idx < slice_len) : (idx += 1) {
        if (PySequence_GetItem(obj, start + idx)) |item| {
            _ = list.PyList_SetItem(result.?, idx, item);
        }
    }
    return result;
}

/// Set slice [i:j] = v
export fn PySequence_SetSlice(obj: *cpython.PyObject, i: isize, j: isize, value: *cpython.PyObject) callconv(.c) c_int {
    const list = @import("pyobject_list.zig");

    // Only lists support slice assignment
    if (list.PyList_Check(obj) != 0) {
        return list.PyList_SetSlice(obj, i, j, value);
    }

    PyErr_SetString(@ptrFromInt(0), "object does not support slice assignment");
    return -1;
}

/// Delete slice [i:j]
export fn PySequence_DelSlice(obj: *cpython.PyObject, i: isize, j: isize) callconv(.c) c_int {
    const list = @import("pyobject_list.zig");

    // Only lists support slice deletion
    if (list.PyList_Check(obj) != 0) {
        // Delete by setting to null/empty list
        return list.PyList_SetSlice(obj, i, j, null);
    }

    PyErr_SetString(@ptrFromInt(0), "object does not support slice deletion");
    return -1;
}

/// Check if item is in sequence
export fn PySequence_Contains(obj: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_contains) |contains_func| {
            return contains_func(obj, value);
        }
    }
    
    // Fallback: Linear search
    const len = PySequence_Size(obj);
    if (len < 0) return -1;
    
    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(obj, i);
        if (item == null) return -1;
        defer if (item) |it| Py_DECREF(it);
        
        // Compare (simplified)
        if (item.? == value) {
            return 1;
        }
    }
    
    return 0;
}

/// Count occurrences of value
export fn PySequence_Count(obj: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) isize {
    const len = PySequence_Size(obj);
    if (len < 0) return -1;
    
    var count: isize = 0;
    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(obj, i);
        if (item == null) return -1;
        defer if (item) |it| Py_DECREF(it);
        
        // Compare (simplified)
        if (item.? == value) {
            count += 1;
        }
    }
    
    return count;
}

/// Find first index of value
export fn PySequence_Index(obj: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) isize {
    const len = PySequence_Size(obj);
    if (len < 0) return -1;
    
    var i: isize = 0;
    while (i < len) : (i += 1) {
        const item = PySequence_GetItem(obj, i);
        if (item == null) return -1;
        defer if (item) |it| Py_DECREF(it);
        
        // Compare (simplified)
        if (item.? == value) {
            return i;
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "value not in sequence");
    return -1;
}

/// Convert sequence to list
export fn PySequence_List(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const list = @import("pyobject_list.zig");

    // If already a list, return a copy
    if (list.PyList_Check(obj) != 0) {
        const len = list.PyList_Size(obj);
        const result = list.PyList_New(len);
        if (result == null) return null;

        var i: isize = 0;
        while (i < len) : (i += 1) {
            if (list.PyList_GetItem(obj, i)) |item| {
                Py_INCREF(item);
                _ = list.PyList_SetItem(result.?, i, item);
            }
        }
        return result;
    }

    // Generic sequence conversion
    const len = PySequence_Size(obj);
    if (len < 0) return null;

    const result = list.PyList_New(len);
    if (result == null) return null;

    var i: isize = 0;
    while (i < len) : (i += 1) {
        if (PySequence_GetItem(obj, i)) |item| {
            _ = list.PyList_SetItem(result.?, i, item);
        }
    }
    return result;
}

/// Convert sequence to tuple
export fn PySequence_Tuple(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const tuple = @import("pyobject_tuple.zig");
    const list = @import("pyobject_list.zig");

    // If already a tuple, incref and return
    if (tuple.PyTuple_Check(obj) != 0) {
        Py_INCREF(obj);
        return obj;
    }

    // If it's a list, convert directly
    if (list.PyList_Check(obj) != 0) {
        return list.PyList_AsTuple(obj);
    }

    // Generic sequence conversion
    const len = PySequence_Size(obj);
    if (len < 0) return null;

    const result = tuple.PyTuple_New(len);
    if (result == null) return null;

    var i: isize = 0;
    while (i < len) : (i += 1) {
        if (PySequence_GetItem(obj, i)) |item| {
            _ = tuple.PyTuple_SetItem(result.?, i, item);
        }
    }
    return result;
}

/// Fast sequence (for iteration)
/// Returns a list or tuple view of the sequence (for fast item access)
export fn PySequence_Fast(obj: *cpython.PyObject, message: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const list = @import("pyobject_list.zig");
    const tuple = @import("pyobject_tuple.zig");

    // If already list or tuple, just incref and return
    if (list.PyList_Check(obj) != 0 or tuple.PyTuple_Check(obj) != 0) {
        Py_INCREF(obj);
        return obj;
    }

    // Otherwise, convert to list
    const result = PySequence_List(obj);
    if (result == null) {
        PyErr_SetString(@ptrFromInt(0), message);
    }
    return result;
}

/// Get item from fast sequence (no bounds checking)
export fn PySequence_Fast_GET_ITEM(obj: *cpython.PyObject, i: isize) callconv(.c) ?*cpython.PyObject {
    const list = @import("pyobject_list.zig");
    const tuple = @import("pyobject_tuple.zig");

    // Direct access for list/tuple (no bounds checking per CPython spec)
    if (list.PyList_Check(obj) != 0) {
        return list.PyList_GetItem(obj, i);
    }
    if (tuple.PyTuple_Check(obj) != 0) {
        return tuple.PyTuple_GetItem(obj, i);
    }

    return PySequence_GetItem(obj, i);
}

/// Get size of fast sequence
export fn PySequence_Fast_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    const list = @import("pyobject_list.zig");
    const tuple = @import("pyobject_tuple.zig");

    if (list.PyList_Check(obj) != 0) {
        return list.PyList_Size(obj);
    }
    if (tuple.PyTuple_Check(obj) != 0) {
        return tuple.PyTuple_Size(obj);
    }

    return PySequence_Size(obj);
}

/// Get underlying array of fast sequence (for direct pointer access)
export fn PySequence_Fast_ITEMS(obj: *cpython.PyObject) callconv(.c) ?[*]*cpython.PyObject {
    const list = @import("pyobject_list.zig");
    const tuple = @import("pyobject_tuple.zig");

    if (list.PyList_Check(obj) != 0) {
        const list_obj: *list.PyListObject = @ptrCast(@alignCast(obj));
        return list_obj.ob_item;
    }
    if (tuple.PyTuple_Check(obj) != 0) {
        const tuple_obj: *tuple.PyTupleObject = @ptrCast(@alignCast(obj));
        return @ptrCast(&tuple_obj.ob_item);
    }

    return null;
}

/// In-place concatenate
export fn PySequence_InPlaceConcat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(a);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_inplace_concat) |concat_func| {
            return concat_func(a, b);
        }
    }
    
    // Fallback to regular concat
    return PySequence_Concat(a, b);
}

/// In-place repeat
export fn PySequence_InPlaceRepeat(obj: *cpython.PyObject, count: isize) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_inplace_repeat) |repeat_func| {
            return repeat_func(obj, count);
        }
    }
    
    // Fallback to regular repeat
    return PySequence_Repeat(obj, count);
}

// Tests
test "PySequence function exports" {
    // Verify functions exist
    _ = PySequence_Check;
    _ = PySequence_Size;
    _ = PySequence_GetItem;
    _ = PySequence_Contains;
}
