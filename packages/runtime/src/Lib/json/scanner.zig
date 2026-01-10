//! json.scanner - JSON lexical scanner
//! Reference: cpython/Lib/json/scanner.py
//!
//! CPython __all__: make_scanner
//!
//! Low-level JSON scanning utilities.
//! Note: The actual JSON parsing is done by json_impl/ which uses SIMD-accelerated parsing.

const std = @import("std");

/// JSON number regex pattern (for reference)
/// CPython: NUMBER_RE = re.compile(...)
pub const NUMBER_RE = "-?(?:0|[1-9]\\d*)(?:\\.\\d+)?(?:[eE][+-]?\\d+)?";

/// Token types produced by the scanner
pub const TokenType = enum {
    string,
    number,
    object_start, // {
    object_end, // }
    array_start, // [
    array_end, // ]
    colon,
    comma,
    true_literal,
    false_literal,
    null_literal,
    eof,
    invalid,
};

/// Scanner state
pub const Scanner = struct {
    const Self = @This();

    data: []const u8,
    pos: usize,
    strict: bool,

    pub fn init(data: []const u8, strict: bool) Self {
        return .{
            .data = data,
            .pos = 0,
            .strict = strict,
        };
    }

    /// Skip whitespace
    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.data.len) {
            const c = self.data[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    /// Get next token
    pub fn nextToken(self: *Self) TokenType {
        self.skipWhitespace();

        if (self.pos >= self.data.len) {
            return .eof;
        }

        const c = self.data[self.pos];

        switch (c) {
            '{' => {
                self.pos += 1;
                return .object_start;
            },
            '}' => {
                self.pos += 1;
                return .object_end;
            },
            '[' => {
                self.pos += 1;
                return .array_start;
            },
            ']' => {
                self.pos += 1;
                return .array_end;
            },
            ':' => {
                self.pos += 1;
                return .colon;
            },
            ',' => {
                self.pos += 1;
                return .comma;
            },
            '"' => {
                // Scan string
                self.pos += 1;
                while (self.pos < self.data.len) {
                    const ch = self.data[self.pos];
                    if (ch == '"') {
                        self.pos += 1;
                        return .string;
                    } else if (ch == '\\') {
                        self.pos += 2; // Skip escape sequence
                    } else {
                        self.pos += 1;
                    }
                }
                return .invalid;
            },
            '-', '0'...'9' => {
                // Scan number
                while (self.pos < self.data.len) {
                    const ch = self.data[self.pos];
                    if ((ch >= '0' and ch <= '9') or ch == '.' or ch == 'e' or ch == 'E' or ch == '+' or ch == '-') {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                return .number;
            },
            't' => {
                // true
                if (self.pos + 4 <= self.data.len and std.mem.eql(u8, self.data[self.pos .. self.pos + 4], "true")) {
                    self.pos += 4;
                    return .true_literal;
                }
                return .invalid;
            },
            'f' => {
                // false
                if (self.pos + 5 <= self.data.len and std.mem.eql(u8, self.data[self.pos .. self.pos + 5], "false")) {
                    self.pos += 5;
                    return .false_literal;
                }
                return .invalid;
            },
            'n' => {
                // null
                if (self.pos + 4 <= self.data.len and std.mem.eql(u8, self.data[self.pos .. self.pos + 4], "null")) {
                    self.pos += 4;
                    return .null_literal;
                }
                return .invalid;
            },
            else => return .invalid,
        }
    }
};

/// Create a scanner (CPython compatibility)
/// In CPython this returns a function, here we return a Scanner struct
pub fn make_scanner(data: []const u8, strict: bool) Scanner {
    return Scanner.init(data, strict);
}

// ============================================================================
// Tests
// ============================================================================

test "Scanner basic tokens" {
    var scanner = make_scanner("{\"key\": 123}", true);

    try std.testing.expectEqual(TokenType.object_start, scanner.nextToken());
    try std.testing.expectEqual(TokenType.string, scanner.nextToken());
    try std.testing.expectEqual(TokenType.colon, scanner.nextToken());
    try std.testing.expectEqual(TokenType.number, scanner.nextToken());
    try std.testing.expectEqual(TokenType.object_end, scanner.nextToken());
    try std.testing.expectEqual(TokenType.eof, scanner.nextToken());
}

test "Scanner literals" {
    var scanner = make_scanner("[true, false, null]", true);

    try std.testing.expectEqual(TokenType.array_start, scanner.nextToken());
    try std.testing.expectEqual(TokenType.true_literal, scanner.nextToken());
    try std.testing.expectEqual(TokenType.comma, scanner.nextToken());
    try std.testing.expectEqual(TokenType.false_literal, scanner.nextToken());
    try std.testing.expectEqual(TokenType.comma, scanner.nextToken());
    try std.testing.expectEqual(TokenType.null_literal, scanner.nextToken());
    try std.testing.expectEqual(TokenType.array_end, scanner.nextToken());
}
