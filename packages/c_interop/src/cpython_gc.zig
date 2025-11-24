/// CPython Garbage Collection Protocol
///
/// Implements GC control and object tracking for cyclic garbage collection.

const std = @import("std");
const cpython = @import("cpython_object.zig");

/// Perform garbage collection
export fn PyGC_Collect() callconv(.c) isize {
    // Simplified: no actual GC yet
    return 0;
}

/// Enable automatic garbage collection
export fn PyGC_Enable() callconv(.c) c_int {
    // GC always enabled for now
    return 0;
}

/// Disable automatic garbage collection  
export fn PyGC_Disable() callconv(.c) c_int {
    // Can't disable in simplified implementation
    return 0;
}

/// Check if GC is enabled
export fn PyGC_IsEnabled() callconv(.c) c_int {
    return 1; // Always enabled
}

/// Track object for GC
export fn PyObject_GC_Track(obj: *cpython.PyObject) callconv(.c) void {
    _ = obj;
    // TODO: Add to GC tracking list
}

/// Untrack object from GC
export fn PyObject_GC_UnTrack(obj: *cpython.PyObject) callconv(.c) void {
    _ = obj;
    // TODO: Remove from GC tracking list
}

/// Check if object is tracked
export fn PyObject_GC_IsTracked(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 0; // Not tracked by default
}

/// Allocate GC-tracked object
export fn _PyObject_GC_New(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    const basic_size: usize = @intCast(type_obj.tp_basicsize);
    
    const memory = std.heap.c_allocator.alignedAlloc(u8, @alignOf(cpython.PyObject), basic_size) catch return null;
    
    const obj = @as(*cpython.PyObject, @ptrCast(@alignCast(memory.ptr)));
    obj.ob_refcnt = 1;
    obj.ob_type = type_obj;
    
    PyObject_GC_Track(obj);
    
    return obj;
}

/// Delete GC-tracked object
export fn PyObject_GC_Del(obj: *cpython.PyObject) callconv(.c) void {
    PyObject_GC_UnTrack(obj);
    
    const ptr = @as([*]u8, @ptrCast(obj));
    const type_obj = cpython.Py_TYPE(obj);
    const size: usize = @intCast(type_obj.tp_basicsize);
    
    std.heap.c_allocator.free(ptr[0..size]);
}

// Tests
test "gc exports" {
    _ = PyGC_Collect;
    _ = PyGC_Enable;
    _ = PyObject_GC_Track;
}
