/// bltinmodule - Built-in Functions Module
/// Mirrors cpython/Python/bltinmodule.c
///
/// This module provides Python's built-in functions that are always available:
/// - Type conversion: int(), float(), str(), bool(), list(), dict(), etc.
/// - Math: abs(), pow(), round(), min(), max(), sum(), divmod()
/// - Iteration: iter(), next(), len(), range(), enumerate(), zip(), map(), filter()
/// - I/O: print(), input(), open()
/// - Object introspection: type(), isinstance(), issubclass(), hasattr(), getattr(), setattr()
/// - Execution: eval(), exec(), compile()
/// - Other: sorted(), reversed(), all(), any(), hash(), id(), repr(), ascii()
///
/// Most implementations delegate to runtime/builtins.zig for actual logic.

const std = @import("std");
const errors = @import("errors.zig");

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
// Math Functions
// ============================================================================

/// Absolute value
/// Mirrors: builtin abs()
pub fn abs_builtin(value: anytype) @TypeOf(value) {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int => @intCast(@abs(value)),
        .float => @abs(value),
        else => value,
    };
}

/// Power function
/// Mirrors: builtin pow()
pub fn pow_builtin(base: anytype, exp: anytype, mod: anytype) !i64 {
    _ = mod; // TODO: modular exponentiation
    const b: f64 = @floatFromInt(base);
    const e: f64 = @floatFromInt(exp);
    const result = std.math.pow(f64, b, e);
    return @intFromFloat(result);
}

/// Round to nearest integer
/// Mirrors: builtin round()
pub fn round_builtin(value: f64, ndigits: ?i32) f64 {
    if (ndigits) |n| {
        const factor = std.math.pow(f64, 10, @floatFromInt(n));
        return @round(value * factor) / factor;
    }
    return @round(value);
}

/// Integer division and modulo
/// Mirrors: builtin divmod()
pub fn divmod_builtin(a: i64, b: i64) !struct { i64, i64 } {
    if (b == 0) {
        errors.setString("ZeroDivisionError", "integer division or modulo by zero");
        return error.ZeroDivisionError;
    }
    return .{ @divFloor(a, b), @mod(a, b) };
}

/// Minimum value
/// Mirrors: builtin min()
pub fn min_builtin(values: anytype) @TypeOf(values[0]) {
    var result = values[0];
    for (values[1..]) |v| {
        if (v < result) result = v;
    }
    return result;
}

/// Maximum value
/// Mirrors: builtin max()
pub fn max_builtin(values: anytype) @TypeOf(values[0]) {
    var result = values[0];
    for (values[1..]) |v| {
        if (v > result) result = v;
    }
    return result;
}

/// Sum of iterable
/// Mirrors: builtin sum()
pub fn sum_builtin(comptime T: type, values: []const T, start: T) T {
    var result = start;
    for (values) |v| {
        result += v;
    }
    return result;
}

// ============================================================================
// Sequence Functions
// ============================================================================

/// Get length of sequence
/// Mirrors: builtin len()
pub fn len_builtin(value: anytype) !usize {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                return value.len;
            }
            if (ptr_info.child == u8) {
                // C-string
                return std.mem.len(value);
            }
            errors.setString("TypeError", "object has no len()");
            return error.TypeError;
        },
        .array => |arr_info| arr_info.len,
        else => {
            errors.setString("TypeError", "object has no len()");
            return error.TypeError;
        },
    };
}

/// Check if all elements are true
/// Mirrors: builtin all()
pub fn all_builtin(values: anytype) bool {
    for (values) |v| {
        if (!bool_builtin(v)) return false;
    }
    return true;
}

/// Check if any element is true
/// Mirrors: builtin any()
pub fn any_builtin(values: anytype) bool {
    for (values) |v| {
        if (bool_builtin(v)) return true;
    }
    return false;
}

// ============================================================================
// Object Introspection
// ============================================================================

/// Get type name of object
/// Mirrors: builtin type()
pub fn type_builtin(comptime T: type) []const u8 {
    return @typeName(T);
}

/// Get hash of object
/// Mirrors: builtin hash()
pub fn hash_builtin(value: anytype) u64 {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int, .comptime_int => @bitCast(@as(i64, value)),
        .float => @bitCast(value),
        .bool => if (value) 1 else 0,
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                // String hash using FNV-1a
                var h: u64 = 14695981039346656037;
                for (value) |byte| {
                    h ^= byte;
                    h *%= 1099511628211;
                }
                return h;
            }
            return @intFromPtr(value);
        },
        else => @intFromPtr(&value),
    };
}

/// Get unique ID of object
/// Mirrors: builtin id()
pub fn id_builtin(value: anytype) usize {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => @intFromPtr(value),
        else => @intFromPtr(&value),
    };
}

/// Get repr of object
/// Mirrors: builtin repr()
pub fn repr_builtin(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .float, .comptime_float => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .bool => if (value) "True" else "False",
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                // String repr with quotes
                return std.fmt.allocPrint(allocator, "'{s}'", .{value});
            }
            return std.fmt.allocPrint(allocator, "<{s} at {*}>", .{ @typeName(T), value });
        },
        else => std.fmt.allocPrint(allocator, "<{s}>", .{@typeName(T)}),
    };
}

