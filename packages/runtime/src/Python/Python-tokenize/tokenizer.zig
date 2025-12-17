/// Tokenizer State and Main Logic
/// Core tokenizer implementation with indentation tracking

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const helpers = @import("helpers.zig");
const string_reader = @import("string_reader.zig");
const number_reader = @import("number_reader.zig");
const operator_reader = @import("operator_reader.zig");

pub const Token = types.Token;
pub const Position = types.Position;
pub const TokenType = types.TokenType;

// ============================================================================
// Tokenizer State
// ============================================================================

/// Tokenizer state
pub const Tokenizer = struct {
    const Self = @This();

    allocator: Allocator,
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    col: u32 = 0,
    /// Indentation stack
    indent_stack: std.ArrayList(u32),
    /// Pending dedents to emit
    pending_dedents: u32 = 0,
    /// Bracket nesting level
    bracket_level: u32 = 0,
    /// At beginning of line
    at_bol: bool = true,
    /// In f-string
    in_fstring: bool = false,
    /// Error message if any
    error_msg: ?[]const u8 = null,

    pub fn init(allocator: Allocator, source: []const u8) Self {
        var self = Self{
            .allocator = allocator,
            .source = source,
            .indent_stack = std.ArrayList(u32).init(allocator),
        };
        // Start with 0 indentation
        self.indent_stack.append(0) catch unreachable;
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.indent_stack.deinit();
    }

    /// Get next token
    pub fn nextToken(self: *Self) !Token {
        // Emit pending dedents
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return Token{
                .type_ = .DEDENT,
                .start = self.currentPos(),
                .end = self.currentPos(),
                .string = "",
            };
        }

        // Skip whitespace and handle indentation at BOL
        if (self.at_bol and self.bracket_level == 0) {
            try self.handleIndentation();
            if (self.pending_dedents > 0) {
                self.pending_dedents -= 1;
                return Token{
                    .type_ = .DEDENT,
                    .start = self.currentPos(),
                    .end = self.currentPos(),
                    .string = "",
                };
            }
        }

        // Skip spaces (not at BOL)
        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
            self.advance();
        }

        // End of input
        if (self.pos >= self.source.len) {
            // Emit final dedents
            if (self.indent_stack.items.len > 1) {
                _ = self.indent_stack.pop();
                self.pending_dedents = @intCast(self.indent_stack.items.len - 1);
                if (self.pending_dedents > 0) {
                    self.pending_dedents -= 1;
                    return Token{
                        .type_ = .DEDENT,
                        .start = self.currentPos(),
                        .end = self.currentPos(),
                        .string = "",
                    };
                }
            }
            return Token{
                .type_ = .ENDMARKER,
                .start = self.currentPos(),
                .end = self.currentPos(),
                .string = "",
            };
        }

        const start = self.currentPos();
        const c = self.source[self.pos];

        // Comment
        if (c == '#') {
            const comment_start = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.advance();
            }
            return Token{
                .type_ = .COMMENT,
                .start = start,
                .end = self.currentPos(),
                .string = self.source[comment_start..self.pos],
            };
        }

        // Newline
        if (c == '\n') {
            self.advance();
            self.at_bol = true;
            if (self.bracket_level > 0) {
                return Token{
                    .type_ = .NL,
                    .start = start,
                    .end = self.currentPos(),
                    .string = "\n",
                };
            }
            return Token{
                .type_ = .NEWLINE,
                .start = start,
                .end = self.currentPos(),
                .string = "\n",
            };
        }

        self.at_bol = false;

        // String
        if (c == '"' or c == '\'') {
            return string_reader.readString(self.source, &self.pos, &self.line, &self.col, start);
        }

        // String with prefix
        if (helpers.isStringPrefix(c)) {
            return string_reader.readPrefixedString(self.source, &self.pos, &self.line, &self.col, start);
        }

        // Number
        if (std.ascii.isDigit(c)) {
            return number_reader.readNumber(self.source, &self.pos, &self.line, &self.col, start);
        }

        // Name/keyword
        if (helpers.isIdentStart(c)) {
            return self.readName(start);
        }

        // Operators and delimiters
        return operator_reader.readOperator(self.source, &self.pos, &self.line, &self.col, start, &self.bracket_level);
    }

    fn currentPos(self: *const Self) Position {
        return Position{
            .line = self.line,
            .column = self.col,
            .offset = self.pos,
        };
    }

    fn advance(self: *Self) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.col = 0;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
    }

    fn handleIndentation(self: *Self) !void {
        var indent: u32 = 0;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ') {
                indent += 1;
                self.advance();
            } else if (c == '\t') {
                indent = (indent + 8) & ~@as(u32, 7);
                self.advance();
            } else {
                break;
            }
        }

        // Skip blank lines and comments
        if (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\n' or c == '#') {
                return;
            }
        }

        self.at_bol = false;

        const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];

        if (indent > current_indent) {
            try self.indent_stack.append(indent);
            // Will return INDENT token
        } else if (indent < current_indent) {
            // Calculate dedents
            while (self.indent_stack.items.len > 1) {
                const top = self.indent_stack.items[self.indent_stack.items.len - 1];
                if (indent >= top) break;
                _ = self.indent_stack.pop();
                self.pending_dedents += 1;
            }
        }
    }

    fn readName(self: *Self, start: Position) Token {
        const name_start = self.pos;
        while (self.pos < self.source.len and helpers.isIdentContinue(self.source[self.pos])) {
            self.advance();
        }
        const name = self.source[name_start..self.pos];

        // Check for async/await
        if (std.mem.eql(u8, name, "async")) {
            return Token{ .type_ = .ASYNC, .start = start, .end = self.currentPos(), .string = name };
        }
        if (std.mem.eql(u8, name, "await")) {
            return Token{ .type_ = .AWAIT, .start = start, .end = self.currentPos(), .string = name };
        }

        return Token{
            .type_ = .NAME,
            .start = start,
            .end = self.currentPos(),
            .string = name,
        };
    }
};
