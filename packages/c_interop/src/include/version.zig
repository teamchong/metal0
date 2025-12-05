/// Python Version Configuration
///
/// Supports Python 3.10, 3.11, 3.12+ with version-specific struct layouts.
/// Set PYTHON_VERSION at compile time or detect at runtime.

const std = @import("std");
const builtin = @import("builtin");

/// Python version enum
pub const PythonVersion = enum(u8) {
    py310 = 10,
    py311 = 11,
    py312 = 12,
    py313 = 13,

    pub fn major(_: PythonVersion) u8 {
        return 3;
    }

    pub fn minor(self: PythonVersion) u8 {
        return @intFromEnum(self);
    }
};

/// Compile-time Python version selection
/// Override with: -DPYTHON_VERSION=311
pub const PYTHON_VERSION: PythonVersion = blk: {
    // Default to 3.12 (latest stable)
    break :blk .py312;
};

/// Check if version has lv_tag encoding for PyLongObject (3.12+)
pub fn hasLvTag(version: PythonVersion) bool {
    return @intFromEnum(version) >= 12;
}

/// Check if version has tp_watched/tp_versions_used in PyTypeObject (3.12+)
pub fn hasTypeWatching(version: PythonVersion) bool {
    return @intFromEnum(version) >= 12;
}

/// Check if version has _ma_watcher_tag in PyDictObject (3.12+)
pub fn hasDictWatcher(version: PythonVersion) bool {
    return @intFromEnum(version) >= 12;
}

/// Check if version has new frame object layout (3.11+)
pub fn hasNewFrameLayout(version: PythonVersion) bool {
    return @intFromEnum(version) >= 11;
}

/// Get Python version string
pub fn versionString(version: PythonVersion) []const u8 {
    return switch (version) {
        .py310 => "3.10",
        .py311 => "3.11",
        .py312 => "3.12",
        .py313 => "3.13",
    };
}

/// Get magic number for .pyc files
pub fn magicNumber(version: PythonVersion) u32 {
    return switch (version) {
        .py310 => 3439,
        .py311 => 3495,
        .py312 => 3531,
        .py313 => 3550,
    };
}
