/// CPython Garbage Collection Protocol
///
/// Implements GC control and object tracking for cyclic garbage collection.

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// GC State
// ============================================================================

/// Global GC state
var gc_enabled: bool = true;
var gc_generation_count: [3]usize = .{ 0, 0, 0 };
var gc_threshold: [3]usize = .{ 700, 10, 10 }; // Default thresholds

/// Simple hash set for tracking objects
const ObjectSet = std.AutoHashMap(*cpython.PyObject, void);
var tracked_objects: ?ObjectSet = null;

fn getTrackedObjects() *ObjectSet {
    if (tracked_objects == null) {
        tracked_objects = ObjectSet.init(allocator);
    }
    return &tracked_objects.?;
}

// ============================================================================
// GC Control Functions
// ============================================================================

/// Perform garbage collection
export fn PyGC_Collect() callconv(.c) isize {
    if (!gc_enabled) return 0;

    var collected: isize = 0;
    const objects = getTrackedObjects();

    // Mark and sweep: find objects with refcount 0 that are still tracked
    var to_remove = std.ArrayList(*cpython.PyObject).init(allocator);
    defer to_remove.deinit();

    var it = objects.iterator();
    while (it.next()) |entry| {
        const obj = entry.key_ptr.*;
        if (obj.ob_refcnt <= 0) {
            to_remove.append(obj) catch continue;
            collected += 1;
        }
    }

    // Remove collected objects
    for (to_remove.items) |obj| {
        _ = objects.remove(obj);
        // Call finalizer if present
        const type_obj = cpython.Py_TYPE(obj);
        if (type_obj.tp_finalize) |finalize| {
            finalize(obj);
        }
        if (type_obj.tp_dealloc) |dealloc| {
            dealloc(obj);
        }
    }

    return collected;
}

/// Enable automatic garbage collection
export fn PyGC_Enable() callconv(.c) c_int {
    gc_enabled = true;
    return 0;
}

/// Disable automatic garbage collection
export fn PyGC_Disable() callconv(.c) c_int {
    gc_enabled = false;
    return 0;
}

/// Check if GC is enabled
export fn PyGC_IsEnabled() callconv(.c) c_int {
    return if (gc_enabled) 1 else 0;
}

/// Get current GC counts for each generation
export fn PyGC_GetCount(gen0: *isize, gen1: *isize, gen2: *isize) callconv(.c) void {
    gen0.* = @intCast(gc_generation_count[0]);
    gen1.* = @intCast(gc_generation_count[1]);
    gen2.* = @intCast(gc_generation_count[2]);
}

/// Get GC thresholds
export fn PyGC_GetThreshold(threshold0: *c_int, threshold1: *c_int, threshold2: *c_int) callconv(.c) void {
    threshold0.* = @intCast(gc_threshold[0]);
    threshold1.* = @intCast(gc_threshold[1]);
    threshold2.* = @intCast(gc_threshold[2]);
}

/// Set GC thresholds
export fn PyGC_SetThreshold(threshold0: c_int, threshold1: c_int, threshold2: c_int) callconv(.c) void {
    gc_threshold[0] = @intCast(threshold0);
    gc_threshold[1] = @intCast(threshold1);
    gc_threshold[2] = @intCast(threshold2);
}

// ============================================================================
// Object Tracking
// ============================================================================

/// Track object for GC
export fn PyObject_GC_Track(obj: *cpython.PyObject) callconv(.c) void {
    const objects = getTrackedObjects();
    objects.put(obj, {}) catch return;
}

/// Untrack object from GC
export fn PyObject_GC_UnTrack(obj: *cpython.PyObject) callconv(.c) void {
    const objects = getTrackedObjects();
    _ = objects.remove(obj);
}

/// Check if object is tracked
export fn PyObject_GC_IsTracked(obj: *cpython.PyObject) callconv(.c) c_int {
    const objects = getTrackedObjects();
    return if (objects.contains(obj)) 1 else 0;
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
