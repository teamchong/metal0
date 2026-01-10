//! test.test_ctypes.test_init - Tests for initialization
//! Reference: cpython/Lib/test/test_ctypes/test_init.py
//!
//! Tests for ctypes object initialization including constructors,
//! default values, and initialization from various sources.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Initialization Helpers
// ============================================================================

/// Initialize a value to zero
pub fn zeroInit(comptime T: type) T {
    return std.mem.zeroes(T);
}

/// Initialize from bytes
pub fn initFromBytes(comptime T: type, bytes: []const u8) !T {
    if (bytes.len < @sizeOf(T)) {
        return error.InsufficientBytes;
    }
    return std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
}

/// Initialize from a value of the same type
pub fn initFromValue(comptime T: type, value: T) T {
    return value;
}

// ============================================================================
// Simple Types with Init
// ============================================================================

pub const c_int = struct {
    const Self = @This();

    value: i32 = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn initValue(v: i32) Self {
        return .{ .value = v };
    }

    pub fn initFromInt(comptime T: type, v: T) Self {
        return .{ .value = @intCast(v) };
    }
};

pub const c_double = struct {
    const Self = @This();

    value: f64 = 0.0,

    pub fn init() Self {
        return .{};
    }

    pub fn initValue(v: f64) Self {
        return .{ .value = v };
    }

    pub fn initFromFloat(comptime T: type, v: T) Self {
        return .{ .value = @floatCast(v) };
    }
};

pub const c_char_p = struct {
    const Self = @This();

    ptr: ?[*:0]const u8 = null,

    pub fn init() Self {
        return .{};
    }

    pub fn initValue(s: [*:0]const u8) Self {
        return .{ .ptr = s };
    }

    pub fn initFromSlice(s: [:0]const u8) Self {
        return .{ .ptr = s.ptr };
    }

    pub fn value(self: Self) ?[]const u8 {
        if (self.ptr) |p| {
            var len: usize = 0;
            while (p[len] != 0) : (len += 1) {}
            return p[0..len];
        }
        return null;
    }
};

// ============================================================================
// Structure Initialization
// ============================================================================

pub fn StructInit(comptime fields: []const FieldInit) type {
    return struct {
        const Self = @This();
        pub const _fields_ = fields;

        values: [fields.len]i64 = initDefaults(),

        fn initDefaults() [fields.len]i64 {
            var result: [fields.len]i64 = undefined;
            inline for (fields, 0..) |field, i| {
                result[i] = field.default;
            }
            return result;
        }

        pub fn init() Self {
            return .{};
        }

        pub fn initWith(vals: anytype) Self {
            var self = Self.init();
            inline for (vals, 0..) |v, i| {
                if (i < fields.len) {
                    self.values[i] = v;
                }
            }
            return self;
        }

        pub fn get(self: *const Self, comptime name: []const u8) i64 {
            inline for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, name)) {
                    return self.values[i];
                }
            }
            @compileError("Unknown field: " ++ name);
        }

        pub fn set(self: *Self, comptime name: []const u8, value: i64) void {
            inline for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, name)) {
                    self.values[i] = value;
                    return;
                }
            }
            @compileError("Unknown field: " ++ name);
        }
    };
}

pub const FieldInit = struct {
    name: []const u8,
    default: i64 = 0,
};

// ============================================================================
// Array Initialization
// ============================================================================

pub fn ArrayInit(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        items: [N]T = [_]T{std.mem.zeroes(T)} ** N,

        pub fn init() Self {
            return .{};
        }

        pub fn initWith(values: [N]T) Self {
            return .{ .items = values };
        }

        pub fn initFill(value: T) Self {
            return .{ .items = [_]T{value} ** N };
        }

        pub fn initFromSlice(slice: []const T) Self {
            var self = Self.init();
            const len = @min(slice.len, N);
            @memcpy(self.items[0..len], slice[0..len]);
            return self;
        }
    };
}

// ============================================================================
// Example Types
// ============================================================================

pub const Point = StructInit(&.{
    .{ .name = "x", .default = 0 },
    .{ .name = "y", .default = 0 },
});

pub const Rect = StructInit(&.{
    .{ .name = "left", .default = 0 },
    .{ .name = "top", .default = 0 },
    .{ .name = "right", .default = 100 },
    .{ .name = "bottom", .default = 100 },
});

pub const IntArray5 = ArrayInit(i32, 5);

// ============================================================================
// Test Cases
// ============================================================================

