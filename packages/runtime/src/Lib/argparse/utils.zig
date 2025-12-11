//! Utility functions for argparse
//!
//! Provides getSystemArgs, type conversion functions, and FileType.

const std = @import("std");

/// Get system command-line arguments using std.process.argsAlloc
/// Returns an allocated slice of argument strings
/// Caller must free with allocator.free() when done
pub fn getSystemArgs(allocator: std.mem.Allocator) []const [:0]u8 {
    // Use std.process.argsAlloc to get command line arguments
    const args = std.process.argsAlloc(allocator) catch {
        // On failure, return empty slice
        return &[_][:0]u8{};
    };
    return args;
}

/// Free system arguments allocated by getSystemArgs
pub fn freeSystemArgs(allocator: std.mem.Allocator, args: []const [:0]u8) void {
    std.process.argsFree(allocator, args);
}

/// Convert string to integer
pub fn intType(s: []const u8) !i64 {
    return std.fmt.parseInt(i64, s, 10) catch error.InvalidValue;
}

/// Convert string to float
pub fn floatType(s: []const u8) !f64 {
    return std.fmt.parseFloat(f64, s) catch error.InvalidValue;
}

/// File type for argument parsing
pub const FileType = struct {
    mode: []const u8,

    pub fn init(mode: []const u8) FileType {
        return .{ .mode = mode };
    }

    pub fn open(self: FileType, path: []const u8) !std.fs.File {
        _ = self;
        return std.fs.cwd().openFile(path, .{});
    }
};

// ============================================================================
// Tests
// ============================================================================

test "intType" {
    try std.testing.expectEqual(@as(i64, 42), try intType("42"));
    try std.testing.expectEqual(@as(i64, -100), try intType("-100"));
    try std.testing.expectError(error.InvalidValue, intType("not_a_number"));
}

test "floatType" {
    const f = try floatType("3.14");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), f, 0.001);
    try std.testing.expectError(error.InvalidValue, floatType("not_a_float"));
}
