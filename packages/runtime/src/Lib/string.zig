//! Python 'string' module - Common string operations
//!
//! Provides string constants and template formatting.
//! Note: Most string operations are on str type directly.
//!
//! Mirrors: CPython Lib/string.py

const std = @import("std");

// ============================================================================
// String Constants
// ============================================================================

/// String of ASCII lowercase letters: 'abcdefghijklmnopqrstuvwxyz'
pub const ascii_lowercase = "abcdefghijklmnopqrstuvwxyz";

/// String of ASCII uppercase letters: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
pub const ascii_uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

/// String of ASCII letters (lowercase + uppercase)
pub const ascii_letters = ascii_lowercase ++ ascii_uppercase;

/// String of ASCII decimal digits: '0123456789'
pub const digits = "0123456789";

/// String of ASCII hexadecimal digits: '0123456789abcdefABCDEF'
pub const hexdigits = "0123456789abcdefABCDEF";

/// String of ASCII octal digits: '01234567'
pub const octdigits = "01234567";

/// String of ASCII punctuation characters
pub const punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";

/// String of ASCII whitespace characters
pub const whitespace = " \t\n\r\x0b\x0c";

/// String of printable ASCII characters
pub const printable = digits ++ ascii_letters ++ punctuation ++ " \t\n\r\x0b\x0c";

// ============================================================================
// Formatter (simplified Template-like functionality)
// ============================================================================

