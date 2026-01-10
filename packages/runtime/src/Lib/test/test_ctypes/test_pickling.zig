//! test.test_ctypes.test_pickling - Tests for pickle support
//! Reference: cpython/Lib/test/test_ctypes/test_pickling.py
//!
//! Tests for serialization/deserialization of ctypes objects.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Pickle Protocol
// ============================================================================

pub const PickleProtocol = enum(u8) {
    protocol_0 = 0, // ASCII
    protocol_1 = 1, // Binary
    protocol_2 = 2, // New-style classes
    protocol_3 = 3, // Explicit support for bytes
    protocol_4 = 4, // Framing
    protocol_5 = 5, // Out-of-band data
};

// ============================================================================
// Serializable Interface
// ============================================================================

pub fn Serializable(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        /// Serialize to bytes
        pub fn toBytes(self: *const Self, buf: []u8) !usize {
            const bytes = std.mem.asBytes(&self.value);
            if (buf.len < bytes.len) return error.BufferTooSmall;
            @memcpy(buf[0..bytes.len], bytes);
            return bytes.len;
        }

        /// Deserialize from bytes
        pub fn fromBytes(bytes: []const u8) !Self {
            if (bytes.len < @sizeOf(T)) return error.InsufficientData;
            const value = std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
            return .{ .value = value };
        }

        /// Get reduce tuple for pickling
        pub fn reduce(self: *const Self) ReduceTuple {
            return .{
                .type_name = @typeName(T),
                .args = &[_]i64{@as(i64, @bitCast(self.value))},
            };
        }
    };
}

pub const ReduceTuple = struct {
    type_name: []const u8,
    args: []const i64,
};

// ============================================================================
// Structure Serialization
// ============================================================================

pub fn StructSerializer(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn serialize(value: *const T, allocator: std.mem.Allocator) ![]u8 {
            const bytes = std.mem.asBytes(value);
            const result = try allocator.alloc(u8, bytes.len);
            @memcpy(result, bytes);
            return result;
        }

        pub fn deserialize(bytes: []const u8, out: *T) !void {
            if (bytes.len < @sizeOf(T)) return error.InsufficientData;
            const ptr: *const T = @ptrCast(@alignCast(bytes.ptr));
            out.* = ptr.*;
        }

        pub fn getState(value: *const T) []const u8 {
            return std.mem.asBytes(value);
        }

        pub fn setState(value: *T, state: []const u8) !void {
            try deserialize(state, value);
        }
    };
}

// ============================================================================
// Pickle-like Operations
// ============================================================================

/// Dump object to bytes (simplified pickle)
pub fn dumps(comptime T: type, value: T, allocator: std.mem.Allocator) ![]u8 {
    const bytes = std.mem.asBytes(&value);
    const result = try allocator.alloc(u8, bytes.len + 1);
    result[0] = @intCast(@sizeOf(T)); // Simple header with size
    @memcpy(result[1..], bytes);
    return result;
}

/// Load object from bytes
pub fn loads(comptime T: type, data: []const u8) !T {
    if (data.len < 1) return error.InvalidPickle;
    const expected_size = data[0];
    if (data.len < 1 + expected_size) return error.InvalidPickle;
    if (expected_size != @sizeOf(T)) return error.TypeMismatch;
    return std.mem.bytesToValue(T, data[1..][0..@sizeOf(T)]);
}

// ============================================================================
// Test Types
// ============================================================================

const TestStruct = extern struct {
    x: i32,
    y: i32,
};

// ============================================================================
// Test Cases
// ============================================================================

fn testSerializableInt() !void {
    const s = Serializable(i32).init(42);
    var buf: [16]u8 = undefined;

    const len = try s.toBytes(&buf);
    try std.testing.expectEqual(@as(usize, 4), len);

    const restored = try Serializable(i32).fromBytes(&buf);
    try std.testing.expectEqual(@as(i32, 42), restored.value);
}

fn testSerializableDouble() !void {
    const s = Serializable(f64).init(3.14159);
    var buf: [16]u8 = undefined;

    const len = try s.toBytes(&buf);
    try std.testing.expectEqual(@as(usize, 8), len);

    const restored = try Serializable(f64).fromBytes(&buf);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), restored.value, 0.00001);
}

fn testStructSerializer() !void {
    const allocator = std.testing.allocator;
    var original = TestStruct{ .x = 10, .y = 20 };

    const bytes = try StructSerializer(TestStruct).serialize(&original, allocator);
    defer allocator.free(bytes);

    var restored: TestStruct = undefined;
    try StructSerializer(TestStruct).deserialize(bytes, &restored);

    try std.testing.expectEqual(@as(i32, 10), restored.x);
    try std.testing.expectEqual(@as(i32, 20), restored.y);
}

fn testDumpsLoads() !void {
    const allocator = std.testing.allocator;

    const original: i32 = 12345;
    const data = try dumps(i32, original, allocator);
    defer allocator.free(data);

    const restored = try loads(i32, data);
    try std.testing.expectEqual(@as(i32, 12345), restored);
}

fn testDumpsLoadsStruct() !void {
    const allocator = std.testing.allocator;

    const original = TestStruct{ .x = -5, .y = 100 };
    const data = try dumps(TestStruct, original, allocator);
    defer allocator.free(data);

    const restored = try loads(TestStruct, data);
    try std.testing.expectEqual(@as(i32, -5), restored.x);
    try std.testing.expectEqual(@as(i32, 100), restored.y);
}

fn testReduceTuple() !void {
    const s = Serializable(i32).init(42);
    const reduce = s.reduce();

    try std.testing.expectEqualStrings("i32", reduce.type_name);
    try std.testing.expect(reduce.args.len > 0);
}

fn testPickleProtocol() !void {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PickleProtocol.protocol_0));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(PickleProtocol.protocol_5));
}

fn testLoadsInvalidData() !void {
    const empty: []const u8 = &.{};
    try std.testing.expectError(error.InvalidPickle, loads(i32, empty));

    const too_small: []const u8 = &.{4};
    try std.testing.expectError(error.InvalidPickle, loads(i32, too_small));
}

fn testGetSetState() !void {
    var original = TestStruct{ .x = 42, .y = 84 };
    const state = StructSerializer(TestStruct).getState(&original);

    var restored: TestStruct = undefined;
    try StructSerializer(TestStruct).setState(&restored, state);

    try std.testing.expectEqual(@as(i32, 42), restored.x);
    try std.testing.expectEqual(@as(i32, 84), restored.y);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "serializable_int" {
    try testSerializableInt();
}

test "serializable_double" {
    try testSerializableDouble();
}

test "struct_serializer" {
    try testStructSerializer();
}

test "dumps_loads" {
    try testDumpsLoads();
}

test "dumps_loads_struct" {
    try testDumpsLoadsStruct();
}

test "reduce_tuple" {
    try testReduceTuple();
}

test "pickle_protocol" {
    try testPickleProtocol();
}

test "loads_invalid_data" {
    try testLoadsInvalidData();
}

test "get_set_state" {
    try testGetSetState();
}
