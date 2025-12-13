//! Python stdlib module stub
//! Mirrors test.support.os_helper from CPython
const std = @import("std");

/// Default test filename for temp files
pub const TESTFN = "/tmp/metal0_test";

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

pub fn __stub__() void {
    // Stub - see module header for why this isn't needed
}
