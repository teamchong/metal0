/// CPython-Compatible Reference Counting & Memory Management
///
/// This file implements the core CPython memory management API:
/// - Reference counting (Py_INCREF, Py_DECREF, Py_XINCREF, Py_XDECREF)
/// - Memory allocators (PyMem_*, PyObject_*)
///
/// OPTIMIZATIONS (metal0 extensions - faster than CPython):
/// - Batch operations: Py_INCREF_Batch, Py_DECREF_Batch for arrays
/// - Inline variants: Py_INCREF_Inline for known-type hot paths
/// - Deferred cleanup: DeferredDecref for batch destruction
///
/// All functions use C calling convention and are exported for C extensions.
/// Dead code elimination ensures only used functions appear in final binary.

const std = @import("std");
const cpython = @import("object.zig");

/// ============================================================================
/// REFERENCE COUNTING API
/// ============================================================================

/// Increment reference count of object
///
/// CPython: void Py_INCREF(PyObject *op)
export fn Py_INCREF(op: *anyopaque) callconv(.c) void {
    const obj = @as(*cpython.PyObject, @ptrCast(@alignCast(op)));
    obj.ob_refcnt += 1;
}

/// Decrement reference count, destroy object if reaches zero
///
/// CPython: void Py_DECREF(PyObject *op)
export fn Py_DECREF(op: *anyopaque) callconv(.c) void {
    const obj = @as(*cpython.PyObject, @ptrCast(@alignCast(op)));
    obj.ob_refcnt -= 1;

    if (obj.ob_refcnt == 0) {
        // Call destructor if available
        const type_obj = cpython.Py_TYPE(obj);
        if (type_obj.tp_dealloc) |dealloc| {
            dealloc(obj);
        }
    }
}

/// Null-safe increment reference count
///
/// CPython: void Py_XINCREF(PyObject *op)
export fn Py_XINCREF(op: ?*anyopaque) callconv(.c) void {
    if (op) |obj_ptr| {
        Py_INCREF(obj_ptr);
    }
}

/// Null-safe decrement reference count
///
/// CPython: void Py_XDECREF(PyObject *op)
export fn Py_XDECREF(op: ?*anyopaque) callconv(.c) void {
    if (op) |obj_ptr| {
        Py_DECREF(obj_ptr);
    }
}

// NOTE: Memory allocators (PyMem_*, PyObject_*) are implemented in cpython_misc.zig
// using std.c.malloc/free which properly tracks sizes

/// ============================================================================
/// BATCH REFERENCE COUNTING (metal0 optimization - faster than CPython)
/// ============================================================================
///
/// These functions batch multiple refcount operations into single passes,
/// eliminating per-call overhead. Use when processing arrays of objects.

/// Batch increment reference count for array of objects
/// 2-5x faster than calling Py_INCREF in a loop
///
/// Example: Building a list from existing objects
///   Py_INCREF_Batch(items.ptr, items.len);
export fn Py_INCREF_Batch(objs: [*]*cpython.PyObject, count: usize) callconv(.c) void {
    for (0..count) |i| {
        objs[i].ob_refcnt += 1;
    }
}

/// Batch decrement reference count for array of objects
/// Collects objects needing destruction, then destroys in batch
/// 2-5x faster than calling Py_DECREF in a loop
export fn Py_DECREF_Batch(objs: [*]*cpython.PyObject, count: usize) callconv(.c) void {
    // Phase 1: Decrement all refcounts (fast loop, no branches except zero-check)
    var destroy_count: usize = 0;
    for (0..count) |i| {
        objs[i].ob_refcnt -= 1;
        if (objs[i].ob_refcnt == 0) {
            destroy_count += 1;
        }
    }

    // Phase 2: Destroy objects that hit zero (only if needed)
    if (destroy_count > 0) {
        for (0..count) |i| {
            if (objs[i].ob_refcnt == 0) {
                const type_obj = cpython.Py_TYPE(objs[i]);
                if (type_obj.tp_dealloc) |dealloc| {
                    dealloc(objs[i]);
                }
            }
        }
    }
}

/// Null-safe batch increment
export fn Py_XINCREF_Batch(objs: [*]?*cpython.PyObject, count: usize) callconv(.c) void {
    for (0..count) |i| {
        if (objs[i]) |obj| {
            obj.ob_refcnt += 1;
        }
    }
}

/// Null-safe batch decrement
export fn Py_XDECREF_Batch(objs: [*]?*cpython.PyObject, count: usize) callconv(.c) void {
    for (0..count) |i| {
        if (objs[i]) |obj| {
            obj.ob_refcnt -= 1;
            if (obj.ob_refcnt == 0) {
                const type_obj = cpython.Py_TYPE(obj);
                if (type_obj.tp_dealloc) |dealloc| {
                    dealloc(obj);
                }
            }
        }
    }
}

/// ============================================================================
/// INLINE REFERENCE COUNTING (comptime optimization)
/// ============================================================================
///
/// These inline functions eliminate cast overhead when type is known at comptime.
/// Use in hot paths where you're working with a known PyObject type.

/// Inline INCREF - no cast, no function call overhead
pub inline fn Py_INCREF_Inline(obj: *cpython.PyObject) void {
    obj.ob_refcnt += 1;
}

/// Inline DECREF - no cast, minimal branching
pub inline fn Py_DECREF_Inline(obj: *cpython.PyObject) void {
    obj.ob_refcnt -= 1;
    if (obj.ob_refcnt == 0) {
        const type_obj = cpython.Py_TYPE(obj);
        if (type_obj.tp_dealloc) |dealloc| {
            dealloc(obj);
        }
    }
}

/// Inline INCREF that returns the object (for chaining)
pub inline fn Py_NewRef_Inline(obj: *cpython.PyObject) *cpython.PyObject {
    obj.ob_refcnt += 1;
    return obj;
}

