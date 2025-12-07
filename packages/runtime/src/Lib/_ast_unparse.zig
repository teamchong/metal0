//! Python '_ast_unparse' module - AST Unparsing utilities
//!
//! Internal module for converting AST nodes back to Python source code.
//!
//! Mirrors: CPython Lib/ast.py (unparse functionality)

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const UnparseError = error{
    InvalidNode,
    UnsupportedFeature,
    FormattingError,
    OutOfMemory,
};

// ============================================================================
// Precedence levels for expressions
// ============================================================================

pub const Precedence = enum(u8) {
    TUPLE = 0,
    YIELD = 1,
    TEST = 2,
    OR = 3,
    AND = 4,
    NOT = 5,
    CMP = 6,
    EXPR = 7,
    BOR = 8,
    BXOR = 9,
    BAND = 10,
    SHIFT = 11,
    ARITH = 12,
    TERM = 13,
    FACTOR = 14,
    POWER = 15,
    AWAIT = 16,
    ATOM = 17,
};

// ============================================================================
// Unparser
// ============================================================================

/// AST to source code converter
pub const Unparser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    indent_level: usize = 0,
    indent_str: []const u8 = "    ",

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    /// Get the unparsed output
    pub fn getOutput(self: *const Self) []const u8 {
        return self.output.items;
    }

    /// Write string to output
    pub fn write(self: *Self, s: []const u8) !void {
        try self.output.appendSlice(s);
    }

    /// Write a single character
    pub fn writeChar(self: *Self, c: u8) !void {
        try self.output.append(c);
    }

    /// Write newline with indentation
    pub fn newline(self: *Self) !void {
        try self.output.append('\n');
        for (0..self.indent_level) |_| {
            try self.output.appendSlice(self.indent_str);
        }
    }

    /// Increase indentation
    pub fn indent(self: *Self) void {
        self.indent_level += 1;
    }

    /// Decrease indentation
    pub fn dedent(self: *Self) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    /// Write a quoted string
    pub fn writeString(self: *Self, s: []const u8) !void {
        try self.write("\"");
        for (s) |c| {
            switch (c) {
                '\n' => try self.write("\\n"),
                '\r' => try self.write("\\r"),
                '\t' => try self.write("\\t"),
                '\\' => try self.write("\\\\"),
                '"' => try self.write("\\\""),
                else => {
                    if (c >= 32 and c < 127) {
                        try self.writeChar(c);
                    } else {
                        try self.write("\\x");
                        const hex = "0123456789abcdef";
                        try self.writeChar(hex[c >> 4]);
                        try self.writeChar(hex[c & 0xf]);
                    }
                },
            }
        }
        try self.write("\"");
    }

    /// Write an identifier
    pub fn writeIdentifier(self: *Self, name: []const u8) !void {
        try self.write(name);
    }

    /// Write a number
    pub fn writeNumber(self: *Self, value: i64) !void {
        var buf: [32]u8 = undefined;
        const len = std.fmt.formatIntBuf(&buf, value, 10, .lower, .{});
        try self.write(buf[0..len]);
    }

    /// Write a float
    pub fn writeFloat(self: *Self, value: f64) !void {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormattingError;
        try self.write(s);
    }

    /// Clear output
    pub fn clear(self: *Self) void {
        self.output.clearRetainingCapacity();
        self.indent_level = 0;
    }
};

// ============================================================================
// Helper functions
// ============================================================================

/// Escape a string for Python source
pub fn escapeString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (s) |c| {
        switch (c) {
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            '\\' => try result.appendSlice("\\\\"),
            '\'' => try result.appendSlice("\\'"),
            '"' => try result.appendSlice("\\\""),
            else => {
                if (c >= 32 and c < 127) {
                    try result.append(c);
                } else {
                    try result.appendSlice("\\x");
                    const hex = "0123456789abcdef";
                    try result.append(hex[c >> 4]);
                    try result.append(hex[c & 0xf]);
                }
            },
        }
    }

    return result.toOwnedSlice();
}

/// Get operator string
pub fn getOperator(op: []const u8) []const u8 {
    const ops = std.StaticStringMap([]const u8).initComptime(.{
        .{ "Add", "+" },
        .{ "Sub", "-" },
        .{ "Mult", "*" },
        .{ "Div", "/" },
        .{ "FloorDiv", "//" },
        .{ "Mod", "%" },
        .{ "Pow", "**" },
        .{ "LShift", "<<" },
        .{ "RShift", ">>" },
        .{ "BitOr", "|" },
        .{ "BitXor", "^" },
        .{ "BitAnd", "&" },
        .{ "MatMult", "@" },
        .{ "Eq", "==" },
        .{ "NotEq", "!=" },
        .{ "Lt", "<" },
        .{ "LtE", "<=" },
        .{ "Gt", ">" },
        .{ "GtE", ">=" },
        .{ "Is", "is" },
        .{ "IsNot", "is not" },
        .{ "In", "in" },
        .{ "NotIn", "not in" },
        .{ "And", "and" },
        .{ "Or", "or" },
        .{ "Not", "not" },
        .{ "Invert", "~" },
        .{ "UAdd", "+" },
        .{ "USub", "-" },
    });

    return ops.get(op) orelse op;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Unparser init" {
    const allocator = std.testing.allocator;
    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.write("hello");
    try std.testing.expectEqualStrings("hello", unparser.getOutput());
}

test "Unparser indentation" {
    const allocator = std.testing.allocator;
    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.write("def foo():");
    unparser.indent();
    try unparser.newline();
    try unparser.write("pass");

    try std.testing.expect(std.mem.indexOf(u8, unparser.getOutput(), "    pass") != null);
}

test "Unparser writeString" {
    const allocator = std.testing.allocator;
    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.writeString("hello\nworld");
    try std.testing.expectEqualStrings("\"hello\\nworld\"", unparser.getOutput());
}

test "escapeString" {
    const allocator = std.testing.allocator;

    const result = try escapeString(allocator, "hello\nworld");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello\\nworld", result);
}

test "getOperator" {
    try std.testing.expectEqualStrings("+", getOperator("Add"));
    try std.testing.expectEqualStrings("==", getOperator("Eq"));
    try std.testing.expectEqualStrings("and", getOperator("And"));
}

test "Precedence" {
    try std.testing.expect(@intFromEnum(Precedence.ATOM) > @intFromEnum(Precedence.OR));
    try std.testing.expect(@intFromEnum(Precedence.FACTOR) > @intFromEnum(Precedence.ARITH));
}
