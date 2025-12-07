//! Python 'sysconfig' module - Python configuration information
//!
//! Provides access to Python's configuration information like installation
//! paths, compiler flags, and platform identification.
//!
//! Mirrors: CPython Lib/sysconfig.py

const std = @import("std");
const builtin = @import("builtin");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Installation Scheme Names
// ============================================================================

/// Standard installation scheme
pub const SCHEME_NAMES = [_][]const u8{
    "posix_prefix",
    "posix_home",
    "posix_user",
    "posix_venv",
    "nt",
    "nt_user",
    "nt_venv",
    "venv",
};

// ============================================================================
// Path Names
// ============================================================================

/// Path name keys
pub const PATH_NAMES = [_][]const u8{
    "stdlib",
    "platstdlib",
    "purelib",
    "platlib",
    "include",
    "platinclude",
    "scripts",
    "data",
};

// ============================================================================
// Configuration Variables
// ============================================================================

/// Get a configuration variable
pub fn get_config_var(name: []const u8) ?[]const u8 {
    const vars = std.StaticStringMap([]const u8).initComptime(.{
        .{ "prefix", "/usr/local" },
        .{ "exec_prefix", "/usr/local" },
        .{ "base", "/usr/local" },
        .{ "platbase", "/usr/local" },
        .{ "VERSION", "3.12" },
        .{ "SOABI", getSoabi() },
        .{ "EXT_SUFFIX", getExtSuffix() },
        .{ "LIBDIR", "/usr/local/lib" },
        .{ "INCLUDEDIR", "/usr/local/include" },
        .{ "BINDIR", "/usr/local/bin" },
        .{ "CC", "cc" },
        .{ "CXX", "c++" },
        .{ "CFLAGS", "" },
        .{ "LDFLAGS", "" },
        .{ "SHLIB_SUFFIX", getSharedLibSuffix() },
        .{ "py_version", "3.12.0" },
        .{ "py_version_short", "3.12" },
        .{ "py_version_nodot", "312" },
        .{ "installed_base", "/usr/local" },
        .{ "installed_platbase", "/usr/local" },
    });
    return vars.get(name);
}

/// Get all configuration variables
pub fn get_config_vars(allocator: std.mem.Allocator) !hashmap_helper.StringHashMap([]const u8) {
    var vars = hashmap_helper.StringHashMap([]const u8).init(allocator);

    const keys = [_][]const u8{
        "prefix", "exec_prefix", "base", "platbase",
        "VERSION", "SOABI", "EXT_SUFFIX", "LIBDIR",
        "INCLUDEDIR", "BINDIR", "CC", "CXX", "CFLAGS",
        "LDFLAGS", "SHLIB_SUFFIX",
    };

    for (keys) |key| {
        if (get_config_var(key)) |value| {
            try vars.put(key, value);
        }
    }

    return vars;
}

// ============================================================================
// Platform Detection
// ============================================================================

/// Get the platform identifier
pub fn get_platform() []const u8 {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => "linux-x86_64",
            .aarch64 => "linux-aarch64",
            .arm => "linux-armv7l",
            else => "linux-unknown",
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "macosx-10.9-x86_64",
            .aarch64 => "macosx-11.0-arm64",
            else => "macosx-unknown",
        },
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "win-amd64",
            .x86 => "win32",
            .aarch64 => "win-arm64",
            else => "win-unknown",
        },
        .freebsd => "freebsd",
        .netbsd => "netbsd",
        .openbsd => "openbsd",
        else => "unknown",
    };
}

/// Get Python implementation (always "Metal0" for this runtime)
pub fn get_python_version() []const u8 {
    return "3.12.0";
}

// ============================================================================
// Path Functions
// ============================================================================

