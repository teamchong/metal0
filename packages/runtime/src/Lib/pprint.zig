//! CPython source: Lib/pprint.py
//!
//! Provides a capability to "pretty-print" arbitrary data structures
//! in a form which can be used as input to the interpreter.
//!
//! Mirrors: CPython Lib/pprint.py

const std = @import("std");

// ============================================================================
// Configuration
// ============================================================================

pub const PrettyPrinterOptions = struct {
    indent: usize = 1,
    width: usize = 80,
    depth: ?usize = null,
    compact: bool = false,
    sort_dicts: bool = true,
    underscore_numbers: bool = false,
};

// ============================================================================
// PrettyPrinter
// ============================================================================

pub const PrettyPrinter = struct {
    allocator: std.mem.Allocator,
    options: PrettyPrinterOptions,

    pub fn init(allocator: std.mem.Allocator) PrettyPrinter {
        return .{
            .allocator = allocator,
            .options = .{},
        };
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, options: PrettyPrinterOptions) PrettyPrinter {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Format a value as a pretty-printed string
    pub fn pformat(self: *const PrettyPrinter, value: anytype) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try self.formatValue(&result, value, 0, 0);

        return result.toOwnedSlice();
    }

    /// Print a value to stdout
    pub fn pprint(self: *const PrettyPrinter, value: anytype) !void {
        const formatted = try self.pformat(value);
        defer self.allocator.free(formatted);

        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{formatted});
    }

    fn formatValue(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype, level: usize, allowance: usize) !void {
        const T = @TypeOf(value);

        // Check depth limit
        if (self.options.depth) |max_depth| {
            if (level >= max_depth) {
                try result.appendSlice("...");
                return;
            }
        }

        const type_info = @typeInfo(T);

        switch (type_info) {
            .int, .comptime_int => {
                try self.formatInt(result, value);
            },
            .float, .comptime_float => {
                try self.formatFloat(result, value);
            },
            .bool => {
                try result.appendSlice(if (value) "True" else "False");
            },
            .pointer => |ptr| {
                if (ptr.size == .Slice) {
                    if (ptr.child == u8) {
                        try self.formatString(result, value);
                    } else {
                        try self.formatSlice(result, value, level, allowance);
                    }
                } else if (ptr.size == .One) {
                    if (@typeInfo(ptr.child) == .array) {
                        const child_info = @typeInfo(ptr.child).array;
                        if (child_info.child == u8) {
                            try self.formatString(result, value);
                        } else {
                            try self.formatArray(result, value, level, allowance);
                        }
                    } else {
                        try self.formatPointer(result, value);
                    }
                } else {
                    try self.formatPointer(result, value);
                }
            },
            .array => |arr| {
                if (arr.child == u8) {
                    try self.formatString(result, &value);
                } else {
                    try self.formatArray(result, &value, level, allowance);
                }
            },
            .optional => {
                if (value) |v| {
                    try self.formatValue(result, v, level, allowance);
                } else {
                    try result.appendSlice("None");
                }
            },
            .@"struct" => |s| {
                if (s.is_tuple) {
                    try self.formatTuple(result, value, level, allowance);
                } else {
                    try self.formatStruct(result, value, level, allowance);
                }
            },
            .@"enum" => {
                try self.formatEnum(result, value);
            },
            .void => {
                try result.appendSlice("None");
            },
            else => {
                try result.appendSlice("<unprintable>");
            },
        }
    }

    fn formatInt(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype) !void {
        var buf: [64]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;

        if (self.options.underscore_numbers and str.len > 4) {
            // Add underscores for readability (e.g., 1_000_000)
            var formatted = std.ArrayList(u8).init(self.allocator);
            defer formatted.deinit();

            var count: usize = 0;
            var i = str.len;
            while (i > 0) : (i -= 1) {
                if (count > 0 and count % 3 == 0 and str[i - 1] != '-') {
                    try formatted.insert(0, '_');
                }
                try formatted.insert(0, str[i - 1]);
                count += 1;
            }
            try result.appendSlice(formatted.items);
        } else {
            try result.appendSlice(str);
        }
    }

    fn formatFloat(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype) !void {
        _ = self;
        var buf: [64]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        try result.appendSlice(str);
    }

    fn formatString(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: []const u8) !void {
        _ = self;
        try result.append('\'');
        for (value) |c| {
            switch (c) {
                '\'' => try result.appendSlice("\\'"),
                '\\' => try result.appendSlice("\\\\"),
                '\n' => try result.appendSlice("\\n"),
                '\r' => try result.appendSlice("\\r"),
                '\t' => try result.appendSlice("\\t"),
                else => {
                    if (c < 32 or c > 126) {
                        var buf: [6]u8 = undefined;
                        const hex = std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{c}) catch continue;
                        try result.appendSlice(hex);
                    } else {
                        try result.append(c);
                    }
                },
            }
        }
        try result.append('\'');
    }

    fn formatSlice(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype, level: usize, allowance: usize) !void {
        try result.append('[');

        const items = value;
        if (items.len == 0) {
            try result.append(']');
            return;
        }

        const new_level = level + 1;
        const indent_str = try self.getIndent(new_level);
        defer self.allocator.free(indent_str);

        // Check if we should use multiline format
        const use_multiline = !self.options.compact and items.len > 3;

        for (items, 0..) |item, i| {
            if (use_multiline) {
                try result.append('\n');
                try result.appendSlice(indent_str);
            } else if (i > 0) {
                try result.appendSlice(", ");
            }

            try self.formatValue(result, item, new_level, allowance);

            if (use_multiline and i < items.len - 1) {
                try result.append(',');
            }
        }

        if (use_multiline) {
            try result.append('\n');
            const outer_indent = try self.getIndent(level);
            defer self.allocator.free(outer_indent);
            try result.appendSlice(outer_indent);
        }

        try result.append(']');
    }

    fn formatArray(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype, level: usize, allowance: usize) !void {
        try result.append('[');

        const arr = value.*;
        if (arr.len == 0) {
            try result.append(']');
            return;
        }

        for (arr, 0..) |item, i| {
            if (i > 0) {
                try result.appendSlice(", ");
            }
            try self.formatValue(result, item, level + 1, allowance);
        }

        try result.append(']');
    }

    fn formatTuple(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype, level: usize, allowance: usize) !void {
        try result.append('(');

        const fields = @typeInfo(@TypeOf(value)).@"struct".fields;

        inline for (fields, 0..) |field, i| {
            if (i > 0) {
                try result.appendSlice(", ");
            }
            try self.formatValue(result, @field(value, field.name), level + 1, allowance);
        }

        // Single element tuple needs trailing comma
        if (fields.len == 1) {
            try result.append(',');
        }

        try result.append(')');
    }

    fn formatStruct(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype, level: usize, allowance: usize) !void {
        const T = @TypeOf(value);
        const type_name = @typeName(T);

        try result.append('{');

        const fields = @typeInfo(T).@"struct".fields;
        if (fields.len == 0) {
            try result.append('}');
            return;
        }

        const new_level = level + 1;
        const use_multiline = !self.options.compact and fields.len > 2;

        inline for (fields, 0..) |field, i| {
            if (use_multiline) {
                try result.append('\n');
                const indent_str = try self.getIndent(new_level);
                defer self.allocator.free(indent_str);
                try result.appendSlice(indent_str);
            } else if (i > 0) {
                try result.appendSlice(", ");
            }

            try result.append('\'');
            try result.appendSlice(field.name);
            try result.appendSlice("': ");
            try self.formatValue(result, @field(value, field.name), new_level, allowance);

            if (use_multiline and i < fields.len - 1) {
                try result.append(',');
            }
        }

        if (use_multiline) {
            try result.append('\n');
            const outer_indent = try self.getIndent(level);
            defer self.allocator.free(outer_indent);
            try result.appendSlice(outer_indent);
        }

        try result.append('}');
        _ = type_name;
    }

    fn formatEnum(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype) !void {
        _ = self;
        const name = @tagName(value);
        try result.appendSlice(name);
    }

    fn formatPointer(self: *const PrettyPrinter, result: *std.ArrayList(u8), value: anytype) !void {
        _ = self;
        _ = value;
        try result.appendSlice("<pointer>");
    }

    fn getIndent(self: *const PrettyPrinter, level: usize) ![]u8 {
        const total = level * self.options.indent;
        const indent_buf = try self.allocator.alloc(u8, total);
        @memset(indent_buf, ' ');
        return indent_buf;
    }
};

