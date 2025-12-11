/// fileutils - File Utilities
/// Mirrors cpython/Python/fileutils.c
///
/// This module provides low-level file system utilities used by the Python runtime:
/// - File descriptor operations (open, close, read, write)
/// - Path manipulation and validation
/// - Encoding detection and conversion
/// - File mode handling (text/binary)
/// - Cross-platform file system operations

const std = @import("std");

// Re-export submodules
pub const errors = @import("fileutils/errors.zig");
pub const fd_ops = @import("fileutils/fd_ops.zig");
pub const path_ops = @import("fileutils/path_ops.zig");
pub const encoding = @import("fileutils/encoding.zig");
pub const mode = @import("fileutils/mode.zig");
pub const stat = @import("fileutils/stat.zig");
pub const dir_ops = @import("fileutils/dir_ops.zig");
pub const file_ops = @import("fileutils/file_ops.zig");
pub const cwd = @import("fileutils/cwd.zig");

// Re-export commonly used types and functions
pub const ErrorHandler = errors.ErrorHandler;
pub const FileError = errors.FileError;
pub const OpenFlags = fd_ops.OpenFlags;
pub const StatResult = stat.StatResult;

// File descriptor operations
pub const open = fd_ops.open;
pub const create = fd_ops.create;
pub const close = fd_ops.close;
pub const read = fd_ops.read;
pub const write = fd_ops.write;
pub const seek = fd_ops.seek;
pub const tell = fd_ops.tell;
pub const isatty = fd_ops.isatty;

// Path operations
pub const SEP = path_ops.SEP;
pub const ALTSEP = path_ops.ALTSEP;
pub const EXTSEP = path_ops.EXTSEP;
pub const PATHSEP = path_ops.PATHSEP;
pub const joinPath = path_ops.joinPath;
pub const dirname = path_ops.dirname;
pub const basename = path_ops.basename;
pub const extension = path_ops.extension;
pub const splitPath = path_ops.splitPath;
pub const splitExt = path_ops.splitExt;
pub const normpath = path_ops.normpath;
pub const isabs = path_ops.isabs;
pub const abspath = path_ops.abspath;
pub const exists = path_ops.exists;
pub const isfile = path_ops.isfile;
pub const isdir = path_ops.isdir;
pub const islink = path_ops.islink;

// Encoding detection
pub const deviceEncoding = encoding.deviceEncoding;
pub const filesystemEncoding = encoding.filesystemEncoding;
pub const localeEncoding = encoding.localeEncoding;

// File mode parsing
pub const parseMode = mode.parseMode;
pub const modeToString = mode.modeToString;

// File statistics
pub const statFile = stat.stat;
pub const getsize = stat.getsize;
pub const getmtime = stat.getmtime;

// Directory operations
pub const listdir = dir_ops.listdir;
pub const mkdir = dir_ops.mkdir;
pub const makedirs = dir_ops.makedirs;
pub const rmdir = dir_ops.rmdir;

// File operations
pub const unlink = file_ops.unlink;
pub const rename = file_ops.rename;
pub const copy = file_ops.copy;

// Current working directory
pub const getcwd = cwd.getcwd;
pub const chdir = cwd.chdir;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize file utilities
pub fn init() void {
    // No initialization needed for Zig stdlib
}
