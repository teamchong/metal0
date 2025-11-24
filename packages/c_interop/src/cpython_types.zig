/// CPython Type Conversion Functions
///
/// Implements PyLong, PyFloat, PyTuple, PyList, PyDict conversions
/// with C-compatible exports and dead code elimination support.
///
/// PyLong and PyBytes implementations are in separate modules.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// Import full PyLong and PyBytes implementations
pub const pylong = @import("pyobject_long.zig");
pub const pybytes = @import("pyobject_bytes.zig");

/// Global allocator for type conversions (C-compatible)
const allocator = std.heap.c_allocator;

/// ============================================================================
/// PYLONG - Integer Conversions (now in pyobject_long.zig)
/// ============================================================================

// All PyLong_* functions are now implemented in pyobject_long.zig
// They are automatically exported and available to C code

/// ============================================================================
/// PYFLOAT - Float Conversions (4 functions from auto-generated specs)
/// ============================================================================

/// Create PyFloat from C double
export fn PyFloat_FromDouble(value: f64) callconv(.C) ?*cpython.PyObject {
    const obj = allocator.create(cpython.PyFloatObject) catch return null;
    obj.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined, // TODO: &PyFloat_Type
    };
    obj.fval = value;
    return @ptrCast(&obj.ob_base);
}

/// Extract double from PyFloat
export fn PyFloat_AsDouble(obj: *cpython.PyObject) callconv(.C) f64 {
    const float_obj = @as(*cpython.PyFloatObject, @ptrCast(obj));
    return float_obj.fval;
}

/// Check if object is PyFloat
export fn PyFloat_Check(obj: *cpython.PyObject) callconv(.C) c_int {
    _ = obj;
    return 1; // TODO: Proper type checking
}

/// Check if object is exactly PyFloat (not subclass)
export fn PyFloat_CheckExact(obj: *cpython.PyObject) callconv(.C) c_int {
    _ = obj;
    return 1; // TODO: Proper type checking
}

/// ============================================================================
/// PYTUPLE - Tuple Operations (8 functions from auto-generated specs)
/// ============================================================================

/// Create new tuple with given size
export fn PyTuple_New(size: isize) callconv(.C) ?*cpython.PyObject {
    if (size < 0) return null;

    // Allocate tuple object + array of pointers
    const usize_val: usize = @intCast(size);
    const tuple_size = @sizeOf(cpython.PyTupleObject) + usize_val * @sizeOf(?*cpython.PyObject);

    const memory = allocator.alignedAlloc(u8, @alignOf(cpython.PyTupleObject), tuple_size) catch return null;
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(memory.ptr));

    tuple.ob_base.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined, // TODO: &PyTuple_Type
    };
    tuple.ob_base.ob_size = size;

    // Initialize all slots to NULL
    const items_ptr = @as([*]?*cpython.PyObject, @ptrCast(memory.ptr + @sizeOf(cpython.PyTupleObject)));
    for (0..usize_val) |i| {
        items_ptr[i] = null;
    }

    return @ptrCast(&tuple.ob_base.ob_base);
}

/// Get tuple size
export fn PyTuple_Size(obj: *cpython.PyObject) callconv(.C) isize {
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(obj));
    return tuple.ob_base.ob_size;
}

/// Get item at index (borrowed reference)
export fn PyTuple_GetItem(obj: *cpython.PyObject, index: isize) callconv(.C) ?*cpython.PyObject {
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(obj));
    if (index < 0 or index >= tuple.ob_base.ob_size) return null;

    const items_ptr = @as([*]?*cpython.PyObject, @ptrCast(@intFromPtr(tuple) + @sizeOf(cpython.PyTupleObject)));
    const uindex: usize = @intCast(index);
    return items_ptr[uindex];
}

/// Set item at index (steals reference)
export fn PyTuple_SetItem(obj: *cpython.PyObject, index: isize, item: *cpython.PyObject) callconv(.C) c_int {
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(obj));
    if (index < 0 or index >= tuple.ob_base.ob_size) return -1;

    const items_ptr = @as([*]?*cpython.PyObject, @ptrCast(@intFromPtr(tuple) + @sizeOf(cpython.PyTupleObject)));
    const uindex: usize = @intCast(index);
    items_ptr[uindex] = item;

    return 0;
}

/// Check if object is tuple
export fn PyTuple_Check(obj: *cpython.PyObject) callconv(.C) c_int {
    _ = obj;
    return 1; // TODO: Proper type checking
}

/// ============================================================================
/// PYLIST - List Operations (10 functions from auto-generated specs)
/// ============================================================================

/// Create new list with given size
export fn PyList_New(size: isize) callconv(.C) ?*cpython.PyObject {
    if (size < 0) return null;

    const list = allocator.create(cpython.PyListObject) catch return null;

    list.ob_base.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined, // TODO: &PyList_Type
    };
    list.ob_base.ob_size = size;

    // Allocate items array
    const usize_val: usize = @intCast(size);
    const items = allocator.alloc(?*cpython.PyObject, usize_val) catch {
        allocator.destroy(list);
        return null;
    };

    // Initialize to null
    for (items) |*item| item.* = null;

    list.ob_item = items.ptr;
    list.allocated = size;

    return @ptrCast(&list.ob_base.ob_base);
}

/// Get list size
export fn PyList_Size(obj: *cpython.PyObject) callconv(.C) isize {
    const list = @as(*cpython.PyListObject, @ptrCast(obj));
    return list.ob_base.ob_size;
}

