//! test.test_ctypes.test_structures - Tests for ctypes structures
//! Reference: cpython/Lib/test/test_ctypes/test_structures.py

const std = @import("std");
const _support = @import("_support.zig");

pub fn Structure(comptime fields: []const FieldDef) type {
    return struct {
        const Self = @This();
        pub const _fields_ = fields;

        data: [@sizeOf(StructData(fields))]u8 align(@alignOf(StructData(fields))) = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn asPtr(self: *Self) *StructData(fields) {
            return @ptrCast(&self.data);
        }
    };
}

pub const FieldDef = struct {
    name: []const u8,
    type_name: []const u8,
    size: usize,
    offset: usize,
};

fn StructData(comptime fields: []const FieldDef) type {
    _ = fields;
    return struct { x: i32 = 0, y: i32 = 0 }; // Placeholder
}

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
    
    pub fn init(x: i32, y: i32) @This() { return .{ .x = x, .y = y }; }
};

pub const Rect = struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,

    pub fn width(self: @This()) i32 { return self.right - self.left; }
    pub fn height(self: @This()) i32 { return self.bottom - self.top; }
};

test "point_init" {
    const p = Point.init(10, 20);
    try std.testing.expectEqual(@as(i32, 10), p.x);
    try std.testing.expectEqual(@as(i32, 20), p.y);
}

test "rect_dimensions" {
    const r = Rect{ .left = 0, .top = 0, .right = 100, .bottom = 50 };
    try std.testing.expectEqual(@as(i32, 100), r.width());
    try std.testing.expectEqual(@as(i32, 50), r.height());
}
