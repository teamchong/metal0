//! ctypes.util - Utility functions for finding shared libraries
//! Reference: cpython/Lib/ctypes/util.py
//!
//! CPython exports: find_library, find_msvcrt (Windows only)
//!
//! Provides platform-specific functions for locating shared libraries.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection
// ============================================================================

const is_windows = builtin.os.tag == .windows;
const is_darwin = builtin.os.tag == .macos or builtin.os.tag == .ios or
    builtin.os.tag == .tvos or builtin.os.tag == .watchos;
const is_aix = false; // AIX not supported in Zig std
const is_freebsd = builtin.os.tag == .freebsd;
const is_openbsd = builtin.os.tag == .openbsd;
const is_linux = builtin.os.tag == .linux;
const is_android = builtin.abi == .android;

// ============================================================================
// Windows Support
// ============================================================================

/// CPython: def find_msvcrt()
/// Return the name of the VC runtime dll (Windows only)
pub fn find_msvcrt() ?[]const u8 {
    if (!is_windows) return null;

    // Modern Windows uses ucrtbase.dll (Universal CRT)
    // Legacy versions used msvcrt.dll, msvcr90.dll, etc.
    return "ucrtbase.dll";
}

// ============================================================================
// Library Search Paths
// ============================================================================

/// Default library search paths for Unix-like systems
const unix_lib_paths = [_][]const u8{
    "/usr/local/lib",
    "/usr/lib",
    "/lib",
};

/// Default library search paths for macOS
const darwin_lib_paths = [_][]const u8{
    "/usr/local/lib",
    "/usr/lib",
    "/opt/homebrew/lib",
};

/// Default framework search paths for macOS
const darwin_framework_paths = [_][]const u8{
    "/Library/Frameworks",
    "/System/Library/Frameworks",
};

// ============================================================================
// find_library Implementation
// ============================================================================

/// CPython: def find_library(name)
/// Find a library and return the pathname.
/// On most systems, name is the library name without any prefix like 'lib',
/// suffix like '.so', '.dylib' or version number.
/// Returns null if the library cannot be found.
pub fn find_library(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    if (is_windows) {
        return findLibraryWindows(allocator, name);
    } else if (is_darwin) {
        return findLibraryDarwin(allocator, name);
    } else if (is_android) {
        return findLibraryAndroid(allocator, name);
    } else {
        return findLibraryPosix(allocator, name);
    }
}

/// Windows library search
fn findLibraryWindows(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Special case for C library
    if (std.mem.eql(u8, name, "c") or std.mem.eql(u8, name, "m")) {
        return find_msvcrt();
    }

    // Search PATH environment variable
    const path_env = std.posix.getenv("PATH") orelse return null;
    var path_iter = std.mem.splitScalar(u8, path_env, ';');

    while (path_iter.next()) |dir| {
        // Try name as-is
        if (checkLibraryExists(allocator, dir, name, "")) |found| {
            return found;
        }
        // Try with .dll extension
        if (!std.mem.endsWith(u8, name, ".dll")) {
            if (checkLibraryExists(allocator, dir, name, ".dll")) |found| {
                return found;
            }
        }
    }

    return null;
}

/// macOS/iOS library search using dyld semantics
fn findLibraryDarwin(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Import macholib for dyld_find
    const macholib = @import("macholib.zig");

    // Try different naming conventions
    const suffixes = [_][]const u8{
        ".dylib",
        "",
    };

    const prefixes = [_][]const u8{
        "lib",
        "",
    };

    for (prefixes) |prefix| {
        for (suffixes) |suffix| {
            const lib_name = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, name, suffix }) catch continue;
            defer allocator.free(lib_name);

            if (macholib.dyld_find(allocator, lib_name, null)) |path| {
                return path;
            }
        }
    }

    // Try as framework
    const framework_name = std.fmt.allocPrint(allocator, "{s}.framework/{s}", .{ name, name }) catch return null;
    defer allocator.free(framework_name);

    if (macholib.dyld_find(allocator, framework_name, null)) |path| {
        return path;
    }

    return null;
}

