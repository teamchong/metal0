//! Full Pickle module implementation for Python compatibility
//! Supports protocols 0-5 with proper serialization/deserialization
//!
//! Module structure:
//! - opcodes.zig: Protocol constants and opcodes
//! - types.zig: PickleValue union and error types
//! - pickler.zig: Serialization (Pickler class)
//! - unpickler.zig: Deserialization (Unpickler class)
//!
//! API: loads() returns *PyObject (like json.loads), matching Python semantics.
//! Internal: loadsInternal() returns PickleValue for low-level access.

const std = @import("std");
const runtime = @import("../../runtime.zig");

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
pub const pickleValueToPyObject = types.pickleValueToPyObject;

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

/// Deserialize pickle bytes to PyObject (Python-compatible API)
/// Returns *PyObject like json.loads() - enables assertIs(pickle.loads(...), True)
pub fn loads(data: []const u8, allocator: std.mem.Allocator) !*runtime.PyObject {
    const pickle_value = try loadsInternal(data, allocator);
    return try pickleValueToPyObject(pickle_value, allocator);
}

/// Internal: Deserialize pickle bytes to PickleValue (for low-level access)
pub fn loadsInternal(data: []const u8, allocator: std.mem.Allocator) !PickleValue {
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

/// Unpickle from a file - returns PyObject (Python-compatible API)
pub fn load(file: anytype, allocator: std.mem.Allocator) !*runtime.PyObject {
    const data = try file.readToEndAlloc(allocator, 1024 * 1024 * 100); // 100MB max
    defer allocator.free(data);
    return try loads(data, allocator);
}

/// Generic loads that handles both PyBytes and raw byte slices
/// Returns *PyObject for Python compatibility
/// This is a compile-once helper to avoid repeated @TypeOf introspection in generated code
pub fn loadsAny(data: anytype, allocator: std.mem.Allocator) *runtime.PyObject {
    const T = @TypeOf(data);
    // Import builtins at comptime to check for PyBytes type
    const builtins = @import("../../runtime/builtins.zig");
    const bytes: []const u8 = if (T == builtins.PyBytes)
        data.data
    else if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.child == u8)
        data
    else if (@typeInfo(T) == .@"struct" and @hasField(T, "data"))
        data.data
    else
        data;
    return loads(bytes, allocator) catch runtime.Py_None;
}

// ============================================================================
// Tests
// ============================================================================

test "pickle basic types (internal)" {
    const allocator = std.testing.allocator;

    // Test None
    {
        const data = try dumps(@as(?i64, null), allocator);
        defer allocator.free(data);
        const result = try loadsInternal(data, allocator);
        try std.testing.expect(result == .none);
    }

    // Test bool
    {
        const data = try dumps(true, allocator);
        defer allocator.free(data);
        const result = try loadsInternal(data, allocator);
        try std.testing.expect(result == .bool and result.bool == true);
    }

    // Test int
    {
        const data = try dumps(@as(i64, 42), allocator);
        defer allocator.free(data);
        const result = try loadsInternal(data, allocator);
        try std.testing.expect(result == .int and result.int == 42);
    }

    // Test float
    {
        const data = try dumps(@as(f64, 3.14), allocator);
        defer allocator.free(data);
        const result = try loadsInternal(data, allocator);
        try std.testing.expect(result == .float and @abs(result.float - 3.14) < 0.001);
    }

    // Test string
    {
        const data = try dumps("hello", allocator);
        defer allocator.free(data);
        const result = try loadsInternal(data, allocator);
        defer allocator.free(result.string);
        try std.testing.expect(result == .string and std.mem.eql(u8, result.string, "hello"));
    }
}

test "pickle tuple (internal)" {
    const allocator = std.testing.allocator;

    const data = try dumps(.{ @as(i64, 1), @as(i64, 2), @as(i64, 3) }, allocator);
    defer allocator.free(data);

    const result = try loadsInternal(data, allocator);
    defer allocator.free(result.tuple);

    try std.testing.expect(result == .tuple);
    try std.testing.expectEqual(@as(usize, 3), result.tuple.len);
    try std.testing.expectEqual(@as(i64, 1), result.tuple[0].int);
    try std.testing.expectEqual(@as(i64, 2), result.tuple[1].int);
    try std.testing.expectEqual(@as(i64, 3), result.tuple[2].int);
}

test "pickle loads returns PyObject" {
    const allocator = std.testing.allocator;

    // Test True returns Py_True
    {
        const data = try dumps(true, allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expectEqual(runtime.Py_True, result);
    }

    // Test False returns Py_False
    {
        const data = try dumps(false, allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expectEqual(runtime.Py_False, result);
    }

    // Test None returns Py_None
    {
        const data = try dumps(@as(?i64, null), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expectEqual(runtime.Py_None, result);
    }
}
