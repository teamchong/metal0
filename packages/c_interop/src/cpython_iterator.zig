/// CPython Iterator Protocol Implementation
///
/// This implements the iterator protocol for for-loop iteration.
/// Used by NumPy for iterating over arrays.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

/// Get iterator from object
export fn PyObject_GetIter(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    
    // Check for tp_iter
    if (type_obj.tp_iter) |iter_func| {
        return iter_func(obj);
    }
    
    // Check if object is already an iterator (has __next__)
    if (type_obj.tp_iternext) |_| {
        Py_INCREF(obj);
        return obj;
    }
    
    // Check for sequence protocol fallback
    if (type_obj.tp_as_sequence) |seq_procs| {
        if (seq_procs.sq_item) |_| {
            // Create sequence iterator
            // TODO: Implement sequence iterator wrapper
            PyErr_SetString(@ptrFromInt(0), "sequence iterator not implemented");
            return null;
        }
    }
    
    PyErr_SetString(@ptrFromInt(0), "object is not iterable");
    return null;
}

/// Get next item from iterator
export fn PyIter_Next(iter: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(iter);
    
    if (type_obj.tp_iternext) |next_func| {
        return next_func(iter);
    }
    
    PyErr_SetString(@ptrFromInt(0), "iter() returned non-iterator");
    return null;
}

/// Check if object is an iterator
export fn PyIter_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_iternext != null) {
        return 1;
    }
    
    return 0;
}

/// Send value to generator/coroutine
export fn PyIter_Send(iter: *cpython.PyObject, arg: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Simplified: just call next for now
    _ = arg;
    return PyIter_Next(iter);
}

// Tests
test "PyIter function exports" {
    _ = PyObject_GetIter;
    _ = PyIter_Next;
    _ = PyIter_Check;
}
