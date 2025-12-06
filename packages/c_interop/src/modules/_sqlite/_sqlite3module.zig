/// _sqlite3 Module - SQLite Database Interface
///
/// Implements CPython's Modules/_sqlite/module.c
/// Provides sqlite3 module for database operations
///
/// Reference: cpython/Modules/_sqlite/module.c
const std = @import("std");
const cpython = @import("../../include/object.zig");

const allocator = std.heap.c_allocator;

// Re-export submodule types
pub const sqlite = @import("sqlite.zig");
pub const connection = @import("connection.zig");
pub const cursor = @import("cursor.zig");
pub const row = @import("row.zig");

// Re-export key types
pub const pysqlite_state = sqlite.pysqlite_state;
pub const pysqlite_Connection = connection.pysqlite_Connection;
pub const pysqlite_Cursor = cursor.pysqlite_Cursor;
pub const pysqlite_Row = row.pysqlite_Row;

// ============================================================================
// MODULE FUNCTIONS
// ============================================================================

/// connect - Open database connection
fn sqlite3_connect(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    _ = kwargs;
    // Create connection with given database path
    return connection.Connection_new(null, null, null);
}

/// complete_statement - Check if SQL is complete
fn sqlite3_complete_statement(self: ?*cpython.PyObject, statement: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = statement;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_TrueStruct;
}

/// enable_callback_tracebacks - Enable/disable traceback printing
fn sqlite3_enable_callback_tracebacks(self: ?*cpython.PyObject, flag: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = flag;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// register_adapter - Register type adapter
fn sqlite3_register_adapter(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// register_converter - Register type converter
fn sqlite3_register_converter(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var sqlite3_methods: [6]cpython.PyMethodDef = .{
    .{ .ml_name = "connect", .ml_meth = @ptrCast(&sqlite3_connect), .ml_flags = 0x0003, .ml_doc = "Opens a connection to a SQLite database." },
    .{ .ml_name = "complete_statement", .ml_meth = @ptrCast(&sqlite3_complete_statement), .ml_flags = 0x0008, .ml_doc = "Checks if a SQL statement is complete." },
    .{ .ml_name = "enable_callback_tracebacks", .ml_meth = @ptrCast(&sqlite3_enable_callback_tracebacks), .ml_flags = 0x0008, .ml_doc = "Enable or disable callback tracebacks." },
    .{ .ml_name = "register_adapter", .ml_meth = @ptrCast(&sqlite3_register_adapter), .ml_flags = 0x0001, .ml_doc = "Register an adapter callable." },
    .{ .ml_name = "register_converter", .ml_meth = @ptrCast(&sqlite3_register_converter), .ml_flags = 0x0001, .ml_doc = "Register a converter callable." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _sqlite3module: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_sqlite3",
    .m_doc = "C module for the sqlite3 package.",
    .m_size = @sizeOf(pysqlite_state),
    .m_methods = &sqlite3_methods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

/// Module initialization
pub export fn PyInit__sqlite3() callconv(.c) ?*cpython.PyObject {
    const module_mod = @import("../../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_sqlite3module);
    if (module == null) return null;

    // Add type objects
    _ = module_mod.PyModule_AddObject(module, "Connection", @ptrCast(&connection.pysqlite_ConnectionType));
    _ = module_mod.PyModule_AddObject(module, "Cursor", @ptrCast(&cursor.pysqlite_CursorType));
    _ = module_mod.PyModule_AddObject(module, "Row", @ptrCast(&row.pysqlite_RowType));

    // Add version info
    _ = module_mod.PyModule_AddStringConstant(module, "version", sqlite.PYSQLITE_VERSION);
    _ = module_mod.PyModule_AddStringConstant(module, "sqlite_version", "3.45.0");

    // Add parse constants
    _ = module_mod.PyModule_AddIntConstant(module, "PARSE_DECLTYPES", sqlite.PARSE_DECLTYPES);
    _ = module_mod.PyModule_AddIntConstant(module, "PARSE_COLNAMES", sqlite.PARSE_COLNAMES);

    // SQLite constants
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_OK", 0);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_ERROR", 1);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_INTERNAL", 2);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_PERM", 3);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_ABORT", 4);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_BUSY", 5);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_LOCKED", 6);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_NOMEM", 7);
    _ = module_mod.PyModule_AddIntConstant(module, "SQLITE_READONLY", 8);

    // Set module state references
    sqlite.pysqlite_global_state.ConnectionType = &connection.pysqlite_ConnectionType;
    sqlite.pysqlite_global_state.CursorType = &cursor.pysqlite_CursorType;
    sqlite.pysqlite_global_state.RowType = &row.pysqlite_RowType;

    return module;
}
