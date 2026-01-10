//! ctypes.macholib - macOS Mach-O library utilities
//! Reference: cpython/Lib/ctypes/macholib/__init__.py
//!
//! CPython exports: dyld_find, framework_find, dylib_info, framework_info
//!
//! Provides utilities for finding macOS dynamic libraries and frameworks
//! using dyld semantics.

const std = @import("std");
const builtin = @import("builtin");

// Re-export submodules
pub const dyld = @import("macholib/dyld.zig");
pub const dylib = @import("macholib/dylib.zig");
pub const framework = @import("macholib/framework.zig");

// ============================================================================
// Main Exports (re-exported from submodules)
// ============================================================================

/// Find a library using dyld semantics
pub const dyld_find = dyld.dyld_find;

/// Find a framework using dyld semantics
pub const framework_find = dyld.framework_find;

/// Parse dylib path information
pub const dylib_info = dylib.dylib_info;

/// Parse framework path information
pub const framework_info = framework.framework_info;

// ============================================================================
// Constants
// ============================================================================

/// Default framework fallback paths
pub const DEFAULT_FRAMEWORK_FALLBACK = dyld.DEFAULT_FRAMEWORK_FALLBACK;

/// Default library fallback paths
pub const DEFAULT_LIBRARY_FALLBACK = dyld.DEFAULT_LIBRARY_FALLBACK;

// ============================================================================
// Tests
// ============================================================================

test "imports" {
    _ = dyld;
    _ = dylib;
    _ = framework;
}
