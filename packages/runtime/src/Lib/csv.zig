//! CPython source: Lib/csv.py
//!
//! Provides classes for reading and writing tabular data in CSV format.
//!
//! Mirrors: CPython Lib/csv.py

// ============================================================================
// Module Structure
// ============================================================================
//
// This module is organized as follows:
//   - types.zig      - Dialect, constants, error types, registry
//   - reader.zig     - Reader and DictReader classes
//   - writer.zig     - Writer and DictWriter classes
//   - sniffer.zig    - Sniffer class for format detection
//
// ============================================================================

const types = @import("csv/types.zig");
const reader_mod = @import("csv/reader.zig");
const writer_mod = @import("csv/writer.zig");
const sniffer_mod = @import("csv/sniffer.zig");

// ============================================================================
// Re-export all public APIs
// ============================================================================

// Types and constants
pub const Dialect = types.Dialect;
pub const QUOTE_MINIMAL = types.QUOTE_MINIMAL;
pub const QUOTE_ALL = types.QUOTE_ALL;
pub const QUOTE_NONNUMERIC = types.QUOTE_NONNUMERIC;
pub const QUOTE_NONE = types.QUOTE_NONE;
pub const QUOTE_STRINGS = types.QUOTE_STRINGS;
pub const QUOTE_NOTNULL = types.QUOTE_NOTNULL;
pub const Error = types.Error;

// Reader classes
pub const Reader = reader_mod.Reader;
pub const DictReader = reader_mod.DictReader;

// Writer classes
pub const Writer = writer_mod.Writer;
pub const DictWriter = writer_mod.DictWriter;

// Sniffer
pub const Sniffer = sniffer_mod.Sniffer;

// Convenience functions
pub const reader = reader_mod.reader;
pub const dictReader = reader_mod.dictReader;
pub const writer = writer_mod.writer;
pub const dictWriter = writer_mod.dictWriter;

// Dialect registry functions
pub const registerDialect = types.registerDialect;
pub const getDialect = types.getDialect;
pub const unregisterDialect = types.unregisterDialect;
pub const listDialects = types.listDialects;

// Field size limit functions
pub const getFieldSizeLimit = types.getFieldSizeLimit;
pub const setFieldSizeLimit = types.setFieldSizeLimit;
