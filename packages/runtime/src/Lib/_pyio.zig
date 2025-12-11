/// _pyio - Python I/O Implementation
/// Mirrors cpython/Lib/_pyio.py
///
/// Pure Zig implementation of Python's buffered I/O classes.
/// Provides the underlying implementation for io module.
///
/// Structure:
/// - types.zig: Core types (IOMode, SeekWhence, IOError, TextNewline)
/// - base.zig: IOBase abstract interface
/// - raw.zig: FileIO for unbuffered file operations
/// - buffered.zig: BufferedReader and BufferedWriter
/// - text.zig: TextIOWrapper for text encoding
/// - string_io.zig: StringIO and BytesIO for in-memory streams
/// - module.zig: Module initialization and state

// Re-export all public APIs
pub const types = @import("_pyio/types.zig");
pub const base = @import("_pyio/base.zig");
pub const raw = @import("_pyio/raw.zig");
pub const buffered = @import("_pyio/buffered.zig");
pub const text = @import("_pyio/text.zig");
pub const string_io = @import("_pyio/string_io.zig");
pub const module = @import("_pyio/module.zig");

// Re-export commonly used types at top level for convenience
pub const IOMode = types.IOMode;
pub const SeekWhence = types.SeekWhence;
pub const IOError = types.IOError;
pub const TextNewline = types.TextNewline;
pub const DEFAULT_BUFFER_SIZE = types.DEFAULT_BUFFER_SIZE;

pub const IOBase = base.IOBase;
pub const FileIO = raw.FileIO;
pub const BufferedReader = buffered.BufferedReader;
pub const BufferedWriter = buffered.BufferedWriter;
pub const TextIOWrapper = text.TextIOWrapper;
pub const StringIO = string_io.StringIO;
pub const BytesIO = string_io.BytesIO;

// Re-export module functions
pub const init = module.init;
pub const reset = module.reset;