fn testZeroInit() !void {
    const i = zeroInit(i32);
    try std.testing.expectEqual(@as(i32, 0), i);

    const f = zeroInit(f64);
    try std.testing.expectEqual(@as(f64, 0.0), f);
}

fn testInitFromBytes() !void {
    const bytes = [_]u8{ 0x2A, 0x00, 0x00, 0x00 }; // 42 in little-endian
    const value = try initFromBytes(i32, &bytes);
    try std.testing.expectEqual(@as(i32, 42), value);
}

fn testInitFromBytesTooShort() !void {
    const bytes = [_]u8{ 0x01, 0x02 };
    try std.testing.expectError(error.InsufficientBytes, initFromBytes(i32, &bytes));
}

fn testCIntInit() !void {
    const ci = c_int.init();
    try std.testing.expectEqual(@as(i32, 0), ci.value);

    const ci2 = c_int.initValue(42);
    try std.testing.expectEqual(@as(i32, 42), ci2.value);

    const ci3 = c_int.initFromInt(u8, 255);
    try std.testing.expectEqual(@as(i32, 255), ci3.value);
}

fn testCDoubleInit() !void {
    const cd = c_double.init();
    try std.testing.expectEqual(@as(f64, 0.0), cd.value);

    const cd2 = c_double.initValue(3.14);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), cd2.value, 0.001);
}

fn testCCharPInit() !void {
    const cp = c_char_p.init();
    try std.testing.expect(cp.value() == null);

    const cp2 = c_char_p.initValue("Hello");
    try std.testing.expectEqualStrings("Hello", cp2.value().?);
}

fn testPointInit() !void {
    const pt = Point.init();
    try std.testing.expectEqual(@as(i64, 0), pt.get("x"));
    try std.testing.expectEqual(@as(i64, 0), pt.get("y"));

    const pt2 = Point.initWith(.{ 10, 20 });
    try std.testing.expectEqual(@as(i64, 10), pt2.get("x"));
    try std.testing.expectEqual(@as(i64, 20), pt2.get("y"));
}

fn testRectDefaults() !void {
    const rect = Rect.init();
    try std.testing.expectEqual(@as(i64, 0), rect.get("left"));
    try std.testing.expectEqual(@as(i64, 0), rect.get("top"));
    try std.testing.expectEqual(@as(i64, 100), rect.get("right"));
    try std.testing.expectEqual(@as(i64, 100), rect.get("bottom"));
}

fn testArrayInit() !void {
    const arr = IntArray5.init();
    for (arr.items) |item| {
        try std.testing.expectEqual(@as(i32, 0), item);
    }
}

fn testArrayInitWith() !void {
    const arr = IntArray5.initWith(.{ 1, 2, 3, 4, 5 });
    try std.testing.expectEqual(@as(i32, 1), arr.items[0]);
    try std.testing.expectEqual(@as(i32, 5), arr.items[4]);
}

fn testArrayInitFill() !void {
    const arr = IntArray5.initFill(42);
    for (arr.items) |item| {
        try std.testing.expectEqual(@as(i32, 42), item);
    }
}

fn testArrayInitFromSlice() !void {
    const values = [_]i32{ 10, 20, 30 };
    const arr = IntArray5.initFromSlice(&values);
    try std.testing.expectEqual(@as(i32, 10), arr.items[0]);
    try std.testing.expectEqual(@as(i32, 30), arr.items[2]);
    try std.testing.expectEqual(@as(i32, 0), arr.items[3]); // Not copied
}

fn testStructSet() !void {
    var pt = Point.init();
    pt.set("x", 100);
    pt.set("y", 200);

    try std.testing.expectEqual(@as(i64, 100), pt.get("x"));
    try std.testing.expectEqual(@as(i64, 200), pt.get("y"));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "zero_init" {
    try testZeroInit();
}

test "init_from_bytes" {
    try testInitFromBytes();
}

test "init_from_bytes_too_short" {
    try testInitFromBytesTooShort();
}

test "c_int_init" {
    try testCIntInit();
}

test "c_double_init" {
    try testCDoubleInit();
}

test "c_char_p_init" {
    try testCCharPInit();
}

test "point_init" {
    try testPointInit();
}

test "rect_defaults" {
    try testRectDefaults();
}

test "array_init" {
    try testArrayInit();
}

test "array_init_with" {
    try testArrayInitWith();
}

test "array_init_fill" {
    try testArrayInitFill();
}

test "array_init_from_slice" {
    try testArrayInitFromSlice();
}

test "struct_set" {
    try testStructSet();
}
