//! test.test_ctypes.test_objects - Tests for object handling
//! Reference: cpython/Lib/test/test_ctypes/test_objects.py
//!
//! Tests for ctypes object creation, manipulation, and lifecycle.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Base Object
// ============================================================================

pub const CDataObject = struct {
    const Self = @This();

    type_name: []const u8,
    size: usize,
    data: []u8,
    allocator: std.mem.Allocator,
    owns_memory: bool = true,

    pub fn init(allocator: std.mem.Allocator, type_name: []const u8, size: usize) !Self {
        const data = try allocator.alloc(u8, size);
        @memset(data, 0);
        return .{
            .type_name = type_name,
            .size = size,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.owns_memory) {
            self.allocator.free(self.data);
        }
    }

    pub fn getPtr(self: *Self) *anyopaque {
        return @ptrCast(self.data.ptr);
    }

    pub fn getBytes(self: *const Self) []const u8 {
        return self.data;
    }

    pub fn setBytes(self: *Self, bytes: []const u8) void {
        const len = @min(bytes.len, self.size);
        @memcpy(self.data[0..len], bytes[0..len]);
    }
};

// ============================================================================
// Simple Data Types
// ============================================================================

pub fn SimpleType(comptime T: type, comptime name: []const u8) type {
    return struct {
        const Self = @This();
        pub const type_name = name;

        value: T = std.mem.zeroes(T),

        pub fn init() Self {
            return .{};
        }

        pub fn initValue(val: T) Self {
            return .{ .value = val };
        }

        pub fn getValue(self: *const Self) T {
            return self.value;
        }

        pub fn setValue(self: *Self, val: T) void {
            self.value = val;
        }

        pub fn sizeof() usize {
            return @sizeOf(T);
        }
    };
}

pub const c_int_obj = SimpleType(i32, "c_int");
pub const c_uint_obj = SimpleType(u32, "c_uint");
pub const c_long_obj = SimpleType(i64, "c_long");
pub const c_double_obj = SimpleType(f64, "c_double");

// ============================================================================
// Pointer Object
// ============================================================================

pub fn PointerObject(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const PointedType = T;

        ptr: ?*T = null,

        pub fn init() Self {
            return .{};
        }

        pub fn initPtr(p: *T) Self {
            return .{ .ptr = p };
        }

        pub fn isNull(self: *const Self) bool {
            return self.ptr == null;
        }

        pub fn getContents(self: *const Self) ?*T {
            return self.ptr;
        }

        pub fn setContents(self: *Self, p: ?*T) void {
            self.ptr = p;
        }

        pub fn dereference(self: *const Self) ?T {
            if (self.ptr) |p| {
                return p.*;
            }
            return null;
        }
    };
}

// ============================================================================
// Array Object
// ============================================================================

pub fn ArrayObject(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        pub const ElementType = T;
        pub const length = N;

        items: [N]T = [_]T{std.mem.zeroes(T)} ** N,

        pub fn init() Self {
            return .{};
        }

        pub fn get(self: *const Self, idx: usize) ?T {
            if (idx >= N) return null;
            return self.items[idx];
        }

        pub fn set(self: *Self, idx: usize, val: T) bool {
            if (idx >= N) return false;
            self.items[idx] = val;
            return true;
        }

        pub fn len(_: *const Self) usize {
            return N;
        }

        pub fn slice(self: *Self) []T {
            return &self.items;
        }
    };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testCDataObject() !void {
    const allocator = std.testing.allocator;

    var obj = try CDataObject.init(allocator, "test", 16);
    defer obj.deinit();

    try std.testing.expectEqualStrings("test", obj.type_name);
    try std.testing.expectEqual(@as(usize, 16), obj.size);
}

fn testCDataObjectSetBytes() !void {
    const allocator = std.testing.allocator;

    var obj = try CDataObject.init(allocator, "test", 8);
    defer obj.deinit();

    obj.setBytes("Hello");
    try std.testing.expectEqualStrings("Hello", obj.getBytes()[0..5]);
}

fn testSimpleTypeInt() !void {
    var i = c_int_obj.initValue(42);
    try std.testing.expectEqual(@as(i32, 42), i.getValue());

    i.setValue(-100);
    try std.testing.expectEqual(@as(i32, -100), i.getValue());
}

fn testSimpleTypeDouble() !void {
    var d = c_double_obj.initValue(3.14159);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), d.getValue(), 0.00001);
}

fn testSimpleTypeSizeof() !void {
    try std.testing.expectEqual(@as(usize, 4), c_int_obj.sizeof());
    try std.testing.expectEqual(@as(usize, 8), c_long_obj.sizeof());
    try std.testing.expectEqual(@as(usize, 8), c_double_obj.sizeof());
}

fn testPointerObject() !void {
    var value: i32 = 42;
    const PtrType = PointerObject(i32);

    var ptr = PtrType.initPtr(&value);
    try std.testing.expect(!ptr.isNull());
    try std.testing.expectEqual(@as(?i32, 42), ptr.dereference());

    ptr.setContents(null);
    try std.testing.expect(ptr.isNull());
}

fn testPointerObjectNull() !void {
    const PtrType = PointerObject(i32);
    const ptr = PtrType.init();

    try std.testing.expect(ptr.isNull());
    try std.testing.expect(ptr.dereference() == null);
}

fn testArrayObject() !void {
    const ArrType = ArrayObject(i32, 5);
    var arr = ArrType.init();

    try std.testing.expectEqual(@as(usize, 5), arr.len());

    try std.testing.expect(arr.set(0, 10));
    try std.testing.expect(arr.set(4, 50));
    try std.testing.expect(!arr.set(5, 60)); // Out of bounds

    try std.testing.expectEqual(@as(?i32, 10), arr.get(0));
    try std.testing.expectEqual(@as(?i32, 50), arr.get(4));
    try std.testing.expectEqual(@as(?i32, null), arr.get(5));
}

fn testArrayObjectSlice() !void {
    const ArrType = ArrayObject(i32, 3);
    var arr = ArrType.init();
    _ = arr.set(0, 1);
    _ = arr.set(1, 2);
    _ = arr.set(2, 3);

    const sl = arr.slice();
    try std.testing.expectEqual(@as(usize, 3), sl.len);
    try std.testing.expectEqual(@as(i32, 2), sl[1]);
}

fn testCDataObjectPtr() !void {
    const allocator = std.testing.allocator;

    var obj = try CDataObject.init(allocator, "test", 4);
    defer obj.deinit();

    const ptr = obj.getPtr();
    try std.testing.expect(@intFromPtr(ptr) != 0);
}

fn testSimpleTypeDefault() !void {
    const i = c_int_obj.init();
    try std.testing.expectEqual(@as(i32, 0), i.getValue());

    const d = c_double_obj.init();
    try std.testing.expectEqual(@as(f64, 0.0), d.getValue());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "cdata_object" {
    try testCDataObject();
}

test "cdata_object_set_bytes" {
    try testCDataObjectSetBytes();
}

test "simple_type_int" {
    try testSimpleTypeInt();
}

test "simple_type_double" {
    try testSimpleTypeDouble();
}

test "simple_type_sizeof" {
    try testSimpleTypeSizeof();
}

test "pointer_object" {
    try testPointerObject();
}

test "pointer_object_null" {
    try testPointerObjectNull();
}

test "array_object" {
    try testArrayObject();
}

test "array_object_slice" {
    try testArrayObjectSlice();
}

test "cdata_object_ptr" {
    try testCDataObjectPtr();
}

test "simple_type_default" {
    try testSimpleTypeDefault();
}