// ============================================================================
// Module-level convenience functions
// ============================================================================

/// Format a value as a pretty-printed string
pub fn pformat(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    const pp = PrettyPrinter.init(allocator);
    return pp.pformat(value);
}

/// Format with custom options
pub fn pformatWithOptions(allocator: std.mem.Allocator, value: anytype, options: PrettyPrinterOptions) ![]u8 {
    const pp = PrettyPrinter.initWithOptions(allocator, options);
    return pp.pformat(value);
}

/// Print a value to stdout
pub fn pprint(allocator: std.mem.Allocator, value: anytype) !void {
    const pp = PrettyPrinter.init(allocator);
    try pp.pprint(value);
}

/// Check if a value is printable on a single line
pub fn isReadable(allocator: std.mem.Allocator, value: anytype) !bool {
    const pp = PrettyPrinter.init(allocator);
    const formatted = try pp.pformat(value);
    defer allocator.free(formatted);

    // Check for newlines
    for (formatted) |c| {
        if (c == '\n') return false;
    }
    return true;
}

/// Safe repr - returns a string representation, or error message if it fails
pub fn saferepr(allocator: std.mem.Allocator, value: anytype) []u8 {
    return pformat(allocator, value) catch blk: {
        const err_msg = allocator.dupe(u8, "<error in repr>") catch break :blk "";
        break :blk err_msg;
    };
}

