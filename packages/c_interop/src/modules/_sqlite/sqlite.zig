/// _sqlite/sqlite - Core SQLite types and definitions
///
/// Implements types from CPython's Modules/_sqlite/
/// Provides module state and core structures
///
/// Reference: cpython/Modules/_sqlite/module.h
const std = @import("std");
const cpython = @import("../../include/object.zig");

pub const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

pub const PYSQLITE_VERSION: [:0]const u8 = "2.6.0";
pub const MODULE_NAME: [:0]const u8 = "sqlite3";

pub const LEGACY_TRANSACTION_CONTROL: c_int = -1;
pub const PARSE_DECLTYPES: c_int = 1;
pub const PARSE_COLNAMES: c_int = 2;

// Autocommit modes
pub const AUTOCOMMIT_LEGACY: c_int = LEGACY_TRANSACTION_CONTROL;
pub const AUTOCOMMIT_ENABLED: c_int = 1;
pub const AUTOCOMMIT_DISABLED: c_int = 0;

// ============================================================================
// SQLITE HANDLE (opaque)
// ============================================================================

/// sqlite3 - Opaque database handle
pub const sqlite3 = opaque {};

/// sqlite3_stmt - Opaque statement handle
pub const sqlite3_stmt = opaque {};

/// sqlite3_blob - Opaque blob handle
pub const sqlite3_blob = opaque {};

// ============================================================================
// CALLBACK CONTEXT
// ============================================================================

/// callback_context - Context for Python callbacks
pub const callback_context = extern struct {
    callable: ?*cpython.PyObject,
    module: ?*cpython.PyObject,
    state: ?*pysqlite_state,
};

// ============================================================================
// MODULE STATE
// ============================================================================

/// pysqlite_state - Module state
pub const pysqlite_state = extern struct {
    // Exception types
    DataError: ?*cpython.PyObject,
    DatabaseError: ?*cpython.PyObject,
    Error: ?*cpython.PyObject,
    IntegrityError: ?*cpython.PyObject,
    InterfaceError: ?*cpython.PyObject,
    InternalError: ?*cpython.PyObject,
    NotSupportedError: ?*cpython.PyObject,
    OperationalError: ?*cpython.PyObject,
    ProgrammingError: ?*cpython.PyObject,
    Warning: ?*cpython.PyObject,

    // Converter registry
    converters: ?*cpython.PyObject,

    // Cache and adapters
    lru_cache: ?*cpython.PyObject,
    psyco_adapters: ?*cpython.PyObject,
    BaseTypeAdapted: c_int,
    enable_callback_tracebacks: c_int,

    // Type objects
    BlobType: ?*cpython.PyTypeObject,
    ConnectionType: ?*cpython.PyTypeObject,
    CursorType: ?*cpython.PyTypeObject,
    PrepareProtocolType: ?*cpython.PyTypeObject,
    RowType: ?*cpython.PyTypeObject,
    StatementType: ?*cpython.PyTypeObject,

    // Interned strings
    str___adapt__: ?*cpython.PyObject,
    str___conform__: ?*cpython.PyObject,
    str_executescript: ?*cpython.PyObject,
    str_finalize: ?*cpython.PyObject,
    str_inverse: ?*cpython.PyObject,
    str_step: ?*cpython.PyObject,
    str_upper: ?*cpython.PyObject,
    str_value: ?*cpython.PyObject,
};

/// Global module state
pub var pysqlite_global_state: pysqlite_state = .{
    .DataError = null,
    .DatabaseError = null,
    .Error = null,
    .IntegrityError = null,
    .InterfaceError = null,
    .InternalError = null,
    .NotSupportedError = null,
    .OperationalError = null,
    .ProgrammingError = null,
    .Warning = null,
    .converters = null,
    .lru_cache = null,
    .psyco_adapters = null,
    .BaseTypeAdapted = 0,
    .enable_callback_tracebacks = 0,
    .BlobType = null,
    .ConnectionType = null,
    .CursorType = null,
    .PrepareProtocolType = null,
    .RowType = null,
    .StatementType = null,
    .str___adapt__ = null,
    .str___conform__ = null,
    .str_executescript = null,
    .str_finalize = null,
    .str_inverse = null,
    .str_step = null,
    .str_upper = null,
    .str_value = null,
};

// ============================================================================
// ERROR HANDLING
// ============================================================================

/// Get error name for SQLite result code
pub export fn pysqlite_error_name(rc: c_int) callconv(.c) ?[*:0]const u8 {
    return switch (rc) {
        0 => "SQLITE_OK",
        1 => "SQLITE_ERROR",
        2 => "SQLITE_INTERNAL",
        3 => "SQLITE_PERM",
        4 => "SQLITE_ABORT",
        5 => "SQLITE_BUSY",
        6 => "SQLITE_LOCKED",
        7 => "SQLITE_NOMEM",
        8 => "SQLITE_READONLY",
        9 => "SQLITE_INTERRUPT",
        10 => "SQLITE_IOERR",
        11 => "SQLITE_CORRUPT",
        12 => "SQLITE_NOTFOUND",
        13 => "SQLITE_FULL",
        14 => "SQLITE_CANTOPEN",
        15 => "SQLITE_PROTOCOL",
        16 => "SQLITE_EMPTY",
        17 => "SQLITE_SCHEMA",
        18 => "SQLITE_TOOBIG",
        19 => "SQLITE_CONSTRAINT",
        20 => "SQLITE_MISMATCH",
        21 => "SQLITE_MISUSE",
        22 => "SQLITE_NOLFS",
        23 => "SQLITE_AUTH",
        24 => "SQLITE_FORMAT",
        25 => "SQLITE_RANGE",
        26 => "SQLITE_NOTADB",
        27 => "SQLITE_NOTICE",
        28 => "SQLITE_WARNING",
        100 => "SQLITE_ROW",
        101 => "SQLITE_DONE",
        else => null,
    };
}