/// Get installation paths for a scheme
pub fn get_paths(allocator: std.mem.Allocator, scheme: ?[]const u8) !hashmap_helper.StringHashMap([]const u8) {
    _ = scheme;
    var paths = hashmap_helper.StringHashMap([]const u8).init(allocator);

    const prefix = "/usr/local";
    try paths.put("stdlib", prefix ++ "/lib/python3.12");
    try paths.put("platstdlib", prefix ++ "/lib/python3.12");
    try paths.put("purelib", prefix ++ "/lib/python3.12/site-packages");
    try paths.put("platlib", prefix ++ "/lib/python3.12/site-packages");
    try paths.put("include", prefix ++ "/include/python3.12");
    try paths.put("platinclude", prefix ++ "/include/python3.12");
    try paths.put("scripts", prefix ++ "/bin");
    try paths.put("data", prefix);

    return paths;
}

/// Get a single installation path
pub fn get_path(name: []const u8) ?[]const u8 {
    const paths = std.StaticStringMap([]const u8).initComptime(.{
        .{ "stdlib", "/usr/local/lib/python3.12" },
        .{ "platstdlib", "/usr/local/lib/python3.12" },
        .{ "purelib", "/usr/local/lib/python3.12/site-packages" },
        .{ "platlib", "/usr/local/lib/python3.12/site-packages" },
        .{ "include", "/usr/local/include/python3.12" },
        .{ "platinclude", "/usr/local/include/python3.12" },
        .{ "scripts", "/usr/local/bin" },
        .{ "data", "/usr/local" },
    });
    return paths.get(name);
}

/// Get default scheme name
pub fn get_default_scheme() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "nt",
        else => "posix_prefix",
    };
}

/// Get scheme for current installation
pub fn get_preferred_scheme(key: []const u8) []const u8 {
    if (std.mem.eql(u8, key, "prefix")) {
        return get_default_scheme();
    } else if (std.mem.eql(u8, key, "home")) {
        return switch (builtin.os.tag) {
            .windows => "nt",
            else => "posix_home",
        };
    } else if (std.mem.eql(u8, key, "user")) {
        return switch (builtin.os.tag) {
            .windows => "nt_user",
            else => "posix_user",
        };
    }
    return get_default_scheme();
}

// ============================================================================
// Helpers
// ============================================================================

fn getSoabi() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "cpython-312-x86_64-linux-gnu",
        .macos => "cpython-312-darwin",
        .windows => "cp312-win_amd64",
        else => "cpython-312",
    };
}

fn getExtSuffix() []const u8 {
    return switch (builtin.os.tag) {
        .linux => ".cpython-312-x86_64-linux-gnu.so",
        .macos => ".cpython-312-darwin.so",
        .windows => ".cp312-win_amd64.pyd",
        else => ".so",
    };
}

fn getSharedLibSuffix() []const u8 {
    return switch (builtin.os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the sysconfig module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "get_config_var" {
    try std.testing.expect(get_config_var("VERSION") != null);
    try std.testing.expectEqualStrings("3.12", get_config_var("VERSION").?);
    try std.testing.expect(get_config_var("nonexistent") == null);
}

test "get_platform" {
    const platform = get_platform();
    try std.testing.expect(platform.len > 0);
}

test "get_python_version" {
    try std.testing.expectEqualStrings("3.12.0", get_python_version());
}

test "get_path" {
    try std.testing.expect(get_path("stdlib") != null);
    try std.testing.expect(get_path("nonexistent") == null);
}

test "get_default_scheme" {
    const scheme = get_default_scheme();
    try std.testing.expect(scheme.len > 0);
}

test "get_preferred_scheme" {
    const prefix_scheme = get_preferred_scheme("prefix");
    try std.testing.expect(prefix_scheme.len > 0);

    const user_scheme = get_preferred_scheme("user");
    try std.testing.expect(user_scheme.len > 0);
}

test "SCHEME_NAMES" {
    try std.testing.expect(SCHEME_NAMES.len > 0);
    try std.testing.expectEqualStrings("posix_prefix", SCHEME_NAMES[0]);
}

test "PATH_NAMES" {
    try std.testing.expect(PATH_NAMES.len == 8);
    try std.testing.expectEqualStrings("stdlib", PATH_NAMES[0]);
}
