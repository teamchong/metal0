//! Python 'sqlite3' module - SQLite database interface
//!
//! Provides a Python DB-API 2.0 interface to SQLite databases.
//!
//! Mirrors: CPython Lib/sqlite3/__init__.py
//!
//! This module re-exports all functionality from the sqlite3/ directory.

// Re-export everything from sqlite3/sqlite3.zig (explicit exports for Zig 0.15 compatibility)
const sqlite3_impl = @import("sqlite3/sqlite3.zig");

pub const errors = sqlite3_impl.errors;
pub const types = sqlite3_impl.types;
pub const blob = sqlite3_impl.blob;
pub const dbapi2 = sqlite3_impl.dbapi2;
pub const dump = sqlite3_impl.dump;

pub const sqlite_version = sqlite3_impl.sqlite_version;
pub const sqlite_version_info = sqlite3_impl.sqlite_version_info;
pub const apilevel = sqlite3_impl.apilevel;
pub const threadsafety = sqlite3_impl.threadsafety;
pub const paramstyle = sqlite3_impl.paramstyle;

pub const PARSE_DECLTYPES = sqlite3_impl.PARSE_DECLTYPES;
pub const PARSE_COLNAMES = sqlite3_impl.PARSE_COLNAMES;

pub const Connection = sqlite3_impl.Connection;
pub const ConnectionOptions = sqlite3_impl.ConnectionOptions;
pub const Cursor = sqlite3_impl.Cursor;
pub const RowObject = sqlite3_impl.RowObject;
pub const Blob = sqlite3_impl.Blob;

pub const Error = sqlite3_impl.Error;
pub const Warning = sqlite3_impl.Warning;
pub const InterfaceError = sqlite3_impl.InterfaceError;
pub const DatabaseError = sqlite3_impl.DatabaseError;
pub const DataError = sqlite3_impl.DataError;
pub const OperationalError = sqlite3_impl.OperationalError;
pub const IntegrityError = sqlite3_impl.IntegrityError;
pub const InternalError = sqlite3_impl.InternalError;
pub const ProgrammingError = sqlite3_impl.ProgrammingError;
pub const NotSupportedError = sqlite3_impl.NotSupportedError;

pub const connect = sqlite3_impl.connect;
pub const registerAdapter = sqlite3_impl.registerAdapter;
pub const registerConverter = sqlite3_impl.registerConverter;
