//! Full Pickle module implementation for Python compatibility
//! Supports protocols 0-5 with proper serialization/deserialization
//!
//! Module structure:
//! - opcodes.zig: Protocol constants and opcodes
//! - types.zig: PickleValue union and error types
//! - pickler.zig: Serialization (Pickler class)
//! - unpickler.zig: Deserialization (Unpickler class)

const std = @import("std");

// Re-export submodules
pub const opcodes = @import("opcodes.zig");
pub const types = @import("types.zig");
pub const pickler = @import("pickler.zig");
pub const unpickler = @import("unpickler.zig");

// Re-export key types and constants for convenience
pub const Opcode = opcodes.Opcode;
pub const HIGHEST_PROTOCOL = opcodes.HIGHEST_PROTOCOL;
pub const DEFAULT_PROTOCOL = opcodes.DEFAULT_PROTOCOL;

pub const PickleValue = types.PickleValue;
pub const PicklingError = types.PicklingError;
pub const UnpicklingError = types.UnpicklingError;

pub const Pickler = pickler.Pickler;
pub const Unpickler = unpickler.Unpickler;

// ============================================================================
// Public API matching Python's pickle module
// ============================================================================

/// Serialize an object to pickle bytes
pub fn dumps(obj: anytype, allocator: std.mem.Allocator) ![]const u8 {
    return dumpsWithProtocol(obj, allocator, @intCast(DEFAULT_PROTOCOL));
}

/// Serialize with specific protocol version
pub fn dumpsWithProtocol(obj: anytype, allocator: std.mem.Allocator, protocol: u8) ![]const u8 {
    var p = Pickler.init(allocator, protocol);
    defer p.deinit();
    return try p.dump(obj);
}

/// Deserialize pickle bytes to a PickleValue
pub fn loads(data: []const u8, allocator: std.mem.Allocator) !PickleValue {
    var u = Unpickler.init(allocator, data);
    defer u.deinit();
    return try u.load();
}

/// Pickle to a file
pub fn dump(obj: anytype, file: anytype, allocator: std.mem.Allocator) !void {
    const data = try dumps(obj, allocator);
    defer allocator.free(data);
    try file.writeAll(data);
}

/// Unpickle from a file
pub fn load(file: anytype, allocator: std.mem.Allocator) !PickleValue {
    const data = try file.readToEndAlloc(allocator, 1024 * 1024 * 100); // 100MB max
    defer allocator.free(data);
    return try loads(data, allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "pickle basic types" {
    const allocator = std.testing.allocator;

    // Test None
    {
        const data = try dumps(@as(?i64, null), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .none);
    }

    // Test bool
    {
        const data = try dumps(true, allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .bool and result.bool == true);
    }

    // Test int
    {
        const data = try dumps(@as(i64, 42), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .int and result.int == 42);
    }

    // Test float
    {
        const data = try dumps(@as(f64, 3.14), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .float and @abs(result.float - 3.14) < 0.001);
    }

    // Test string
    {
        const data = try dumps("hello", allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        defer allocator.free(result.string);
        try std.testing.expect(result == .string and std.mem.eql(u8, result.string, "hello"));
    }
}

test "pickle tuple" {
    const allocator = std.testing.allocator;

    const data = try dumps(.{ @as(i64, 1), @as(i64, 2), @as(i64, 3) }, allocator);
    defer allocator.free(data);

    const result = try loads(data, allocator);
    defer allocator.free(result.tuple);

    try std.testing.expect(result == .tuple);
    try std.testing.expectEqual(@as(usize, 3), result.tuple.len);
    try std.testing.expectEqual(@as(i64, 1), result.tuple[0].int);
    try std.testing.expectEqual(@as(i64, 2), result.tuple[1].int);
    try std.testing.expectEqual(@as(i64, 3), result.tuple[2].int);
}