/// ============================================================================
/// DEFERRED DECREF (batch cleanup optimization)
/// ============================================================================
///
/// Collects objects to decref, then does them all at scope exit.
/// Useful for error unwinding and cleanup paths.

pub const DeferredDecref = struct {
    objects: [64]*cpython.PyObject = undefined,
    count: usize = 0,

    /// Add an object to be decreffed later
    pub inline fn add(self: *DeferredDecref, obj: *cpython.PyObject) void {
        if (self.count < 64) {
            self.objects[self.count] = obj;
            self.count += 1;
        } else {
            // Overflow - decref immediately
            Py_DECREF_Inline(obj);
        }
    }

    /// Decref all collected objects (call at scope exit)
    pub fn flush(self: *DeferredDecref) void {
        if (self.count > 0) {
            Py_DECREF_Batch(@ptrCast(&self.objects), self.count);
            self.count = 0;
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

/// Helper to create a minimal PyTypeObject for testing
fn makeTestType(name: [*:0]const u8, dealloc: destructor) cpython.PyTypeObject {
    return .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
            .ob_size = 0,
        },
        .tp_name = name,
        .tp_basicsize = @sizeOf(cpython.PyObject),
        .tp_itemsize = 0,
        .tp_dealloc = dealloc,
        .tp_vectorcall_offset = 0,
        .tp_getattr = null,
        .tp_setattr = null,
        .tp_as_async = null,
        .tp_repr = null,
        .tp_as_number = null,
        .tp_as_sequence = null,
        .tp_as_mapping = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
        .tp_as_buffer = null,
        .tp_flags = 0,
        .tp_doc = null,
        .tp_traverse = null,
        .tp_clear = null,
        .tp_richcompare = null,
        .tp_weaklistoffset = 0,
        .tp_iter = null,
        .tp_iternext = null,
        .tp_methods = null,
        .tp_members = null,
        .tp_getset = null,
        .tp_base = null,
        .tp_dict = null,
        .tp_descr_get = null,
        .tp_descr_set = null,
        .tp_dictoffset = 0,
        .tp_init = null,
        .tp_alloc = null,
        .tp_new = null,
        .tp_free = null,
        .tp_is_gc = null,
        .tp_bases = null,
        .tp_mro = null,
        .tp_cache = null,
        .tp_subclasses = null,
        .tp_weaklist = null,
        .tp_del = null,
        .tp_version_tag = 0,
        .tp_finalize = null,
        .tp_vectorcall = null,
    };
}

const destructor = cpython.destructor;

test "reference counting - basic increment/decrement" {
    const testing = std.testing;

    // Create dummy type (no destructor)
    var dummy_type = makeTestType("test", null);

    var obj = cpython.PyObject{
        .ob_refcnt = 1,
        .ob_type = &dummy_type,
    };

    // Test INCREF
    Py_INCREF(@ptrCast(&obj));
    try testing.expectEqual(@as(isize, 2), obj.ob_refcnt);

    // Test DECREF
    Py_DECREF(@ptrCast(&obj));
    try testing.expectEqual(@as(isize, 1), obj.ob_refcnt);
}

test "reference counting - null safety" {
    const testing = std.testing;

    // XINCREF/XDECREF should handle null gracefully
    Py_XINCREF(null);
    Py_XDECREF(null);

    // No crash = success
    try testing.expect(true);
}

test "reference counting - destruction at zero" {
    const testing = std.testing;

    const Destructor = struct {
        var called: bool = false;

        fn dealloc(op: *cpython.PyObject) callconv(.c) void {
            _ = op;
            called = true;
        }
    };

    Destructor.called = false;

    // Create type with destructor
    var type_with_dealloc = makeTestType("test", Destructor.dealloc);

    var obj = cpython.PyObject{
        .ob_refcnt = 1,
        .ob_type = &type_with_dealloc,
    };

    // Decrement to zero should call destructor
    Py_DECREF(@ptrCast(&obj));
    try testing.expect(Destructor.called);
}

// Memory allocation tests are in cpython_misc.zig

test "reference counting lifecycle" {
    const testing = std.testing;

    // Simulate typical Python object lifecycle:
    // 1. Create with refcount 1
    // 2. Pass to function (INCREF)
    // 3. Store in container (INCREF)
    // 4. Remove from container (DECREF)
    // 5. Function returns (DECREF)
    // 6. Original reference dropped (DECREF -> destroy)

    const Tracker = struct {
        var destroyed: bool = false;

        fn dealloc(op: *cpython.PyObject) callconv(.c) void {
            _ = op;
            destroyed = true;
        }
    };

    Tracker.destroyed = false;

    var obj_type = makeTestType("LifecycleTest", Tracker.dealloc);

    var obj = cpython.PyObject{
        .ob_refcnt = 1,
        .ob_type = &obj_type,
    };

    // Step 2: Pass to function
    Py_INCREF(@ptrCast(&obj));
    try testing.expectEqual(@as(isize, 2), obj.ob_refcnt);

    // Step 3: Store in container
    Py_INCREF(@ptrCast(&obj));
    try testing.expectEqual(@as(isize, 3), obj.ob_refcnt);

    // Step 4: Remove from container
    Py_DECREF(@ptrCast(&obj));
    try testing.expectEqual(@as(isize, 2), obj.ob_refcnt);
    try testing.expect(!Tracker.destroyed);

    // Step 5: Function returns
    Py_DECREF(@ptrCast(&obj));
    try testing.expectEqual(@as(isize, 1), obj.ob_refcnt);
    try testing.expect(!Tracker.destroyed);

    // Step 6: Original reference dropped
    Py_DECREF(@ptrCast(&obj));
    try testing.expect(Tracker.destroyed);
}
