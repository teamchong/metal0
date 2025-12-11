/// errors - Error Handling
/// Mirrors cpython/Python/fileutils.c error handling
///
/// This module provides error types and handlers for file operations.

const std = @import("std");

// ============================================================================
// Error Handling
// ============================================================================

/// Error handler modes for file operations
pub const ErrorHandler = enum {
    strict, // Raise exception on error
    surrogateescape, // Use surrogate escapes for invalid bytes
    surrogatepass, // Allow surrogates in UTF-16
    ignore, // Ignore errors
    replace, // Replace invalid bytes with replacement char
    backslashreplace, // Use backslash escapes
    xmlcharrefreplace, // Use XML character references
    namereplace, // Use named references
};

/// File operation errors
pub const FileError = error{
    FileNotFound,
    AccessDenied,
    InvalidPath,
    IsDirectory,
    NotDirectory,
    Exists,
    NoSpace,
    InvalidEncoding,
    TooManyOpenFiles,
    BrokenPipe,
    IOError,
    Interrupted,
    Timeout,
    OutOfMemory,
};
