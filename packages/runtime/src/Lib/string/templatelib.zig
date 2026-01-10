//! string.templatelib - Template string support (Python 3.12+)
//! Reference: cpython/Lib/string/templatelib.py
//!
//! CPython __all__: Interpolation, Template
//!
//! Support for t-strings (template strings) - a new string literal type
//! introduced in Python 3.12 for safer string interpolation.

const std = @import("std");

/// Represents an interpolation within a template string
pub const Interpolation = struct {
    const Self = @This();

    value: []const u8,
    expr: []const u8,
    conv: ?u8 = null, // 's', 'r', or 'a' for conversion
    format_spec: ?[]const u8 = null,

    pub fn init(value: []const u8, expr: []const u8) Self {
        return .{
            .value = value,
            .expr = expr,
        };
    }

    /// Get string representation
    pub fn toString(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        var output = std.ArrayList(u8).init(allocator);
        errdefer output.deinit();

        try output.appendSlice(allocator, "Interpolation(");
        try output.appendSlice(allocator, self.expr);
        try output.append(allocator, '=');
        try output.appendSlice(allocator, self.value);
        if (self.conv) |c| {
            try output.appendSlice(allocator, ", conv='");
            try output.append(allocator, c);
            try output.append(allocator, '\'');
        }
        if (self.format_spec) |fs| {
            try output.appendSlice(allocator, ", format_spec='");
            try output.appendSlice(allocator, fs);
            try output.append(allocator, '\'');
        }
        try output.append(allocator, ')');

        return output.toOwnedSlice(allocator);
    }
};

/// Template string - sequence of strings and interpolations
pub const Template = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    parts: std.ArrayList(Part),

    pub const Part = union(enum) {
        string: []const u8,
        interpolation: Interpolation,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .parts = std.ArrayList(Part).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.parts.deinit(self.allocator);
    }

    /// Add a string part
    pub fn addString(self: *Self, s: []const u8) !void {
        try self.parts.append(self.allocator, .{ .string = s });
    }

    /// Add an interpolation
    pub fn addInterpolation(self: *Self, interp: Interpolation) !void {
        try self.parts.append(self.allocator, .{ .interpolation = interp });
    }

    /// Get all string parts
    pub fn strings(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(allocator);
        for (self.parts.items) |part| {
            switch (part) {
                .string => |s| try result.append(allocator, s),
                .interpolation => {},
            }
        }
        return result;
    }

    /// Get all interpolations
    pub fn interpolations(self: *const Self, allocator: std.mem.Allocator) !std.ArrayList(Interpolation) {
        var result = std.ArrayList(Interpolation).init(allocator);
        for (self.parts.items) |part| {
            switch (part) {
                .string => {},
                .interpolation => |i| try result.append(allocator, i),
            }
        }
        return result;
    }

    /// Render the template to a string
    pub fn render(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        var output = std.ArrayList(u8).init(allocator);
        errdefer output.deinit();

        for (self.parts.items) |part| {
            switch (part) {
                .string => |s| try output.appendSlice(allocator, s),
                .interpolation => |i| {
                    // Apply conversion if specified
                    var value = i.value;
                    if (i.conv) |conv| {
                        switch (conv) {
                            's' => {}, // str() - already a string
                            'r' => {}, // repr() - would need special handling
                            'a' => {}, // ascii() - would need special handling
                            else => {},
                        }
                    }
                    try output.appendSlice(allocator, value);
                },
            }
        }

        return output.toOwnedSlice(allocator);
    }

    /// Get the number of parts
    pub fn len(self: *const Self) usize {
        return self.parts.items.len;
    }
};

/// Parse a template literal string
pub fn parseTemplate(allocator: std.mem.Allocator, template: []const u8) !Template {
    var t = Template.init(allocator);
    errdefer t.deinit();

    var pos: usize = 0;
    var start: usize = 0;

    while (pos < template.len) {
        if (template[pos] == '{') {
            // Save preceding string
            if (pos > start) {
                try t.addString(template[start..pos]);
            }

            // Find closing brace
            const end = std.mem.indexOfScalarPos(u8, template, pos + 1, '}') orelse {
                return error.UnmatchedBrace;
            };

            // Parse interpolation
            const expr = template[pos + 1 .. end];
            try t.addInterpolation(Interpolation.init("", expr));

            pos = end + 1;
            start = pos;
        } else if (template[pos] == '}') {
            pos += 1;
        } else {
            pos += 1;
        }
    }

    // Add final string part
    if (pos > start) {
        try t.addString(template[start..pos]);
    }

    return t;
}

// ============================================================================
// Tests
// ============================================================================

test "Interpolation basic" {
    var interp = Interpolation.init("42", "x");
    try std.testing.expectEqualStrings("42", interp.value);
    try std.testing.expectEqualStrings("x", interp.expr);
}

test "Template basic" {
    const allocator = std.testing.allocator;
    var t = Template.init(allocator);
    defer t.deinit();

    try t.addString("Hello, ");
    try t.addInterpolation(Interpolation.init("World", "name"));
    try t.addString("!");

    try std.testing.expectEqual(@as(usize, 3), t.len());

    const rendered = try t.render(allocator);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello, World!", rendered);
}

test "parseTemplate" {
    const allocator = std.testing.allocator;
    var t = try parseTemplate(allocator, "Hello, {name}!");
    defer t.deinit();

    try std.testing.expectEqual(@as(usize, 3), t.len());
}
