//! test.test_ctypes.test_repr - Tests for string representation
//! Reference: cpython/Lib/test/test_ctypes/test_repr.py
//!
//! Tests for __repr__ and string formatting of ctypes objects.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Repr Formatter
// ============================================================================

pub fn formatRepr(comptime T: type, value: T, buf: []u8) []const u8 {
    const type_name = @typeName(T);
    const result = std.fmt.bufPrint(buf, "{s}({any})", .{ type_name, value }) catch {
        return "<repr error>";
    };
    return result;
}

/// Format a ctypes simple type
pub fn formatSimpleRepr(type_name: []const u8, value: anytype, buf: []u8) []const u8 {
    const result = std.fmt.bufPrint(buf, "{s}({any})", .{ type_name, value }) catch {
        return "<repr error>";
    };
    return result;
}

/// Format a pointer type
pub fn formatPointerRepr(type_name: []const u8, addr: usize, buf: []u8) []const u8 {
    if (addr == 0) {
        const result = std.fmt.bufPrint(buf, "{s}(NULL)", .{type_name}) catch {
            return "<repr error>";
        };
        return result;
    }
    const result = std.fmt.bufPrint(buf, "{s}(0x{x})", .{ type_name, addr }) catch {
        return "<repr error>";
    };
    return result;
}

// ============================================================================
// Repr Types
// ============================================================================

pub fn ReprType(comptime T: type, comptime name: []const u8) type {
    return struct {
        const Self = @This();
        pub const type_name = name;

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn repr(self: *const Self, buf: []u8) []const u8 {
            return formatSimpleRepr(name, self.value, buf);
        }
    };
}

pub const c_int_repr = ReprType(i32, "c_int");
pub const c_long_repr = ReprType(i64, "c_long");
pub const c_double_repr = ReprType(f64, "c_double");

// ============================================================================
// Array Repr
// ============================================================================

pub fn ArrayRepr(comptime T: type, comptime N: usize, comptime elem_name: []const u8) type {
    return struct {
        const Self = @This();

        items: [N]T = [_]T{0} ** N,

        pub fn init() Self {
            return .{};
        }

        pub fn repr(self: *const Self, buf: []u8) []const u8 {
            var pos: usize = 0;
            pos += (std.fmt.bufPrint(buf[pos..], "{s}_Array_{d}(", .{ elem_name, N }) catch return "<repr error>").len;

            for (self.items, 0..) |item, i| {
                if (i > 0) {
                    pos += (std.fmt.bufPrint(buf[pos..], ", ", .{}) catch return "<repr error>").len;
                }
                if (i >= 3 and N > 6) {
                    pos += (std.fmt.bufPrint(buf[pos..], "...", .{}) catch return "<repr error>").len;
                    break;
                }
                pos += (std.fmt.bufPrint(buf[pos..], "{}", .{item}) catch return "<repr error>").len;
            }

            pos += (std.fmt.bufPrint(buf[pos..], ")", .{}) catch return "<repr error>").len;
            return buf[0..pos];
        }
    };
}

// ============================================================================
// Structure Repr
// ============================================================================

pub fn StructRepr(comptime name: []const u8, comptime fields: []const FieldInfo) type {
    return struct {
        const Self = @This();
        pub const _fields_ = fields;

        values: [fields.len]i64 = [_]i64{0} ** fields.len,

        pub fn init() Self {
            return .{};
        }

        pub fn repr(self: *const Self, buf: []u8) []const u8 {
            var pos: usize = 0;
            pos += (std.fmt.bufPrint(buf[pos..], "{s}(", .{name}) catch return "<repr error>").len;

            inline for (fields, 0..) |field, i| {
                if (i > 0) {
                    pos += (std.fmt.bufPrint(buf[pos..], ", ", .{}) catch return "<repr error>").len;
                }
                pos += (std.fmt.bufPrint(buf[pos..], "{s}={}", .{ field.name, self.values[i] }) catch return "<repr error>").len;
            }

            pos += (std.fmt.bufPrint(buf[pos..], ")", .{}) catch return "<repr error>").len;
            return buf[0..pos];
        }
    };
}

