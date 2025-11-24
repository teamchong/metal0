/// CPython Weak Reference Support
///
/// Implements weak reference protocol for objects that can be weakly referenced.

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// Create new weak reference
export fn PyWeakref_NewRef(obj: *cpython.PyObject, callback: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = callback; // TODO: Implement callback
    
    // Create weakref object
    // For now, simplified implementation
    Py_INCREF(obj);
    return obj;
}

/// Get object from weak reference
export fn PyWeakref_GetObject(ref: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Return referenced object (or None if dead)
    return ref;
}

/// Check if object is a weak reference
export fn PyWeakref_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 0; // TODO: Implement type check
}

/// Check if weak reference is still alive
export fn PyWeakref_CheckRef(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 1; // Simplified: always alive
}

// Tests
test "weakref exports" {
    _ = PyWeakref_NewRef;
    _ = PyWeakref_GetObject;
}
