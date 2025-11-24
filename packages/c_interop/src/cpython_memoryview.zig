/// CPython MemoryView Protocol
///
/// Implements memory view objects for buffer interface.

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// Memory view object
pub const PyMemoryViewObject = extern struct {
    ob_base: cpython.PyObject,
    view: cpython.Py_buffer,
};

/// Create memory view from buffer
export fn PyMemoryView_FromBuffer(view: *cpython.Py_buffer) callconv(.c) ?*cpython.PyObject {
    const memview = allocator.create(PyMemoryViewObject) catch return null;
    
    memview.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined, // TODO: &PyMemoryView_Type
    };
    
    memview.view = view.*;
    
    return @ptrCast(&memview.ob_base);
}

/// Create memory view from object
export fn PyMemoryView_FromObject(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Get buffer from object
    // TODO: Use PyObject_GetBuffer
    Py_INCREF(obj);
    return obj;
}

/// Get buffer from memory view
export fn PyMemoryView_GetContiguous(obj: *cpython.PyObject, buffertype: c_int, order: u8) callconv(.c) ?*cpython.PyObject {
    _ = buffertype;
    _ = order;
    
    Py_INCREF(obj);
    return obj;
}

/// Check if object is memory view
export fn PyMemoryView_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    // TODO: Check type
    return 0;
}

// Tests
test "memoryview exports" {
    _ = PyMemoryView_FromObject;
    _ = PyMemoryView_Check;
}
