//! sysconfig.__main__ - CLI for sysconfig module
//! Reference: cpython/Lib/sysconfig/__main__.py
//!
//! Command-line interface for querying Python configuration.
//! Usage: python -m sysconfig [options]

const std = @import("std");
const builtin = @import("builtin");

/// Configuration variables (subset of common ones)
pub const config_vars = std.StaticStringMap([]const u8).initComptime(.{
    .{ "prefix", "/usr/local" },
    .{ "exec_prefix", "/usr/local" },
    .{ "BINDIR", "/usr/local/bin" },
    .{ "LIBDIR", "/usr/local/lib" },
    .{ "INCLUDEDIR", "/usr/local/include" },
    .{ "py_version", "3.12" },
    .{ "py_version_short", "3.12" },
    .{ "py_version_nodot", "312" },
    .{ "SOABI", "cpython-312" },
    .{ "EXT_SUFFIX", ".cpython-312.so" },
    .{ "CC", "cc" },
    .{ "CXX", "c++" },
    .{ "CFLAGS", "-O2" },
    .{ "LDFLAGS", "" },
});

/// Installation scheme paths
pub const Scheme = struct {
    stdlib: []const u8,
    platstdlib: []const u8,
    purelib: []const u8,
    platlib: []const u8,
    include: []const u8,
    platinclude: []const u8,
    scripts: []const u8,
    data: []const u8,
};

/// Get installation scheme for current platform
pub fn getScheme(name: []const u8) Scheme {
    if (std.mem.eql(u8, name, "posix_prefix")) {
        return .{
            .stdlib = "/usr/local/lib/python3.12",
            .platstdlib = "/usr/local/lib/python3.12",
            .purelib = "/usr/local/lib/python3.12/site-packages",
            .platlib = "/usr/local/lib/python3.12/site-packages",
            .include = "/usr/local/include/python3.12",
            .platinclude = "/usr/local/include/python3.12",
            .scripts = "/usr/local/bin",
            .data = "/usr/local",
        };
    } else if (std.mem.eql(u8, name, "posix_user")) {
        return .{
            .stdlib = "~/.local/lib/python3.12",
            .platstdlib = "~/.local/lib/python3.12",
            .purelib = "~/.local/lib/python3.12/site-packages",
            .platlib = "~/.local/lib/python3.12/site-packages",
            .include = "~/.local/include/python3.12",
            .platinclude = "~/.local/include/python3.12",
            .scripts = "~/.local/bin",
            .data = "~/.local",
        };
    } else {
        // Default scheme
        return .{
            .stdlib = "/usr/lib/python3.12",
            .platstdlib = "/usr/lib/python3.12",
            .purelib = "/usr/lib/python3.12/site-packages",
            .platlib = "/usr/lib/python3.12/site-packages",
            .include = "/usr/include/python3.12",
            .platinclude = "/usr/include/python3.12",
            .scripts = "/usr/bin",
            .data = "/usr",
        };
    }
}

/// Get a configuration variable
pub fn getConfigVar(name: []const u8) ?[]const u8 {
    return config_vars.get(name);
}

/// Get Python version info
pub fn getPythonVersion() []const u8 {
    return "3.12.0";
}

/// Get platform string
pub fn getPlatform() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "darwin",
        .linux => "linux",
        .windows => "win32",
        .freebsd => "freebsd",
        else => "unknown",
    };
}

/// Main entry point - print sysconfig information
pub fn main(writer: anytype) !void {
    try writer.writeAll("Platform: ");
    try writer.writeAll(getPlatform());
    try writer.writeAll("\n\n");

    try writer.writeAll("Python version: ");
    try writer.writeAll(getPythonVersion());
    try writer.writeAll("\n\n");

    try writer.writeAll("Paths:\n");
    const scheme = getScheme("posix_prefix");
    try writer.print("  stdlib: {s}\n", .{scheme.stdlib});
    try writer.print("  purelib: {s}\n", .{scheme.purelib});
    try writer.print("  platlib: {s}\n", .{scheme.platlib});
    try writer.print("  scripts: {s}\n", .{scheme.scripts});
    try writer.writeAll("\n");

    try writer.writeAll("Variables:\n");
    inline for (config_vars.keys()) |key| {
        if (config_vars.get(key)) |value| {
            try writer.print("  {s} = {s}\n", .{ key, value });
        }
    }
}

/// Print help message
pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\usage: python -m sysconfig [--help] [--generate-config-args]
        \\
        \\Display Python configuration information.
        \\
        \\Options:
        \\  --help                 show this help message
        \\  --generate-config-args generate config.args file
        \\
    );
}

// ============================================================================
// Tests
// ============================================================================

test "getConfigVar" {
    const prefix = getConfigVar("prefix");
    try std.testing.expect(prefix != null);
    try std.testing.expectEqualStrings("/usr/local", prefix.?);
}

test "getScheme" {
    const scheme = getScheme("posix_prefix");
    try std.testing.expect(std.mem.indexOf(u8, scheme.stdlib, "python") != null);
}

test "getPlatform" {
    const platform = getPlatform();
    try std.testing.expect(platform.len > 0);
}