/// Get ASCII representation
/// Mirrors: builtin ascii()
pub fn ascii_builtin(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.append('\'');

    for (value) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\'' and byte != '\\') {
            try result.append(byte);
        } else if (byte == '\\') {
            try result.appendSlice("\\\\");
        } else if (byte == '\'') {
            try result.appendSlice("\\'");
        } else if (byte == '\n') {
            try result.appendSlice("\\n");
        } else if (byte == '\r') {
            try result.appendSlice("\\r");
        } else if (byte == '\t') {
            try result.appendSlice("\\t");
        } else {
            try result.writer().print("\\x{x:0>2}", .{byte});
        }
    }

    try result.append('\'');
    return result.toOwnedSlice();
}

// ============================================================================
// I/O Functions
// ============================================================================

/// Print to stdout
/// Mirrors: builtin print()
pub fn print_builtin(args: anytype, options: struct {
    sep: []const u8 = " ",
    end: []const u8 = "\n",
    flush: bool = false,
}) !void {
    const stdout = std.io.getStdOut().writer();

    inline for (args, 0..) |arg, i| {
        if (i > 0) try stdout.writeAll(options.sep);
        try stdout.print("{any}", .{arg});
    }

    try stdout.writeAll(options.end);

    if (options.flush) {
        // Flush is automatic in Zig
    }
}

/// Read line from stdin
/// Mirrors: builtin input()
pub fn input_builtin(allocator: std.mem.Allocator, prompt: ?[]const u8) ![]const u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();

    if (prompt) |p| {
        try stdout.writeAll(p);
    }

    return stdin.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 4096) orelse {
        return error.EOFError;
    };
}

// ============================================================================
// Callable Functions
// ============================================================================

/// Check if object is callable
/// Mirrors: builtin callable()
pub fn callable_builtin(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"fn", .bound_fn => true,
        .pointer => |ptr_info| {
            return @typeInfo(ptr_info.child) == .@"fn";
        },
        else => false,
    };
}

// ============================================================================
// Sorting
// ============================================================================

/// Sort a slice in-place
/// Mirrors: builtin sorted() - but mutates
pub fn sorted_builtin(comptime T: type, items: []T, reverse: bool) void {
    if (reverse) {
        std.mem.sort(T, items, {}, std.sort.desc(T));
    } else {
        std.mem.sort(T, items, {}, std.sort.asc(T));
    }
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
// Format Function
// ============================================================================

/// Format a value
/// Mirrors: builtin format()
pub fn format_builtin(allocator: std.mem.Allocator, value: anytype, spec: []const u8) ![]const u8 {
    _ = spec; // TODO: full format spec parsing
    return str_builtin(allocator, value);
}

// ============================================================================
// Vars and Globals (stubs)
// ============================================================================

/// Get local variables (stub)
/// Mirrors: builtin locals()
pub fn locals_builtin() void {
    // In AOT compiled code, locals are not accessible at runtime
}

/// Get global variables (stub)
/// Mirrors: builtin globals()
pub fn globals_builtin() void {
    // In AOT compiled code, globals are compile-time constants
}

/// Get variables dictionary (stub)
/// Mirrors: builtin vars()
pub fn vars_builtin(_: anytype) void {
    // Not applicable in AOT
}

// ============================================================================
// Class Building
// ============================================================================

/// Build a class (used by class statement)
/// Mirrors: builtin __build_class__
pub fn __build_class__(func: anytype, name: []const u8, bases: anytype, kwds: anytype) !type {
    _ = func;
    _ = name;
    _ = bases;
    _ = kwds;
    // Class construction is handled at compile time in AOT
    @compileError("__build_class__ is compile-time in AOT");
}

// ============================================================================
// Object Protocol
// ============================================================================

/// Get attribute
/// Mirrors: builtin getattr()
pub fn getattr_builtin(obj: anytype, name: []const u8, default: anytype) @TypeOf(default) {
    _ = obj;
    _ = name;
    return default;
}

/// Set attribute
/// Mirrors: builtin setattr()
pub fn setattr_builtin(obj: anytype, name: []const u8, value: anytype) !void {
    _ = obj;
    _ = name;
    _ = value;
    errors.setString("AttributeError", "cannot set attribute");
    return error.AttributeError;
}

/// Delete attribute
/// Mirrors: builtin delattr()
pub fn delattr_builtin(obj: anytype, name: []const u8) !void {
    _ = obj;
    _ = name;
    errors.setString("AttributeError", "cannot delete attribute");
    return error.AttributeError;
}

/// Check if attribute exists
/// Mirrors: builtin hasattr()
pub fn hasattr_builtin(obj: anytype, name: []const u8) bool {
    _ = obj;
    _ = name;
    return false;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the builtins module
pub fn init() void {
    // Builtins are statically available, no initialization needed
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

test "abs function" {
    try std.testing.expectEqual(@as(i32, 5), abs_builtin(@as(i32, -5)));
    try std.testing.expectEqual(@as(f64, 3.14), abs_builtin(@as(f64, -3.14)));
}

test "len function" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(usize, 5), try len_builtin(&arr));
    try std.testing.expectEqual(@as(usize, 5), try len_builtin("hello"));
}

test "all and any" {
    const all_true = [_]bool{ true, true, true };
    const some_false = [_]bool{ true, false, true };

    try std.testing.expect(all_builtin(&all_true));
    try std.testing.expect(!all_builtin(&some_false));
    try std.testing.expect(any_builtin(&some_false));
}

test "hash function" {
    const h1 = hash_builtin("hello");
    const h2 = hash_builtin("hello");
    const h3 = hash_builtin("world");

    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
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
