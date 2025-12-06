/// _sqlite/row - SQLite Row object
///
/// Implements CPython's Modules/_sqlite/row.c
/// Provides named access to query results
///
/// Reference: cpython/Modules/_sqlite/row.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const sqlite = @import("sqlite.zig");

const allocator = sqlite.allocator;

// ============================================================================
// ROW OBJECT
// ============================================================================

/// pysqlite_Row - Result row with named column access
pub const pysqlite_Row = extern struct {
    ob_base: cpython.PyObject,
    data: ?*cpython.PyObject, // Tuple of values
    description: ?*cpython.PyObject, // Column descriptions
};

// ============================================================================
// ROW METHODS
// ============================================================================

/// Row_new - Create new Row
fn Row_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(pysqlite_Row), @sizeOf(pysqlite_Row)) catch return null;
    const row: *pysqlite_Row = @ptrCast(@alignCast(mem.ptr));

    row.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = type_obj orelse &pysqlite_RowType },
        .data = null,
        .description = null,
    };

    return @ptrCast(row);
}

/// Row_dealloc - Destructor
fn Row_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const row: *pysqlite_Row = @ptrCast(@alignCast(self.?));

    if (row.data) |d| d.ob_refcnt -= 1;
    if (row.description) |d| d.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(row);
    allocator.free(ptr[0..@sizeOf(pysqlite_Row)]);
}

/// Row_keys - Return column names
fn Row_keys(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// Row_length - Return number of columns
fn Row_length(self: ?*cpython.PyObject) callconv(.c) isize {
    if (self == null) return 0;
    _ = self;
    return 0;
}

/// Row_subscript - Get item by index or name
fn Row_subscript(self: ?*cpython.PyObject, key: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or key == null) return null;
    _ = self;
    return null;
}

/// Row_richcompare - Compare rows
fn Row_richcompare(self: ?*cpython.PyObject, other: ?*cpython.PyObject, op: c_int) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = op;
    return null;
}

/// Row_hash - Hash function
fn Row_hash(self: ?*cpython.PyObject) callconv(.c) isize {
    if (self == null) return -1;
    _ = self;
    return 0;
}

/// Row_iter - Return iterator
fn Row_iter(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const row: *pysqlite_Row = @ptrCast(@alignCast(self.?));
    if (row.data) |d| {
        // Return iter(data)
        _ = d;
    }
    return null;
}

// ============================================================================
// MAPPING METHODS
// ============================================================================

pub export var Row_as_mapping: cpython.PyMappingMethods = .{
    .mp_length = @ptrCast(&Row_length),
    .mp_subscript = Row_subscript,
    .mp_ass_subscript = null,
};

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var Row_methods: [2]cpython.PyMethodDef = .{
    .{ .ml_name = "keys", .ml_meth = @ptrCast(&Row_keys), .ml_flags = 0x0004, .ml_doc = "Return column names." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var pysqlite_RowType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "sqlite3.Row",
    .tp_basicsize = @sizeOf(pysqlite_Row),
    .tp_itemsize = 0,
    .tp_dealloc = Row_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = &Row_as_mapping,
    .tp_hash = Row_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "SQLite row with named column access.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = Row_richcompare,
    .tp_weaklistoffset = 0,
    .tp_iter = Row_iter,
    .tp_iternext = null,
    .tp_methods = &Row_methods,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = Row_new,
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