pub const FieldInfo = struct {
    name: []const u8,
};

// ============================================================================
// Test Cases
// ============================================================================

fn testFormatReprInt() !void {
    var buf: [64]u8 = undefined;
    const repr = formatRepr(i32, 42, &buf);
    try std.testing.expect(std.mem.indexOf(u8, repr, "42") != null);
}

fn testFormatSimpleRepr() !void {
    var buf: [64]u8 = undefined;
    const repr = formatSimpleRepr("c_int", @as(i32, 123), &buf);
    try std.testing.expectEqualStrings("c_int(123)", repr);
}

fn testFormatPointerRepr() !void {
    var buf: [64]u8 = undefined;

    const null_repr = formatPointerRepr("c_void_p", 0, &buf);
    try std.testing.expectEqualStrings("c_void_p(NULL)", null_repr);

    const ptr_repr = formatPointerRepr("c_void_p", 0x12345678, &buf);
    try std.testing.expectEqualStrings("c_void_p(0x12345678)", ptr_repr);
}

fn testCIntRepr() !void {
    var buf: [64]u8 = undefined;
    const ci = c_int_repr.init(-42);
    const repr = ci.repr(&buf);
    try std.testing.expectEqualStrings("c_int(-42)", repr);
}

fn testCDoubleRepr() !void {
    var buf: [64]u8 = undefined;
    const cd = c_double_repr.init(3.14);
    const repr = cd.repr(&buf);
    try std.testing.expect(std.mem.indexOf(u8, repr, "c_double") != null);
    try std.testing.expect(std.mem.indexOf(u8, repr, "3.14") != null);
}

fn testArrayRepr() !void {
    var buf: [128]u8 = undefined;
    const ArrType = ArrayRepr(i32, 3, "c_int");
    var arr = ArrType.init();
    arr.items[0] = 1;
    arr.items[1] = 2;
    arr.items[2] = 3;

    const repr = arr.repr(&buf);
    try std.testing.expect(std.mem.indexOf(u8, repr, "c_int_Array_3") != null);
    try std.testing.expect(std.mem.indexOf(u8, repr, "1") != null);
    try std.testing.expect(std.mem.indexOf(u8, repr, "2") != null);
    try std.testing.expect(std.mem.indexOf(u8, repr, "3") != null);
}

fn testStructRepr() !void {
    var buf: [128]u8 = undefined;
    const PointRepr = StructRepr("Point", &.{
        .{ .name = "x" },
        .{ .name = "y" },
    });
    var pt = PointRepr.init();
    pt.values[0] = 10;
    pt.values[1] = 20;

    const repr = pt.repr(&buf);
    try std.testing.expect(std.mem.indexOf(u8, repr, "Point") != null);
    try std.testing.expect(std.mem.indexOf(u8, repr, "x=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, repr, "y=20") != null);
}

fn testLargeArrayRepr() !void {
    var buf: [128]u8 = undefined;
    const ArrType = ArrayRepr(i32, 100, "c_int");
    var arr = ArrType.init();

    const repr = arr.repr(&buf);
    try std.testing.expect(std.mem.indexOf(u8, repr, "...") != null);
}

fn testReprTypeName() !void {
    try std.testing.expectEqualStrings("c_int", c_int_repr.type_name);
    try std.testing.expectEqualStrings("c_long", c_long_repr.type_name);
    try std.testing.expectEqualStrings("c_double", c_double_repr.type_name);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "format_repr_int" {
    try testFormatReprInt();
}

test "format_simple_repr" {
    try testFormatSimpleRepr();
}

test "format_pointer_repr" {
    try testFormatPointerRepr();
}

test "c_int_repr" {
    try testCIntRepr();
}

test "c_double_repr" {
    try testCDoubleRepr();
}

test "array_repr" {
    try testArrayRepr();
}

test "struct_repr" {
    try testStructRepr();
}

test "large_array_repr" {
    try testLargeArrayRepr();
}

test "repr_type_name" {
    try testReprTypeName();
}
