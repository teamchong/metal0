//! tomllib._parser - TOML parser implementation
//! Reference: cpython/Lib/tomllib/_parser.py
//!
//! Internal TOML parsing implementation.

const std = @import("std");
const types = @import("_types.zig");

/// Parser error types
pub const ParseError = error{
    InvalidSyntax,
    InvalidKey,
    InvalidValue,
    InvalidString,
    InvalidNumber,
    InvalidDateTime,
    InvalidArray,
    InvalidTable,
    DuplicateKey,
    UnexpectedEOF,
    OutOfMemory,
};

/// Parser state
pub const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    src: []const u8,
    pos: usize,
    line: usize,
    col: usize,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) Self {
        return .{
            .allocator = allocator,
            .src = src,
            .pos = 0,
            .line = 1,
            .col = 1,
        };
    }

    /// Get current character
    pub fn current(self: *Self) ?u8 {
        if (self.pos < self.src.len) {
            return self.src[self.pos];
        }
        return null;
    }

    /// Advance position
    pub fn advance(self: *Self) void {
        if (self.pos < self.src.len) {
            if (self.src[self.pos] == '\n') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
    }

    /// Skip whitespace (but not newlines)
    pub fn skipWs(self: *Self) void {
        while (self.current()) |c| {
            if (c == ' ' or c == '\t') {
                self.advance();
            } else {
                break;
            }
        }
    }

    /// Skip whitespace and newlines
    pub fn skipWsAndNewlines(self: *Self) void {
        while (self.current()) |c| {
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.advance();
            } else if (c == '#') {
                // Skip comment
                while (self.current()) |cc| {
                    if (cc == '\n') break;
                    self.advance();
                }
            } else {
                break;
            }
        }
    }

    /// Parse a key
    pub fn parseKey(self: *Self) ![]const u8 {
        self.skipWs();

        const start = self.pos;
        const c = self.current() orelse return ParseError.UnexpectedEOF;

        if (c == '"') {
            // Quoted key
            return self.parseBasicString();
        } else if (c == '\'') {
            // Literal string key
            return self.parseLiteralString();
        } else {
            // Bare key
            while (self.current()) |ch| {
                if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-') {
                    self.advance();
                } else {
                    break;
                }
            }
            if (self.pos == start) return ParseError.InvalidKey;
            return self.src[start..self.pos];
        }
    }

    /// Parse basic string (double-quoted)
    pub fn parseBasicString(self: *Self) ![]const u8 {
        if (self.current() != '"') return ParseError.InvalidString;
        self.advance();

        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        while (self.current()) |c| {
            if (c == '"') {
                self.advance();
                return result.toOwnedSlice(self.allocator);
            } else if (c == '\\') {
                self.advance();
                const escaped = self.current() orelse return ParseError.InvalidString;
                self.advance();
                const replacement: u8 = switch (escaped) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    else => return ParseError.InvalidString,
                };
                try result.append(self.allocator, replacement);
            } else {
                try result.append(self.allocator, c);
                self.advance();
            }
        }
        return ParseError.UnexpectedEOF;
    }

    /// Parse literal string (single-quoted)
    pub fn parseLiteralString(self: *Self) ![]const u8 {
        if (self.current() != '\'') return ParseError.InvalidString;
        self.advance();

        const start = self.pos;
        while (self.current()) |c| {
            if (c == '\'') {
                const result = self.src[start..self.pos];
                self.advance();
                return result;
            }
            self.advance();
        }
        return ParseError.UnexpectedEOF;
    }

    /// Parse integer
    pub fn parseInteger(self: *Self) !i64 {
        var negative = false;
        if (self.current() == '-') {
            negative = true;
            self.advance();
        } else if (self.current() == '+') {
            self.advance();
        }

        // Check for hex/oct/bin
        if (self.current() == '0' and self.pos + 1 < self.src.len) {
            const next = self.src[self.pos + 1];
            if (next == 'x' or next == 'X') {
                self.advance();
                self.advance();
                return self.parseHexInt(negative);
            } else if (next == 'o' or next == 'O') {
                self.advance();
                self.advance();
                return self.parseOctInt(negative);
            } else if (next == 'b' or next == 'B') {
                self.advance();
                self.advance();
                return self.parseBinInt(negative);
            }
        }

        return self.parseDecInt(negative);
    }

    fn parseDecInt(self: *Self, negative: bool) !i64 {
        var value: i64 = 0;
        var has_digit = false;

        while (self.current()) |c| {
            if (c >= '0' and c <= '9') {
                value = value * 10 + (c - '0');
                has_digit = true;
                self.advance();
            } else if (c == '_') {
                self.advance();
            } else {
                break;
            }
        }

        if (!has_digit) return ParseError.InvalidNumber;
        return if (negative) -value else value;
    }

    fn parseHexInt(self: *Self, negative: bool) !i64 {
        var value: i64 = 0;
        while (self.current()) |c| {
            if (c >= '0' and c <= '9') {
                value = value * 16 + (c - '0');
                self.advance();
            } else if (c >= 'a' and c <= 'f') {
                value = value * 16 + (c - 'a' + 10);
                self.advance();
            } else if (c >= 'A' and c <= 'F') {
                value = value * 16 + (c - 'A' + 10);
                self.advance();
            } else if (c == '_') {
                self.advance();
            } else {
                break;
            }
        }
        return if (negative) -value else value;
    }

    fn parseOctInt(self: *Self, negative: bool) !i64 {
        var value: i64 = 0;
        while (self.current()) |c| {
            if (c >= '0' and c <= '7') {
                value = value * 8 + (c - '0');
                self.advance();
            } else if (c == '_') {
                self.advance();
            } else {
                break;
            }
        }
        return if (negative) -value else value;
    }

    fn parseBinInt(self: *Self, negative: bool) !i64 {
        var value: i64 = 0;
        while (self.current()) |c| {
            if (c == '0' or c == '1') {
                value = value * 2 + (c - '0');
                self.advance();
            } else if (c == '_') {
                self.advance();
            } else {
                break;
            }
        }
        return if (negative) -value else value;
    }
};

/// Parse TOML source into a table
pub fn parse(allocator: std.mem.Allocator, src: []const u8) !types.TomlTable {
    var parser = Parser.init(allocator, src);
    var table = types.TomlTable.init(allocator);

    // Simple implementation - parse key = value pairs
    while (parser.current() != null) {
        parser.skipWsAndNewlines();
        if (parser.current() == null) break;

        // Skip table headers for now
        if (parser.current() == '[') {
            while (parser.current()) |c| {
                if (c == '\n') break;
                parser.advance();
            }
            continue;
        }

        // Parse key = value
        const key = parser.parseKey() catch break;
        parser.skipWs();

        if (parser.current() != '=') continue;
        parser.advance();
        parser.skipWs();

        // Parse value (simplified - just strings for now)
        if (parser.current() == '"') {
            const value = try parser.parseBasicString();
            try table.put(key, .{ .string = value });
        } else if (parser.current() == '\'') {
            const value = try parser.parseLiteralString();
            try table.put(key, .{ .string = value });
        }

        // Skip to end of line
        while (parser.current()) |c| {
            if (c == '\n') break;
            parser.advance();
        }
    }

    return table;
}

// ============================================================================
// Tests
// ============================================================================

test "Parser basic string" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "\"hello world\"");
    const result = try parser.parseBasicString();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "Parser integer" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "42");
    const result = try parser.parseInteger();
    try std.testing.expectEqual(@as(i64, 42), result);
}

test "Parser hex integer" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "0xff");
    const result = try parser.parseInteger();
    try std.testing.expectEqual(@as(i64, 255), result);
}
