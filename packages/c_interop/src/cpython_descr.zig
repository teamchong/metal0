/// CPython Descriptor Protocol
///
/// Implements descriptors for property-like access.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

/// Call descriptor __get__
export fn PyObject_GenericGetAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_getattro) |getattr| {
        return getattr(obj, name);
    }
    
    PyErr_SetString(@ptrFromInt(0), "attribute access not supported");
    return null;
}

/// Call descriptor __set__
export fn PyObject_GenericSetAttr(obj: *cpython.PyObject, name: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_setattro) |setattr| {
        return setattr(obj, name, value);
    }
    
    PyErr_SetString(@ptrFromInt(0), "attribute assignment not supported");
    return -1;
}

/// Get attribute with string name
export fn PyObject_GetAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    // TODO: Convert string to unicode object
    _ = obj;
    _ = name;
    return null;
}

/// Set attribute with string name
export fn PyObject_SetAttrString(obj: *cpython.PyObject, name: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    _ = name;
    _ = value;
    return -1;
}

/// Delete attribute with string name
export fn PyObject_DelAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    _ = obj;
    _ = name;
    return -1;
}

// Tests
test "descriptor exports" {
    _ = PyObject_GenericGetAttr;
    _ = PyObject_GenericSetAttr;
}
