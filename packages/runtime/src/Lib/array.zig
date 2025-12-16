//! Python `array` module - Efficient arrays of numeric values
//!
//! This module defines an object type which can compactly represent an array
//! of basic values: characters, integers, floating point numbers.
//!
//! Arrays are sequence types and behave very much like lists, except that
//! the type of objects stored in them is constrained.
//!
//! Type codes:
//!   'b' - signed char (int, 1 byte)
//!   'B' - unsigned char (int, 1 byte)
//!   'u' - Unicode character (2 bytes, deprecated)
//!   'h' - signed short (int, 2 bytes)
//!   'H' - unsigned short (int, 2 bytes)
//!   'i' - signed int (int, 2-4 bytes)
//!   'I' - unsigned int (int, 2-4 bytes)
//!   'l' - signed long (int, 4 bytes)
//!   'L' - unsigned long (int, 4 bytes)
//!   'q' - signed long long (int, 8 bytes)
//!   'Q' - unsigned long long (int, 8 bytes)
//!   'f' - float (4 bytes)
//!   'd' - double (8 bytes)

const std = @import("std");
const builtin = @import("builtin");

/// All available type codes
pub const typecodes = "bBuhHiIlLqQfd";

/// Type code enum matching CPython's array module
pub const TypeCode = enum(u8) {
    b = 'b', // signed char
    B = 'B', // unsigned char
    u = 'u', // unicode (deprecated)
    h = 'h', // signed short
    H = 'H', // unsigned short
    i = 'i', // signed int
    I = 'I', // unsigned int
    l = 'l', // signed long
    L = 'L', // unsigned long
    q = 'q', // signed long long
    Q = 'Q', // unsigned long long
    f = 'f', // float
    d = 'd', // double

    pub fn fromChar(c: u8) ?TypeCode {
        return switch (c) {
            'b' => .b,
            'B' => .B,
            'u' => .u,
            'h' => .h,
            'H' => .H,
            'i' => .i,
            'I' => .I,
            'l' => .l,
            'L' => .L,
            'q' => .q,
            'Q' => .Q,
            'f' => .f,
            'd' => .d,
            else => null,
        };
    }

    pub fn itemsize(self: TypeCode) usize {
        return switch (self) {
            .b, .B => 1,
            .u, .h, .H => 2,
            .i, .I, .l, .L, .f => 4,
            .q, .Q, .d => 8,
        };
    }
};

/// Python array object - contiguous typed storage
pub fn ArrayType(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        allocator: std.mem.Allocator,
        typecode: TypeCode,

        pub fn init(allocator: std.mem.Allocator, typecode: TypeCode) Self {
            return .{
                .items = &[_]T{},
                .allocator = allocator,
                .typecode = typecode,
            };
        }

        pub fn initWithCapacity(allocator: std.mem.Allocator, typecode: TypeCode, capacity: usize) !Self {
            const items = try allocator.alloc(T, capacity);
            return .{
                .items = items[0..0],
                .allocator = allocator,
                .typecode = typecode,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.items.len > 0) {
                self.allocator.free(self.items);
            }
        }

        pub fn append(self: *Self, value: T) !void {
            const new_items = try self.allocator.realloc(self.items, self.items.len + 1);
            new_items[self.items.len] = value;
            self.items = new_items;
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.items.len) return null;
            return self.items[index];
        }

        pub fn set(self: *Self, index: usize, value: T) void {
            if (index < self.items.len) {
                self.items[index] = value;
            }
        }

        /// Optimized sum - uses SIMD when available
        pub fn sum(self: *const Self) T {
            if (self.items.len == 0) return 0;

            // Use SIMD for large arrays
            if (self.items.len >= 16 and @typeInfo(T) == .int) {
                return simdSum(T, self.items);
            }

            var result: T = 0;
            for (self.items) |item| {
                result += item;
            }
            return result;
        }

        /// Convert to list
        pub fn tolist(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList(T) {
            var list = std.ArrayList(T).init(allocator);
            try list.appendSlice(self.items);
            return list;
        }
    };
}

/// SIMD-optimized sum for integer arrays
fn simdSum(comptime T: type, items: []const T) T {
    const vec_len = 8; // Process 8 elements at a time
    var result: T = 0;

    // Vectorized loop
    var i: usize = 0;
    while (i + vec_len <= items.len) : (i += vec_len) {
        const vec: @Vector(vec_len, T) = items[i..][0..vec_len].*;
        result += @reduce(.Add, vec);
    }

    // Scalar cleanup
    while (i < items.len) : (i += 1) {
        result += items[i];
    }

    return result;
}

