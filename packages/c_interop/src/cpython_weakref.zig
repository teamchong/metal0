/// CPython Weak Reference Support
///
/// Implements weak reference protocol for objects that can be weakly referenced.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

const allocator = std.heap.c_allocator;

/// Create new weak reference
export fn PyWeakref_NewRef(obj: *cpython.PyObject, callback: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = callback; // TODO: Implement callback

    // Create weakref object
    // For now, simplified implementation
    return traits.incref(obj);
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

/// Create weak proxy (transparent weak reference)
export fn PyWeakref_NewProxy(obj: *cpython.PyObject, callback: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // For now, same as NewRef - proper implementation would create a transparent proxy
    return PyWeakref_NewRef(obj, callback);
}

/// Get referenced object (Python 3.13+ API)
/// Returns new reference or null if dead (unlike GetObject which returns borrowed)
export fn PyWeakref_GetRef(ref: *cpython.PyObject, pobj: *?*cpython.PyObject) callconv(.c) c_int {
    // Get the object
    const obj = PyWeakref_GetObject(ref);
    if (obj) |o| {
        // Check if it's None (dead reference)
        if (traits.isNone(o)) {
            pobj.* = null;
            return 0;
        }
        // Return new reference
        pobj.* = traits.incref(o);
        return 1;
    }
    pobj.* = null;
    return 0;
}

// Tests
test "weakref exports" {
    _ = PyWeakref_NewRef;
    _ = PyWeakref_GetObject;
}
