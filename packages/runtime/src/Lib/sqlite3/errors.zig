//! SQLite3 error types
//!
//! Mirrors: CPython Lib/sqlite3/__init__.py (exception hierarchy)

// ============================================================================
// Exceptions
// ============================================================================

pub const Error = error{
    Warning,
    InterfaceError,
    DatabaseError,
    DataError,
    OperationalError,
    IntegrityError,
    InternalError,
    ProgrammingError,
    NotSupportedError,
};

pub const Warning = Error.Warning;
pub const InterfaceError = Error.InterfaceError;
pub const DatabaseError = Error.DatabaseError;
pub const DataError = Error.DataError;
pub const OperationalError = Error.OperationalError;
pub const IntegrityError = Error.IntegrityError;
pub const InternalError = Error.InternalError;
pub const ProgrammingError = Error.ProgrammingError;
pub const NotSupportedError = Error.NotSupportedError;
