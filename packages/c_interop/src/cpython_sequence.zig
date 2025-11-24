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
    // Create slice object
    // For now, simplified implementation
    _ = obj;
    _ = i;
    _ = j;
    
    PyErr_SetString(@ptrFromInt(0), "slicing not yet implemented");
    return null;
}

/// Set slice [i:j] = v
export fn PySequence_SetSlice(obj: *cpython.PyObject, i: isize, j: isize, value: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    _ = i;
    _ = j;
    _ = value;
    
    PyErr_SetString(@ptrFromInt(0), "slice assignment not yet implemented");
    return -1;
}

/// Delete slice [i:j]
export fn PySequence_DelSlice(obj: *cpython.PyObject, i: isize, j: isize) callconv(.c) c_int {
    _ = obj;
    _ = i;
    _ = j;
    
    PyErr_SetString(@ptrFromInt(0), "slice deletion not yet implemented");
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
    // Create new list
    const len = PySequence_Size(obj);
    if (len < 0) return null;
    
    // TODO: Create PyList and populate
    _ = obj;
    
    PyErr_SetString(@ptrFromInt(0), "PySequence_List not fully implemented");
    return null;
}

/// Convert sequence to tuple
export fn PySequence_Tuple(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Create new tuple
    const len = PySequence_Size(obj);
    if (len < 0) return null;
    
    // TODO: Create PyTuple and populate
    _ = obj;
    
    PyErr_SetString(@ptrFromInt(0), "PySequence_Tuple not fully implemented");
    return null;
}

/// Fast sequence (for iteration)
export fn PySequence_Fast(obj: *cpython.PyObject, message: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = message;
    
    // If already list or tuple, return it
    const type_obj = cpython.Py_TYPE(obj);
    _ = type_obj;
    
    // TODO: Check if list or tuple
    Py_INCREF(obj);
    return obj;
}

/// Get item from fast sequence
export fn PySequence_Fast_GET_ITEM(obj: *cpython.PyObject, i: isize) callconv(.c) *cpython.PyObject {
    // Unsafe fast access (no bounds check)
    return PySequence_GetItem(obj, i) orelse @ptrFromInt(0);
}

/// Get size of fast sequence
export fn PySequence_Fast_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    return PySequence_Size(obj);
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
