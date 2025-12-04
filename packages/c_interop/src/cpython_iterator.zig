/// CPython Iterator Protocol Implementation
///
/// This implements the iterator protocol for for-loop iteration.
/// Used by NumPy for iterating over arrays.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

/// Get iterator from object
export fn PyObject_GetIter(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Use traits for unified iterator handling
    if (traits.getIter(obj)) |iter| {
        return iter;
    }

    // Check if object is already an iterator (has __next__)
    if (traits.isIterator(obj)) {
        return traits.incref(obj);
    }

    traits.setError("TypeError", "object is not iterable");
    return null;
}

/// Get next item from iterator
export fn PyIter_Next(iter: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return traits.iterNext(iter);
}

/// Check if object is an iterator
export fn PyIter_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (traits.isIterator(obj)) 1 else 0;
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