/// Android library search
fn findLibraryAndroid(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Android libraries are in /system/lib or /system/lib64
    const uname = std.posix.uname();
    const is_64bit = std.mem.indexOf(u8, &uname.machine, "64") != null;

    const dir = if (is_64bit) "/system/lib64" else "/system/lib";

    const lib_name = std.fmt.allocPrint(allocator, "{s}/lib{s}.so", .{ dir, name }) catch return null;

    const file = std.fs.openFileAbsolute(lib_name, .{}) catch {
        allocator.free(lib_name);
        return null;
    };
    file.close();

    return lib_name;
}

/// Generic POSIX library search (Linux, FreeBSD, etc.)
fn findLibraryPosix(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Try ldconfig first on Linux
    if (is_linux) {
        if (findSonameLdconfig(allocator, name)) |path| {
            return path;
        }
    }

    // Search common library paths
    const search_paths = if (is_darwin) &darwin_lib_paths else &unix_lib_paths;

    // Also check LD_LIBRARY_PATH
    const ld_path = std.posix.getenv("LD_LIBRARY_PATH");

    // Try different naming conventions
    const suffixes = [_][]const u8{
        ".so",
        ".so.1",
        ".so.0",
    };

    // Search LD_LIBRARY_PATH first
    if (ld_path) |paths| {
        var path_iter = std.mem.splitScalar(u8, paths, ':');
        while (path_iter.next()) |dir| {
            for (suffixes) |suffix| {
                if (checkLibraryExists(allocator, dir, name, suffix)) |found| {
                    return found;
                }
            }
        }
    }

    // Search standard paths
    for (search_paths) |dir| {
        for (suffixes) |suffix| {
            if (checkLibraryExists(allocator, dir, name, suffix)) |found| {
                return found;
            }
        }
    }

    return null;
}

/// Check if a library exists at the given path
fn checkLibraryExists(allocator: std.mem.Allocator, dir: []const u8, name: []const u8, suffix: []const u8) ?[]const u8 {
    const has_lib_prefix = std.mem.startsWith(u8, name, "lib");
    const prefix = if (has_lib_prefix) "" else "lib";

    const full_path = std.fmt.allocPrint(allocator, "{s}/{s}{s}{s}", .{ dir, prefix, name, suffix }) catch return null;

    const file = std.fs.openFileAbsolute(full_path, .{}) catch {
        allocator.free(full_path);
        return null;
    };
    file.close();

    return full_path;
}

/// Try to find library using ldconfig (Linux)
fn findSonameLdconfig(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    _ = allocator;
    _ = name;

    // Would run /sbin/ldconfig -p and parse output
    // For AOT compilation, we skip subprocess execution
    return null;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if a file is an ELF binary
pub fn isElf(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();

    var header: [4]u8 = undefined;
    const bytes_read = file.read(&header) catch return false;
    if (bytes_read < 4) return false;

    // ELF magic: 0x7F 'E' 'L' 'F'
    return std.mem.eql(u8, &header, "\x7fELF");
}

/// Get SONAME from an ELF file (would use objdump in CPython)
pub fn getSoname(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    _ = allocator;
    _ = path;
    // Would parse ELF headers or use objdump
    // For AOT compilation, return null
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "find_library returns null for nonexistent" {
    const allocator = std.testing.allocator;
    const result = find_library(allocator, "nonexistent_library_12345");
    try std.testing.expect(result == null);
}

test "find_msvcrt" {
    if (is_windows) {
        const result = find_msvcrt();
        try std.testing.expect(result != null);
    }
}

test "isElf" {
    // Test with a non-ELF file (this test file itself)
    const result = isElf("/bin/sh");
    // /bin/sh should be ELF on Linux, Mach-O on macOS
    if (is_linux) {
        try std.testing.expect(result == true);
    }
}
