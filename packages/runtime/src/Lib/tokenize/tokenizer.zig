//! Tokenizer implementation
//!
//! Lexical scanner for Python source code.

const std = @import("std");
const types = @import("types.zig");
const tokens = @import("tokens.zig");

const TokenType = types.TokenType;
const TokenInfo = types.TokenInfo;
const Position = types.Position;
const EXACT_TOKEN_TYPES = tokens.EXACT_TOKEN_TYPES;

// ============================================================================
// Tokenizer
// ============================================================================

pub const Tokenizer = struct {
    const Self = @This();

    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    indent_stack: std.ArrayList(u32),
    allocator: std.mem.Allocator,
    at_bol: bool, // At beginning of line
    pending_dedents: u32,
    encoding: []const u8,
    done: bool,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        var indent_stack: std.ArrayList(u32) = .{};
        indent_stack.append(allocator, 0) catch {};

        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 0,
            .indent_stack = indent_stack,
            .allocator = allocator,
            .at_bol = true,
            .pending_dedents = 0,
            .encoding = "utf-8",
            .done = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.indent_stack.deinit(self.allocator);
    }

    /// Get the next token
    pub fn next(self: *Self) ?TokenInfo {
        if (self.done) return null;

        // Handle pending dedents
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return TokenInfo.init(
                .DEDENT,
                "",
                Position.init(self.line, self.col),
                Position.init(self.line, self.col),
                self.currentLine(),
            );
        }

        // Skip to first non-whitespace at BOL for indent handling
        if (self.at_bol) {
            const indent = self.countIndent();
            self.at_bol = false;

            const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];
            if (indent > current_indent) {
                self.indent_stack.append(self.allocator, indent) catch {};
                return TokenInfo.init(
                    .INDENT,
                    "",
                    Position.init(self.line, 0),
                    Position.init(self.line, indent),
                    self.currentLine(),
                );
            } else if (indent < current_indent) {
                // Count dedents needed
                while (self.indent_stack.items.len > 1 and
                    self.indent_stack.items[self.indent_stack.items.len - 1] > indent)
                {
                    _ = self.indent_stack.pop();
                    self.pending_dedents += 1;
                }
                if (self.pending_dedents > 0) {
                    self.pending_dedents -= 1;
                    return TokenInfo.init(
                        .DEDENT,
                        "",
                        Position.init(self.line, self.col),
                        Position.init(self.line, self.col),
                        self.currentLine(),
                    );
                }
            }
        }

        // Skip whitespace (not at BOL)
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            self.done = true;
            return TokenInfo.init(
                .ENDMARKER,
                "",
                Position.init(self.line, self.col),
                Position.init(self.line, self.col),
                "",
            );
        }

        const start_pos = Position.init(self.line, self.col);
        const c = self.source[self.pos];

        // Comment
        if (c == '#') {
            const start = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
                self.col += 1;
            }
            return TokenInfo.init(
                .COMMENT,
                self.source[start..self.pos],
                start_pos,
                Position.init(self.line, self.col),
                self.currentLine(),
            );
        }

        // Newline
        if (c == '\n') {
            self.pos += 1;
            self.line += 1;
            self.col = 0;
            self.at_bol = true;
            return TokenInfo.init(
                .NEWLINE,
                "\n",
                start_pos,
                Position.init(self.line, 0),
                self.currentLine(),
            );
        }

        // String
        if (c == '"' or c == '\'') {
            return self.readString(start_pos);
        }

        // Number
        if (std.ascii.isDigit(c)) {
            return self.readNumber(start_pos);
        }

        // Name/Keyword
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.readName(start_pos);
        }

        // Operators
        return self.readOperator(start_pos);
    }

    fn countIndent(self: *Self) u32 {
        var indent: u32 = 0;
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == ' ') {
                indent += 1;
                self.pos += 1;
                self.col += 1;
            } else if (self.source[self.pos] == '\t') {
                indent = (indent + 8) & ~@as(u32, 7);
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }
        return indent;
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }
    }

    fn readString(self: *Self, start_pos: Position) TokenInfo {
        const quote = self.source[self.pos];
        const start = self.pos;
        self.pos += 1;
        self.col += 1;

        // Check for triple quotes
        const triple = if (self.pos + 1 < self.source.len and
            self.source[self.pos] == quote and
            self.source[self.pos + 1] == quote)
        blk: {
            self.pos += 2;
            self.col += 2;
            break :blk true;
        } else false;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2;
                self.col += 2;
            } else if (c == '\n') {
                if (!triple) break;
                self.pos += 1;
                self.line += 1;
                self.col = 0;
            } else if (c == quote) {
                if (triple) {
                    if (self.pos + 2 < self.source.len and
                        self.source[self.pos + 1] == quote and
                        self.source[self.pos + 2] == quote)
                    {
                        self.pos += 3;
                        self.col += 3;
                        break;
                    }
                } else {
                    self.pos += 1;
                    self.col += 1;
                    break;
                }
                self.pos += 1;
                self.col += 1;
            } else {
                self.pos += 1;
                self.col += 1;
            }
        }

        return TokenInfo.init(
            .STRING,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn readNumber(self: *Self, start_pos: Position) TokenInfo {
        const start = self.pos;

        // Handle 0x, 0o, 0b prefixes
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            const next_char = self.source[self.pos + 1];
            if (next_char == 'x' or next_char == 'X' or
                next_char == 'o' or next_char == 'O' or
                next_char == 'b' or next_char == 'B')
            {
                self.pos += 2;
                self.col += 2;
            }
        }

        // Integer or float part
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '.') {
                if (c == '.' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '.') {
                    break; // Ellipsis
                }
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }

        // Exponent
        if (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == 'e' or c == 'E') {
                self.pos += 1;
                self.col += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.pos += 1;
                    self.col += 1;
                }
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.pos += 1;
                    self.col += 1;
                }
            }
        }

        // Complex suffix
        if (self.pos < self.source.len and (self.source[self.pos] == 'j' or self.source[self.pos] == 'J')) {
            self.pos += 1;
            self.col += 1;
        }

        return TokenInfo.init(
            .NUMBER,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn readName(self: *Self, start_pos: Position) TokenInfo {
        const start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }

        return TokenInfo.init(
            .NAME,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn readOperator(self: *Self, start_pos: Position) TokenInfo {
        const start = self.pos;

        // Try 3-char operators
        if (self.pos + 2 < self.source.len) {
            const three = self.source[self.pos .. self.pos + 3];
            if (EXACT_TOKEN_TYPES.get(three)) |_| {
                self.pos += 3;
                self.col += 3;
                return TokenInfo.init(
                    .OP,
                    self.source[start..self.pos],
                    start_pos,
                    Position.init(self.line, self.col),
                    self.currentLine(),
                );
            }
        }

        // Try 2-char operators
        if (self.pos + 1 < self.source.len) {
            const two = self.source[self.pos .. self.pos + 2];
            if (EXACT_TOKEN_TYPES.get(two)) |_| {
                self.pos += 2;
                self.col += 2;
                return TokenInfo.init(
                    .OP,
                    self.source[start..self.pos],
                    start_pos,
                    Position.init(self.line, self.col),
                    self.currentLine(),
                );
            }
        }

        // Single char operator
        self.pos += 1;
        self.col += 1;
        return TokenInfo.init(
            .OP,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn currentLine(self: *Self) []const u8 {
        // Find start of current line
        var line_start = self.pos;
        while (line_start > 0 and self.source[line_start - 1] != '\n') {
            line_start -= 1;
        }

        // Find end of current line
        var line_end = self.pos;
        while (line_end < self.source.len and self.source[line_end] != '\n') {
            line_end += 1;
        }

        return self.source[line_start..line_end];
    }

    /// Reset tokenizer to beginning
    pub fn reset(self: *Self) void {
        self.pos = 0;
        self.line = 1;
        self.col = 0;
        self.at_bol = true;
        self.pending_dedents = 0;
        self.done = false;
        self.indent_stack.clearRetainingCapacity();
        self.indent_stack.append(self.allocator, 0) catch {};
    }
};
