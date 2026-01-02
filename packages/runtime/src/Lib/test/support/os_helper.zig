//! Python stdlib module stub
//! Mirrors test.support.os_helper from CPython
const std = @import("std");

/// Default test filename for temp files
pub const TESTFN = "/tmp/metal0_test";

/// Undecodable test filename (contains invalid UTF-8 bytes)
pub const TESTFN_UNDECODABLE: ?[]const u8 = null; // Not supported in AOT

/// Get a temporary directory path
pub fn temp_dir() []const u8 {
    return "/tmp";
}

/// Remove a file (like os.unlink/os.remove)
pub fn unlink(path: []const u8) !void {
    const cwd = std.fs.cwd();
    cwd.deleteFile(path) catch |err| switch (err) {
        error.FileNotFound => {}, // Ignore if file doesn't exist
        else => return err,
    };
}

/// Environment variable context manager
/// Used to temporarily set/unset environment variables in tests
pub const EnvironmentVarGuard = struct {
    pub fn init(_: std.mem.Allocator) EnvironmentVarGuard {
        return .{};
    }
    pub fn deinit(_: *EnvironmentVarGuard) void {}
    pub fn set(_: *EnvironmentVarGuard, _: []const u8, _: []const u8) void {}
    pub fn unset(_: *EnvironmentVarGuard, _: []const u8) void {}
    pub fn close(_: EnvironmentVarGuard) void {}

    /// Python context manager __enter__
    pub fn __enter__(self: *EnvironmentVarGuard, _: std.mem.Allocator) !EnvironmentVarGuard {
        return self.*;
    }

    /// Python context manager __exit__
    pub fn __exit__(_: *EnvironmentVarGuard, _: std.mem.Allocator) !void {}
};

/// Context manager for changing to a temp directory
/// Used for tests that need to work in an isolated directory
pub const temp_cwd = struct {
    original_cwd: ?[]const u8 = null,

    pub fn init(_: std.mem.Allocator) temp_cwd {
        return .{};
    }

    pub fn deinit(_: *temp_cwd) void {}

    /// Python context manager __enter__
    pub fn __enter__(self: *temp_cwd, _: std.mem.Allocator) !*temp_cwd {
        return self;
    }

    /// Python context manager __exit__
    pub fn __exit__(_: *temp_cwd, _: std.mem.Allocator) !void {}
};

/// FakePath - Simple implementation of the path protocol
/// Used for testing path-like objects
pub const FakePath = struct {
    path: []const u8,

    pub fn init(_: std.mem.Allocator, path: []const u8) FakePath {
        return .{ .path = path };
    }

    /// Returns the file system path representation (__fspath__ protocol)
    pub fn __fspath__(self: *const FakePath) []const u8 {
        return self.path;
    }
};

pub fn __stub__() void {
    // Stub - see module header for why this isn't needed
}
