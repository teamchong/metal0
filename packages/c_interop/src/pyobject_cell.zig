/// PyCellObject - Cell objects for closure variables
///
/// Cells are used to implement closures in Python. They hold references
/// to variables that are shared between nested scopes.
///
/// Reference: cpython/Include/cpython/cellobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITION
// ============================================================================

/// PyCellObject - holds a reference to a free variable
pub const PyCellObject = extern struct {
    ob_base: cpython.PyObject,
    ob_ref: ?*cpython.PyObject, // The contained object (can be null)
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyCell_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "cell",
    .tp_basicsize = @sizeOf(PyCellObject),
    .tp_itemsize = 0,
    .tp_dealloc = cell_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = cell_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "cell(contents=<empty cell>)\n\nCreate a new cell object.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = cell_richcompare,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

// ============================================================================
// API FUNCTIONS
// ============================================================================

/// Create a new cell object containing `obj`
/// If obj is null, creates an empty cell
pub export fn PyCell_New(obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const cell = allocator.create(PyCellObject) catch return null;

    cell.ob_base.ob_refcnt = 1;
    cell.ob_base.ob_type = &PyCell_Type;
    cell.ob_ref = if (obj) |o| traits.incref(o) else null;

    return @ptrCast(&cell.ob_base);
}

/// Get the contents of a cell object
/// Returns borrowed reference (or null if empty)
pub export fn PyCell_Get(cell: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyCell_Check(cell) == 0) {
        traits.setError("TypeError", "PyCell_Get: not a cell");
        return null;
    }

    const cell_obj: *PyCellObject = @ptrCast(@alignCast(cell));
    if (cell_obj.ob_ref) |ref| {
        return traits.incref(ref); // Return new reference
    }
    return null;
}

/// Get the contents of a cell (macro version - no error checking)
pub export fn PyCell_GET(cell: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const cell_obj: *PyCellObject = @ptrCast(@alignCast(cell));
    return cell_obj.ob_ref;
}

/// Set the contents of a cell object
/// Steals reference to obj
pub export fn PyCell_Set(cell: *cpython.PyObject, obj: ?*cpython.PyObject) callconv(.c) c_int {
    if (PyCell_Check(cell) == 0) {
        traits.setError("TypeError", "PyCell_Set: not a cell");
        return -1;
    }

    const cell_obj: *PyCellObject = @ptrCast(@alignCast(cell));

    // Decref old contents
    if (cell_obj.ob_ref) |old| {
        traits.decref(old);
    }

    // Set new contents (steals reference)
    cell_obj.ob_ref = obj;
    return 0;
}

/// Set contents (macro version - no error checking)
pub export fn PyCell_SET(cell: *cpython.PyObject, obj: ?*cpython.PyObject) callconv(.c) void {
    const cell_obj: *PyCellObject = @ptrCast(@alignCast(cell));
    if (cell_obj.ob_ref) |old| {
        traits.decref(old);
    }
    cell_obj.ob_ref = obj;
}

/// Check if object is a cell
pub export fn PyCell_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCell_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn cell_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const cell: *PyCellObject = @ptrCast(@alignCast(obj));
    if (cell.ob_ref) |ref| {
        traits.decref(ref);
    }
    allocator.destroy(cell);
}

fn cell_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const cell: *PyCellObject = @ptrCast(@alignCast(obj));
    const unicode = @import("cpython_unicode.zig");

    var buf: [128]u8 = undefined;
    if (cell.ob_ref) |_| {
        const str = std.fmt.bufPrint(&buf, "<cell at 0x{x}: object>", .{@intFromPtr(obj)}) catch return null;
        return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
    } else {
        const str = std.fmt.bufPrint(&buf, "<cell at 0x{x}: empty>", .{@intFromPtr(obj)}) catch return null;
        return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
    }
}

fn cell_richcompare(a: *cpython.PyObject, b: *cpython.PyObject, op: c_int) callconv(.c) ?*cpython.PyObject {
    const bool_mod = @import("pyobject_bool.zig");

    if (PyCell_Check(a) == 0 or PyCell_Check(b) == 0) {
        return bool_mod.PyBool_FromLong(0);
    }

    const cell_a: *PyCellObject = @ptrCast(@alignCast(a));
    const cell_b: *PyCellObject = @ptrCast(@alignCast(b));

    // Only EQ and NE are supported
    const Py_EQ: c_int = 2;
    const Py_NE: c_int = 3;

    if (op == Py_EQ) {
        return bool_mod.PyBool_FromLong(if (cell_a.ob_ref == cell_b.ob_ref) 1 else 0);
    } else if (op == Py_NE) {
        return bool_mod.PyBool_FromLong(if (cell_a.ob_ref != cell_b.ob_ref) 1 else 0);
    }

    traits.setError("TypeError", "cells only support == and !=");
    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyCellObject layout" {
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyCellObject, "ob_ref"));
}

test "PyCell_New and Get" {
    _ = PyCell_New;
    _ = PyCell_Get;
    _ = PyCell_Set;
    _ = PyCell_Check;
}