/// Generic array that stores any type (runtime type selection)
pub const Array = struct {
    data: []u8,
    len: usize,
    typecode: TypeCode,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create a new array with the given typecode
    pub fn init(allocator: std.mem.Allocator, typecode_char: u8) !Self {
        const tc = TypeCode.fromChar(typecode_char) orelse return error.InvalidTypeCode;
        return .{
            .data = &[_]u8{},
            .len = 0,
            .typecode = tc,
            .allocator = allocator,
        };
    }

    /// Create array from initializer list
    pub fn fromSlice(allocator: std.mem.Allocator, typecode_char: u8, values: anytype) !Self {
        const tc = TypeCode.fromChar(typecode_char) orelse return error.InvalidTypeCode;
        const item_size = tc.itemsize();

        var self = Self{
            .data = try allocator.alloc(u8, values.len * item_size),
            .len = values.len,
            .typecode = tc,
            .allocator = allocator,
        };

        // Copy values
        for (values, 0..) |val, i| {
            self.setAt(i, val);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
    }

    pub fn length(self: *const Self) usize {
        return self.len;
    }

    pub fn itemsize(self: *const Self) usize {
        return self.typecode.itemsize();
    }

    /// Get item at index as i64
    pub fn getAt(self: *const Self, index: usize) ?i64 {
        if (index >= self.len) return null;
        const offset = index * self.typecode.itemsize();

        return switch (self.typecode) {
            .b => @as(i64, @as(*const i8, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .B => @as(i64, self.data[offset]),
            .h => @as(i64, @as(*const i16, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .H => @as(i64, @as(*const u16, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .i, .l => @as(i64, @as(*const i32, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .I, .L => @as(i64, @as(*const u32, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .q => @as(*const i64, @ptrCast(@alignCast(self.data.ptr + offset))).*,
            .Q => @intCast(@as(*const u64, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .f => @intFromFloat(@as(*const f32, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .d => @intFromFloat(@as(*const f64, @ptrCast(@alignCast(self.data.ptr + offset))).*),
            .u => @as(i64, @as(*const u16, @ptrCast(@alignCast(self.data.ptr + offset))).*),
        };
    }

    /// Set item at index
    pub fn setAt(self: *Self, index: usize, value: anytype) void {
        if (index >= self.len) return;
        const offset = index * self.typecode.itemsize();

        switch (self.typecode) {
            .b => @as(*i8, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .B => self.data[offset] = @intCast(value),
            .h => @as(*i16, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .H => @as(*u16, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .i, .l => @as(*i32, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .I, .L => @as(*u32, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .q => @as(*i64, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .Q => @as(*u64, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
            .f => @as(*f32, @ptrCast(@alignCast(self.data.ptr + offset))).* = @floatFromInt(value),
            .d => @as(*f64, @ptrCast(@alignCast(self.data.ptr + offset))).* = @floatFromInt(value),
            .u => @as(*u16, @ptrCast(@alignCast(self.data.ptr + offset))).* = @intCast(value),
        }
    }

    /// Append a value to the array
    pub fn append(self: *Self, value: anytype) !void {
        const new_size = (self.len + 1) * self.typecode.itemsize();
        self.data = try self.allocator.realloc(self.data, new_size);
        self.len += 1;
        self.setAt(self.len - 1, value);
    }

    /// Sum all elements (optimized)
    pub fn sum(self: *const Self) i64 {
        if (self.len == 0) return 0;

        var result: i64 = 0;
        for (0..self.len) |i| {
            result += self.getAt(i) orelse 0;
        }
        return result;
    }

    /// Get buffer info for protocol
    pub fn buffer_info(self: *const Self) struct { ptr: usize, len: usize } {
        return .{
            .ptr = @intFromPtr(self.data.ptr),
            .len = self.len,
        };
    }
};

/// Create array from typecode and optional initializer
/// Usage: array.array('i', [1, 2, 3])
pub fn array(allocator: std.mem.Allocator, typecode: []const u8, initializer: anytype) !Array {
    if (typecode.len != 1) return error.InvalidTypeCode;

    const T = @TypeOf(initializer);
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .Slice) {
        return Array.fromSlice(allocator, typecode[0], initializer);
    }

    return Array.init(allocator, typecode[0]);
}

// ============================================================================
// Tests
// ============================================================================

test "array basic" {
    const allocator = std.testing.allocator;

    var arr = try Array.init(allocator, 'i');
    defer arr.deinit();

    try arr.append(1);
    try arr.append(2);
    try arr.append(3);

    try std.testing.expectEqual(@as(usize, 3), arr.length());
    try std.testing.expectEqual(@as(?i64, 1), arr.getAt(0));
    try std.testing.expectEqual(@as(?i64, 2), arr.getAt(1));
    try std.testing.expectEqual(@as(?i64, 3), arr.getAt(2));
}

test "array sum" {
    const allocator = std.testing.allocator;

    var arr = try Array.init(allocator, 'l');
    defer arr.deinit();

    for (0..100) |i| {
        try arr.append(@intCast(i));
    }

    // Sum of 0..99 = 99 * 100 / 2 = 4950
    try std.testing.expectEqual(@as(i64, 4950), arr.sum());
}

test "typecode itemsize" {
    try std.testing.expectEqual(@as(usize, 1), TypeCode.b.itemsize());
    try std.testing.expectEqual(@as(usize, 4), TypeCode.i.itemsize());
    try std.testing.expectEqual(@as(usize, 8), TypeCode.d.itemsize());
}
