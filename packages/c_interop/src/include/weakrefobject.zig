/// CPython Weak Reference Support
///
/// Implements weak reference protocol for objects that can be weakly referenced.

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

/// WeakRef object structure
pub const PyWeakReference = extern struct {
    ob_base: cpython.PyObject,
    /// The referenced object (or null if dead)
    wr_object: ?*cpython.PyObject,
    /// Callback to call when object dies
    wr_callback: ?*cpython.PyObject,
    /// Hash of the referenced object (cached)
    hash: isize,
    /// Whether this is a proxy reference
    wr_prev: ?*PyWeakReference,
    wr_next: ?*PyWeakReference,
};

/// PyWeakref_Type
pub var PyWeakref_RefType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "weakref",
    .tp_basicsize = @sizeOf(PyWeakReference),
    .tp_itemsize = 0,
    .tp_dealloc = weakref_dealloc,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

fn weakref_dealloc(self: *cpython.PyObject) callconv(.c) void {
    const wr: *PyWeakReference = @ptrCast(@alignCast(self));
    if (wr.wr_callback) |cb| {
        traits.decref(cb);
    }
    allocator.destroy(wr);
}

/// Create new weak reference
export fn PyWeakref_NewRef(obj: *cpython.PyObject, callback: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Check if object is weakly referencable
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_weaklistoffset == 0) {
        // Object doesn't support weak references - return incref'd object
        return traits.incref(obj);
    }

    // Create weakref object
    const wr = allocator.create(PyWeakReference) catch return null;
    wr.ob_base.ob_refcnt = 1;
    wr.ob_base.ob_type = &PyWeakref_RefType;
    wr.wr_object = obj; // Don't incref - weak reference
    wr.wr_callback = if (callback) |cb| traits.incref(cb) else null;
    wr.hash = -1;
    wr.wr_prev = null;
    wr.wr_next = null;

    return @ptrCast(&wr.ob_base);
}

/// Get object from weak reference (returns borrowed reference)
export fn PyWeakref_GetObject(ref: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Check if this is actually a weakref
    if (cpython.Py_TYPE(ref) != &PyWeakref_RefType) {
        // Not a weakref - return as-is
        return ref;
    }

    const wr: *PyWeakReference = @ptrCast(@alignCast(ref));
    if (wr.wr_object) |obj| {
        // Check if object is still alive (refcount > 0)
        if (obj.ob_refcnt > 0) {
            return obj;
        }
    }
    // Dead reference - return None
    return @import("../objects/noneobject.zig").Py_None();
}

/// Check if object is a weak reference
export fn PyWeakref_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyWeakref_RefType) 1 else 0;
}

/// Check if weak reference is still alive
export fn PyWeakref_CheckRef(obj: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(obj) != &PyWeakref_RefType) return 0;
    const wr: *PyWeakReference = @ptrCast(@alignCast(obj));
    if (wr.wr_object) |o| {
        return if (o.ob_refcnt > 0) 1 else 0;
    }
    return 0;
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
