/// conversions - Type Conversion Functions
/// int(), float(), str(), bool() built-in implementations.

const std = @import("std");
const errors = @import("../errors.zig");

// ============================================================================
// Type Conversion Functions
// ============================================================================

/// Convert value to integer
/// Mirrors: builtin int()
pub fn int_builtin(value: anytype) !i64 {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => @intCast(value),
        .float, .comptime_float => @intFromFloat(value),
        .bool => if (value) @as(i64, 1) else @as(i64, 0),
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                // String to int
                return std.fmt.parseInt(i64, value, 10) catch {
                    errors.setString("ValueError", "invalid literal for int()");
                    return error.ValueError;
                };
            }
            errors.setString("TypeError", "int() argument must be a string or number");
            return error.TypeError;
        },
        else => {
            errors.setString("TypeError", "int() argument must be a string or number");
            return error.TypeError;
        },
    };
}

/// Convert value to integer with base
pub fn int_with_base(value: []const u8, base: u8) !i64 {
    return std.fmt.parseInt(i64, value, base) catch {
        errors.format("ValueError", "invalid literal for int() with base {d}", .{base});
        return error.ValueError;
    };
}

/// Convert value to float
/// Mirrors: builtin float()
pub fn float_builtin(value: anytype) !f64 {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => @floatFromInt(value),
        .float, .comptime_float => @floatCast(value),
        .bool => if (value) @as(f64, 1.0) else @as(f64, 0.0),
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                return std.fmt.parseFloat(f64, value) catch {
                    errors.setString("ValueError", "could not convert string to float");
                    return error.ValueError;
                };
            }
            errors.setString("TypeError", "float() argument must be a string or number");
            return error.TypeError;
        },
        else => {
            errors.setString("TypeError", "float() argument must be a string or number");
            return error.TypeError;
        },
    };
}

/// Convert value to string
/// Mirrors: builtin str()
pub fn str_builtin(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .float, .comptime_float => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .bool => if (value) "True" else "False",
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                return allocator.dupe(u8, value);
            }
            return std.fmt.allocPrint(allocator, "{any}", .{value});
        },
        else => std.fmt.allocPrint(allocator, "{any}", .{value}),
    };
}

/// Convert value to bool
/// Mirrors: builtin bool()
pub fn bool_builtin(value: anytype) bool {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => value != 0,
        .float, .comptime_float => value != 0.0,
        .bool => value,
        .optional => value != null,
        .pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                return value.len > 0;
            }
            return value != null;
        },
        else => true,
    };
}

// ============================================================================
// Binary/Hex/Oct Conversion
// ============================================================================

/// Convert int to binary string
/// Mirrors: builtin bin()
pub fn bin_builtin(allocator: std.mem.Allocator, value: i64) ![]const u8 {
    if (value < 0) {
        return std.fmt.allocPrint(allocator, "-0b{b}", .{@as(u64, @intCast(-value))});
    }
    return std.fmt.allocPrint(allocator, "0b{b}", .{@as(u64, @intCast(value))});
}

/// Convert int to hex string
/// Mirrors: builtin hex()
pub fn hex_builtin(allocator: std.mem.Allocator, value: i64) ![]const u8 {
    if (value < 0) {
        return std.fmt.allocPrint(allocator, "-0x{x}", .{@as(u64, @intCast(-value))});
    }
    return std.fmt.allocPrint(allocator, "0x{x}", .{@as(u64, @intCast(value))});
}

/// Convert int to octal string
/// Mirrors: builtin oct()
pub fn oct_builtin(allocator: std.mem.Allocator, value: i64) ![]const u8 {
    if (value < 0) {
        return std.fmt.allocPrint(allocator, "-0o{o}", .{@as(u64, @intCast(-value))});
    }
    return std.fmt.allocPrint(allocator, "0o{o}", .{@as(u64, @intCast(value))});
}

/// Get Unicode code point
/// Mirrors: builtin ord()
pub fn ord_builtin(char: []const u8) !u32 {
    if (char.len == 0) {
        errors.setString("TypeError", "ord() expected a character");
        return error.TypeError;
    }
    // Handle UTF-8 decoding
    const len = std.unicode.utf8ByteSequenceLength(char[0]) catch {
        return char[0];
    };
    if (len > char.len) {
        return char[0];
    }
    return std.unicode.utf8Decode(char[0..len]) catch char[0];
}

/// Get character from code point
/// Mirrors: builtin chr()
pub fn chr_builtin(allocator: std.mem.Allocator, code: u32) ![]const u8 {
    if (code > 0x10FFFF) {
        errors.format("ValueError", "chr() arg not in range(0x110000): {d}", .{code});
        return error.ValueError;
    }
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(@intCast(code), &buf) catch {
        errors.setString("ValueError", "chr() arg is not a valid code point");
        return error.ValueError;
    };
    return allocator.dupe(u8, buf[0..len]);
}

// ============================================================================
// Tests
// ============================================================================

test "int conversions" {
    try std.testing.expectEqual(@as(i64, 42), try int_builtin(42));
    try std.testing.expectEqual(@as(i64, 3), try int_builtin(3.7));
    try std.testing.expectEqual(@as(i64, 1), try int_builtin(true));
}

test "float conversions" {
    try std.testing.expectEqual(@as(f64, 42.0), try float_builtin(42));
    try std.testing.expectEqual(@as(f64, 3.14), try float_builtin(3.14));
}

test "bool conversions" {
    try std.testing.expect(bool_builtin(1));
    try std.testing.expect(!bool_builtin(0));
    try std.testing.expect(bool_builtin("hello"));
    try std.testing.expect(!bool_builtin(""));
}

test "bin/hex/oct" {
    const allocator = std.testing.allocator;

    const bin_str = try bin_builtin(allocator, 42);
    defer allocator.free(bin_str);
    try std.testing.expectEqualStrings("0b101010", bin_str);

    const hex_str = try hex_builtin(allocator, 255);
    defer allocator.free(hex_str);
    try std.testing.expectEqualStrings("0xff", hex_str);

    const oct_str = try oct_builtin(allocator, 8);
    defer allocator.free(oct_str);
    try std.testing.expectEqualStrings("0o10", oct_str);
}

test "ord and chr" {
    const allocator = std.testing.allocator;

    try std.testing.expectEqual(@as(u32, 65), try ord_builtin("A"));
    try std.testing.expectEqual(@as(u32, 0x1F600), try ord_builtin("😀"));

    const chr_a = try chr_builtin(allocator, 65);
    defer allocator.free(chr_a);
    try std.testing.expectEqualStrings("A", chr_a);
}