// ============================================================================
// Tests
// ============================================================================

test "pformat int" {
    const allocator = std.testing.allocator;
    const result = try pformat(allocator, @as(i32, 42));
    defer allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "pformat float" {
    const allocator = std.testing.allocator;
    const result = try pformat(allocator, @as(f64, 3.14));
    defer allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "3.14"));
}

test "pformat bool" {
    const allocator = std.testing.allocator;

    const true_result = try pformat(allocator, true);
    defer allocator.free(true_result);
    try std.testing.expectEqualStrings("True", true_result);

    const false_result = try pformat(allocator, false);
    defer allocator.free(false_result);
    try std.testing.expectEqualStrings("False", false_result);
}

test "pformat string" {
    const allocator = std.testing.allocator;
    const result = try pformat(allocator, "hello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("'hello'", result);
}

test "pformat string with escape" {
    const allocator = std.testing.allocator;
    const result = try pformat(allocator, "hello\nworld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("'hello\\nworld'", result);
}

test "pformat optional" {
    const allocator = std.testing.allocator;

    const some_val: ?i32 = 42;
    const some_result = try pformat(allocator, some_val);
    defer allocator.free(some_result);
    try std.testing.expectEqualStrings("42", some_result);

    const null_val: ?i32 = null;
    const null_result = try pformat(allocator, null_val);
    defer allocator.free(null_result);
    try std.testing.expectEqualStrings("None", null_result);
}

test "pformat array" {
    const allocator = std.testing.allocator;
    const arr = [_]i32{ 1, 2, 3 };
    const result = try pformat(allocator, &arr);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[1, 2, 3]", result);
}

test "pformat tuple" {
    const allocator = std.testing.allocator;
    const tuple = .{ 1, "hello", true };
    const result = try pformat(allocator, tuple);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("(1, 'hello', True)", result);
}

test "pformat struct compact" {
    const allocator = std.testing.allocator;
    const pp = PrettyPrinter.initWithOptions(allocator, .{ .compact = true });

    const s = .{ .x = 1, .y = 2 };
    const result = try pp.pformat(s);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{'x': 1, 'y': 2}", result);
}

test "pformat underscore numbers" {
    const allocator = std.testing.allocator;
    const pp = PrettyPrinter.initWithOptions(allocator, .{ .underscore_numbers = true });

    const result = try pp.pformat(@as(i64, 1000000));
    defer allocator.free(result);
    try std.testing.expectEqualStrings("1_000_000", result);
}

test "pformat depth limit" {
    const allocator = std.testing.allocator;
    const pp = PrettyPrinter.initWithOptions(allocator, .{ .depth = 1 });

    const nested = .{ .a = .{ .b = 42 } };
    const result = try pp.pformat(nested);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "...") != null);
}
