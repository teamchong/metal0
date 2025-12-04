/// CPython Mapping Protocol Implementation
///
/// This implements the mapping protocol for dictionary-like operations.
/// Used by NumPy for dictionary-based indexing and named dimensions.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

/// Check if object is a mapping
export fn PyMapping_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (traits.isMapping(obj)) 1 else 0;
}

/// Get mapping length
export fn PyMapping_Size(obj: *cpython.PyObject) callconv(.c) isize {
    if (traits.getLength(obj)) |len| {
        return len;
    }
    traits.setError("TypeError", "object has no len()");
    return -1;
}

/// Alias for PyMapping_Size
export fn PyMapping_Length(obj: *cpython.PyObject) callconv(.c) isize {
    return PyMapping_Size(obj);
}

/// Get item by key
export fn PyMapping_GetItemString(obj: *cpython.PyObject, key: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    const unicode = @import("cpython_unicode.zig");

    if (type_obj.tp_as_mapping) |map_procs| {
        if (map_procs.mp_subscript) |subscript_func| {
            // Create string key
            const key_obj = unicode.PyUnicode_FromString(key) orelse return null;
            defer traits.decref(key_obj);
            return subscript_func(obj, key_obj);
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object is not subscriptable");
    return null;
}

/// Set item by key
export fn PyMapping_SetItemString(obj: *cpython.PyObject, key: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    const unicode = @import("cpython_unicode.zig");

    if (type_obj.tp_as_mapping) |map_procs| {
        if (map_procs.mp_ass_subscript) |ass_subscript_func| {
            // Create string key
            const key_obj = unicode.PyUnicode_FromString(key) orelse return -1;
            defer traits.decref(key_obj);
            return ass_subscript_func(obj, key_obj, value);
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object does not support item assignment");
    return -1;
}

/// Delete item by key
export fn PyMapping_DelItemString(obj: *cpython.PyObject, key: [*:0]const u8) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    const unicode = @import("cpython_unicode.zig");

    if (type_obj.tp_as_mapping) |map_procs| {
        if (map_procs.mp_ass_subscript) |ass_subscript_func| {
            // Create string key and pass null for value (indicates deletion)
            const key_obj = unicode.PyUnicode_FromString(key) orelse return -1;
            defer traits.decref(key_obj);
            return ass_subscript_func(obj, key_obj, null);
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object doesn't support item deletion");
    return -1;
}

/// Check if key exists
export fn PyMapping_HasKeyString(obj: *cpython.PyObject, key: [*:0]const u8) callconv(.c) c_int {
    const item = PyMapping_GetItemString(obj, key);
    if (item != null) {
        Py_DECREF(item.?);
        return 1;
    }
    
    // Clear error
    // TODO: PyErr_Clear when available
    return 0;
}

/// Check if key exists (object key)
export fn PyMapping_HasKey(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_as_mapping) |map_procs| {
        if (map_procs.mp_subscript) |subscript_func| {
            const item = subscript_func(obj, key);
            if (item != null) {
                Py_DECREF(item.?);
                return 1;
            }
        }
    }
    
    return 0;
}

/// Get keys
export fn PyMapping_Keys(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Try dict.keys() method
    _ = obj;
    
    PyErr_SetString(@ptrFromInt(0), "PyMapping_Keys not fully implemented");
    return null;
}

/// Get values
export fn PyMapping_Values(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Try dict.values() method
    _ = obj;
    
    PyErr_SetString(@ptrFromInt(0), "PyMapping_Values not fully implemented");
    return null;
}

/// Get items
export fn PyMapping_Items(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Try dict.items() method
    _ = obj;
    
    PyErr_SetString(@ptrFromInt(0), "PyMapping_Items not fully implemented");
    return null;
}

// Tests
test "PyMapping function exports" {
    _ = PyMapping_Check;
    _ = PyMapping_Size;
    _ = PyMapping_HasKeyString;
}
