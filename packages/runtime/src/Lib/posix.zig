//! Python posix module - POSIX-specific system calls
//! Platform: Unix/Linux/macOS only (not Windows)
//!
//! This module provides low-level POSIX APIs. On Windows, use the nt module instead.
//! Most user code should use the higher-level os module which abstracts platform differences.

const std = @import("std");
const builtin = @import("builtin");

/// List of POSIX functions available on this platform
/// Used by tests to check feature availability
pub const _have_functions: []const []const u8 = &.{
    "HAVE_FACCESSAT",
    "HAVE_FCHDIR",
    "HAVE_FCHMOD",
    "HAVE_FCHMODAT",
    "HAVE_FCHOWN",
    "HAVE_FCHOWNAT",
    "HAVE_FEXECVE",
    "HAVE_FDOPENDIR",
    "HAVE_FPATHCONF",
    "HAVE_FSTATAT",
    "HAVE_FSTATVFS",
    "HAVE_FTRUNCATE",
    "HAVE_FUTIMENS",
    "HAVE_FUTIMES",
    "HAVE_FUTIMESAT",
    "HAVE_LINKAT",
    "HAVE_LUTIMES",
    "HAVE_LCHFLAGS",
    "HAVE_LCHMOD",
    "HAVE_LCHOWN",
    "HAVE_LSTAT",
    "HAVE_MKDIRAT",
    "HAVE_MKFIFOAT",
    "HAVE_MKNODAT",
    "HAVE_OPENAT",
    "HAVE_READLINKAT",
    "HAVE_RENAMEAT",
    "HAVE_SYMLINKAT",
    "HAVE_UNLINKAT",
    "HAVE_UTIMENSAT",
};

/// Stub posix module for tests
/// Most functions are handled by module dispatcher (src/codegen/native/posix_mod.zig)
/// This stub just provides module attributes needed by tests
pub fn __stub__() void {}
