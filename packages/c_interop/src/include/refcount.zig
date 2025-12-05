/// CPython-Compatible Reference Counting & Memory Management
///
/// This file implements the core CPython memory management API:
/// - Reference counting (Py_INCREF, Py_DECREF, Py_XINCREF, Py_XDECREF)
/// - Memory allocators (PyMem_*, PyObject_*)
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

// ============================================================================
// TESTS
// ============================================================================

test "reference counting - basic increment/decrement" {
    const testing = std.testing;

    // Create dummy type (no destructor)
    var dummy_type = cpython.PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = undefined,
            },
            .ob_size = 0,
        },
        .tp_name = "test",
        .tp_basicsize = @sizeOf(cpython.PyObject),
        .tp_itemsize = 0,
        .tp_dealloc = null,
        .tp_repr = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
    };

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
    var type_with_dealloc = cpython.PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = undefined,
            },
            .ob_size = 0,
        },
        .tp_name = "test",
        .tp_basicsize = @sizeOf(cpython.PyObject),
        .tp_itemsize = 0,
        .tp_dealloc = Destructor.dealloc,
        .tp_repr = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
    };

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

    var obj_type = cpython.PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = undefined,
            },
            .ob_size = 0,
        },
        .tp_name = "LifecycleTest",
        .tp_basicsize = @sizeOf(cpython.PyObject),
        .tp_itemsize = 0,
        .tp_dealloc = Tracker.dealloc,
        .tp_repr = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
    };

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
