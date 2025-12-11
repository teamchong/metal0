//! Python 'sqlite3' module - SQLite database interface
//!
//! Provides a Python DB-API 2.0 interface to SQLite databases.
//!
//! Mirrors: CPython Lib/sqlite3/__init__.py
//!
//! This module re-exports all functionality from the sqlite3/ directory.

// Re-export everything from sqlite3/sqlite3.zig
pub usingnamespace @import("sqlite3/sqlite3.zig");
