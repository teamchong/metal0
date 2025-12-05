/// CPython Mapping Protocol Implementation
///
/// This implements the mapping protocol for dictionary-like operations.
/// Used by NumPy for dictionary-based indexing and named dimensions.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Import error handling functions
const PyErr_SetString = traits.externs.PyErr_SetString;
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;

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

/// Get keys as a list
export fn PyMapping_Keys(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pydict = @import("pyobject_dict.zig");
    const pylist = @import("pyobject_list.zig");
    const type_obj = cpython.Py_TYPE(obj);

    // Check if it's a dict - use PyDict_Keys directly
    if (type_obj == pydict.getPyDictType()) {
        return pydict.PyDict_Keys(obj);
    }

    // For other mappings, try to call keys() method via tp_getattro
    if (type_obj.tp_getattro) |getattro| {
        const unicode = @import("cpython_unicode.zig");
        const keys_name = unicode.PyUnicode_FromString("keys") orelse return null;
        defer traits.decref(keys_name);

        const keys_method = getattro(obj, keys_name);
        if (keys_method) |method| {
            defer traits.decref(method);
            // Call the method with no arguments
            const method_type = cpython.Py_TYPE(method);
            if (method_type.tp_call) |call_fn| {
                const empty_tuple = @import("pyobject_tuple.zig").PyTuple_New(0) orelse return null;
                defer traits.decref(empty_tuple);
                const result = call_fn(method, empty_tuple, null);
                if (result) |res| {
                    // Convert to list if it's a view
                    return pylist.PySequence_List(res);
                }
            }
        }
    }

    // Fallback: iterate manually if tp_as_mapping has mp_subscript
    if (type_obj.tp_as_mapping) |_| {
        // Can't iterate without iterator protocol
        PyErr_SetString(@ptrFromInt(0), "mapping object has no keys() method");
        return null;
    }

    PyErr_SetString(@ptrFromInt(0), "object is not a mapping");
    return null;
}

/// Get values as a list
export fn PyMapping_Values(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pydict = @import("pyobject_dict.zig");
    const pylist = @import("pyobject_list.zig");
    const type_obj = cpython.Py_TYPE(obj);

    // Check if it's a dict - use PyDict_Values directly
    if (type_obj == pydict.getPyDictType()) {
        return pydict.PyDict_Values(obj);
    }

    // For other mappings, try to call values() method
    if (type_obj.tp_getattro) |getattro| {
        const unicode = @import("cpython_unicode.zig");
        const values_name = unicode.PyUnicode_FromString("values") orelse return null;
        defer traits.decref(values_name);

        const values_method = getattro(obj, values_name);
        if (values_method) |method| {
            defer traits.decref(method);
            const method_type = cpython.Py_TYPE(method);
            if (method_type.tp_call) |call_fn| {
                const empty_tuple = @import("pyobject_tuple.zig").PyTuple_New(0) orelse return null;
                defer traits.decref(empty_tuple);
                const result = call_fn(method, empty_tuple, null);
                if (result) |res| {
                    return pylist.PySequence_List(res);
                }
            }
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object is not a mapping or has no values() method");
    return null;
}

/// Get items as a list of (key, value) tuples
export fn PyMapping_Items(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pydict = @import("pyobject_dict.zig");
    const pylist = @import("pyobject_list.zig");
    const type_obj = cpython.Py_TYPE(obj);

    // Check if it's a dict - use PyDict_Items directly
    if (type_obj == pydict.getPyDictType()) {
        return pydict.PyDict_Items(obj);
    }

    // For other mappings, try to call items() method
    if (type_obj.tp_getattro) |getattro| {
        const unicode = @import("cpython_unicode.zig");
        const items_name = unicode.PyUnicode_FromString("items") orelse return null;
        defer traits.decref(items_name);

        const items_method = getattro(obj, items_name);
        if (items_method) |method| {
            defer traits.decref(method);
            const method_type = cpython.Py_TYPE(method);
            if (method_type.tp_call) |call_fn| {
                const empty_tuple = @import("pyobject_tuple.zig").PyTuple_New(0) orelse return null;
                defer traits.decref(empty_tuple);
                const result = call_fn(method, empty_tuple, null);
                if (result) |res| {
                    return pylist.PySequence_List(res);
                }
            }
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object is not a mapping or has no items() method");
    return null;
}

// Tests
test "PyMapping function exports" {
    _ = PyMapping_Check;
    _ = PyMapping_Size;
    _ = PyMapping_HasKeyString;
}