pub const Formatter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Formatter {
        return .{ .allocator = allocator };
    }

    /// Format a string with named arguments
    /// Format: "Hello {name}, you are {age} years old"
    pub fn format(self: Formatter, template: []const u8, kwargs: anytype) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < template.len) {
            if (template[i] == '{') {
                if (i + 1 < template.len and template[i + 1] == '{') {
                    // Escaped brace
                    try result.append(self.allocator, '{');
                    i += 2;
                } else {
                    // Find closing brace
                    const start = i + 1;
                    var end = start;
                    while (end < template.len and template[end] != '}') {
                        end += 1;
                    }

                    if (end >= template.len) {
                        return error.UnmatchedBrace;
                    }

                    const key = template[start..end];

                    // Look up the value
                    inline for (std.meta.fields(@TypeOf(kwargs))) |field| {
                        if (std.mem.eql(u8, field.name, key)) {
                            const value = @field(kwargs, field.name);
                            try appendValue(&result, self.allocator, value);
                            break;
                        }
                    }

                    i = end + 1;
                }
            } else if (template[i] == '}') {
                if (i + 1 < template.len and template[i + 1] == '}') {
                    // Escaped brace
                    try result.append(self.allocator, '}');
                    i += 2;
                } else {
                    return error.UnmatchedBrace;
                }
            } else {
                try result.append(self.allocator, template[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn appendValue(result: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
        const T = @TypeOf(value);
        if (T == []const u8 or T == []u8) {
            try result.appendSlice(allocator, value);
        } else if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) {
            // Pointer to array (string literal)
            try result.appendSlice(allocator, value);
        } else if (@typeInfo(T) == .int) {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            try result.appendSlice(allocator, str);
        } else if (@typeInfo(T) == .float) {
            var buf: [64]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            try result.appendSlice(allocator, str);
        } else if (T == bool) {
            try result.appendSlice(allocator, if (value) "True" else "False");
        }
    }
};

// ============================================================================
// Template (Python-style string.Template)
// ============================================================================

pub const Template = struct {
    template: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, template: []const u8) Template {
        return .{
            .template = template,
            .allocator = allocator,
        };
    }

    /// Substitute $name or ${name} with values from mapping
    pub fn substitute(self: Template, kwargs: anytype) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < self.template.len) {
            if (self.template[i] == '$') {
                if (i + 1 < self.template.len) {
                    if (self.template[i + 1] == '$') {
                        // Escaped $
                        try result.append(self.allocator, '$');
                        i += 2;
                    } else if (self.template[i + 1] == '{') {
                        // ${name} form
                        const start = i + 2;
                        var end = start;
                        while (end < self.template.len and self.template[end] != '}') {
                            end += 1;
                        }

                        if (end >= self.template.len) {
                            return error.UnmatchedBrace;
                        }

                        const key = self.template[start..end];
                        try substituteKey(&result, key, kwargs);
                        i = end + 1;
                    } else {
                        // $name form
                        const start = i + 1;
                        var end = start;
                        while (end < self.template.len and isIdChar(self.template[end])) {
                            end += 1;
                        }

                        if (end > start) {
                            const key = self.template[start..end];
                            try substituteKey(&result, self.allocator, key, kwargs);
                            i = end;
                        } else {
                            try result.append(self.allocator, '$');
                            i += 1;
                        }
                    }
                } else {
                    try result.append(self.allocator, '$');
                    i += 1;
                }
            } else {
                try result.append(self.allocator, self.template[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Safe substitute - missing keys left unchanged
    pub fn safe_substitute(self: Template, kwargs: anytype) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < self.template.len) {
            if (self.template[i] == '$') {
                if (i + 1 < self.template.len) {
                    if (self.template[i + 1] == '$') {
                        try result.append(self.allocator, '$');
                        i += 2;
                    } else if (self.template[i + 1] == '{') {
                        const start = i + 2;
                        var end = start;
                        while (end < self.template.len and self.template[end] != '}') {
                            end += 1;
                        }

                        if (end >= self.template.len) {
                            // Leave as-is
                            try result.appendSlice(self.allocator, self.template[i..]);
                            break;
                        }

                        const key = self.template[start..end];
                        if (!trySubstituteKey(&result, self.allocator, key, kwargs)) {
                            try result.appendSlice(self.allocator, self.template[i .. end + 1]);
                        }
                        i = end + 1;
                    } else {
                        const start = i + 1;
                        var end = start;
                        while (end < self.template.len and isIdChar(self.template[end])) {
                            end += 1;
                        }

                        if (end > start) {
                            const key = self.template[start..end];
                            if (!trySubstituteKey(&result, self.allocator, key, kwargs)) {
                                try result.appendSlice(self.allocator, self.template[i..end]);
                            }
                            i = end;
                        } else {
                            try result.append(self.allocator, '$');
                            i += 1;
                        }
                    }
                } else {
                    try result.append(self.allocator, '$');
                    i += 1;
                }
            } else {
                try result.append(self.allocator, self.template[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn isIdChar(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_';
    }

    fn substituteKey(result: *std.ArrayList(u8), allocator: std.mem.Allocator, key: []const u8, kwargs: anytype) !void {
        inline for (std.meta.fields(@TypeOf(kwargs))) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                const value = @field(kwargs, field.name);
                try Formatter.appendValue(result, allocator, value);
                return;
            }
        }
        return error.KeyError;
    }

    fn trySubstituteKey(result: *std.ArrayList(u8), allocator: std.mem.Allocator, key: []const u8, kwargs: anytype) bool {
        inline for (std.meta.fields(@TypeOf(kwargs))) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                const value = @field(kwargs, field.name);
                Formatter.appendValue(result, allocator, value) catch return false;
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Convert string to title case
pub fn capwords(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len == 0) return allocator.dupe(u8, "");

    var result = try allocator.alloc(u8, s.len);
    var cap_next = true;

    for (s, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            result[i] = c;
            cap_next = true;
        } else if (cap_next) {
            result[i] = std.ascii.toUpper(c);
            cap_next = false;
        } else {
            result[i] = std.ascii.toLower(c);
        }
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "string constants" {
    try std.testing.expectEqual(@as(usize, 26), ascii_lowercase.len);
    try std.testing.expectEqual(@as(usize, 26), ascii_uppercase.len);
    try std.testing.expectEqual(@as(usize, 52), ascii_letters.len);
    try std.testing.expectEqual(@as(usize, 10), digits.len);
    try std.testing.expectEqual(@as(usize, 22), hexdigits.len);
}

test "Formatter format" {
    const allocator = std.testing.allocator;
    const formatter = Formatter.init(allocator);

    const result = try formatter.format("Hello {name}!", .{ .name = "World" });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World!", result);
}

test "Formatter with numbers" {
    const allocator = std.testing.allocator;
    const formatter = Formatter.init(allocator);

    const result = try formatter.format("{name} is {age} years old", .{ .name = "Alice", .age = @as(i32, 30) });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Alice is 30 years old", result);
}

test "Template substitute" {
    const allocator = std.testing.allocator;
    const tmpl = Template.init(allocator, "Hello $name!");

    const result = try tmpl.substitute(.{ .name = "World" });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World!", result);
}

test "Template with braces" {
    const allocator = std.testing.allocator;
    const tmpl = Template.init(allocator, "Hello ${name}!");

    const result = try tmpl.substitute(.{ .name = "World" });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World!", result);
}

test "Template escaped dollar" {
    const allocator = std.testing.allocator;
    const tmpl = Template.init(allocator, "Price: $$100");

    const result = try tmpl.substitute(.{});
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Price: $100", result);
}

test "capwords" {
    const allocator = std.testing.allocator;

    const result = try capwords(allocator, "hello world");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World", result);
}

test "capwords with multiple spaces" {
    const allocator = std.testing.allocator;

    const result = try capwords(allocator, "  hello   world  ");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("  Hello   World  ", result);
}