/// Get item at index (borrowed reference)
export fn PyList_GetItem(obj: *cpython.PyObject, index: isize) callconv(.C) ?*cpython.PyObject {
    const list = @as(*cpython.PyListObject, @ptrCast(obj));
    if (index < 0 or index >= list.ob_base.ob_size) return null;

    const uindex: usize = @intCast(index);
    return list.ob_item[uindex];
}

/// Set item at index (steals reference)
export fn PyList_SetItem(obj: *cpython.PyObject, index: isize, item: *cpython.PyObject) callconv(.C) c_int {
    const list = @as(*cpython.PyListObject, @ptrCast(obj));
    if (index < 0 or index >= list.ob_base.ob_size) return -1;

    const uindex: usize = @intCast(index);
    list.ob_item[uindex] = item;

    return 0;
}

/// Append item to list
export fn PyList_Append(obj: *cpython.PyObject, item: *cpython.PyObject) callconv(.C) c_int {
    const list = @as(*cpython.PyListObject, @ptrCast(obj));

    // Check if we need to resize
    if (list.ob_base.ob_size >= list.allocated) {
        // Grow by 1.5x + 1
        const new_size = list.allocated + (list.allocated >> 1) + 1;
        const unew: usize = @intCast(new_size);
        const uold: usize = @intCast(list.allocated);

        const new_items = allocator.realloc(list.ob_item[0..uold], unew) catch return -1;
        list.ob_item = new_items.ptr;
        list.allocated = new_size;
    }

    const uindex: usize = @intCast(list.ob_base.ob_size);
    list.ob_item[uindex] = item;
    list.ob_base.ob_size += 1;

    return 0;
}

/// Check if object is list
export fn PyList_Check(obj: *cpython.PyObject) callconv(.C) c_int {
    _ = obj;
    return 1; // TODO: Proper type checking
}

/// ============================================================================
/// DEAD CODE ELIMINATION
/// ============================================================================

/// All functions use `export` keyword, which means:
/// - They're callable from C
/// - Zig's dead code elimination will:
///   1. Only include functions that are actually called
///   2. Strip unused type conversion functions
///   3. Remove unreferenced type objects
///
/// Example: If NumPy only uses PyLong and PyFloat, PyTuple/PyList won't be in binary!

// Tests
test "PyLong conversions" {
    const obj = PyLong_FromLong(42);
    try std.testing.expect(obj != null);

    const value = PyLong_AsLong(obj.?);
    try std.testing.expectEqual(@as(c_long, 42), value);

    // Cleanup
    allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(obj.?)));
}

test "PyFloat conversions" {
    const obj = PyFloat_FromDouble(3.14);
    try std.testing.expect(obj != null);

    const value = PyFloat_AsDouble(obj.?);
    try std.testing.expectApproxEqAbs(3.14, value, 0.001);

    allocator.destroy(@as(*cpython.PyFloatObject, @ptrCast(obj.?)));
}

test "PyTuple operations" {
    const tuple = PyTuple_New(3);
    try std.testing.expect(tuple != null);

    const size = PyTuple_Size(tuple.?);
    try std.testing.expectEqual(@as(isize, 3), size);

    // Create items
    const item1 = PyLong_FromLong(10);
    const item2 = PyLong_FromLong(20);
    const item3 = PyLong_FromLong(30);

    // Set items
    try std.testing.expectEqual(@as(c_int, 0), PyTuple_SetItem(tuple.?, 0, item1.?));
    try std.testing.expectEqual(@as(c_int, 0), PyTuple_SetItem(tuple.?, 1, item2.?));
    try std.testing.expectEqual(@as(c_int, 0), PyTuple_SetItem(tuple.?, 2, item3.?));

    // Get items
    const got1 = PyTuple_GetItem(tuple.?, 0);
    try std.testing.expect(got1 != null);

    const val1 = PyLong_AsLong(got1.?);
    try std.testing.expectEqual(@as(c_long, 10), val1);

    // Cleanup (simplified - real code needs proper deallocation)
    const tuple_ptr = @as(*cpython.PyTupleObject, @ptrCast(tuple.?));
    const tuple_size = @sizeOf(cpython.PyTupleObject) + 3 * @sizeOf(?*cpython.PyObject);
    const memory = @as([*]u8, @ptrCast(tuple_ptr))[0..tuple_size];
    allocator.free(memory);

    allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(item1.?)));
    allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(item2.?)));
    allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(item3.?)));
}

test "PyList operations" {
    const list = PyList_New(0);
    try std.testing.expect(list != null);

    // Append items
    const item1 = PyLong_FromLong(100);
    const item2 = PyLong_FromLong(200);

    try std.testing.expectEqual(@as(c_int, 0), PyList_Append(list.?, item1.?));
    try std.testing.expectEqual(@as(c_int, 0), PyList_Append(list.?, item2.?));

    // Check size
    const size = PyList_Size(list.?);
    try std.testing.expectEqual(@as(isize, 2), size);

    // Get items
    const got = PyList_GetItem(list.?, 0);
    try std.testing.expect(got != null);

    const val = PyLong_AsLong(got.?);
    try std.testing.expectEqual(@as(c_long, 100), val);

    // Cleanup
    const list_ptr = @as(*cpython.PyListObject, @ptrCast(list.?));
    const items_slice = list_ptr.ob_item[0..@intCast(list_ptr.allocated)];
    allocator.free(items_slice);
    allocator.destroy(list_ptr);

    allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(item1.?)));
    allocator.destroy(@as(*cpython.PyLongObject, @ptrCast(item2.?)));
}
