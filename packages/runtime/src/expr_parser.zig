/// Runtime expression parser for eval()
/// Lightweight recursive descent parser for Python expressions
/// Compiles directly to bytecode for fast execution
const std = @import("std");
const bytecode = @import("bytecode.zig");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidNumber,
    UnclosedParen,
    UnclosedString,
    OutOfMemory,
};

/// Token types for expression lexer
const TokenType = enum {
    Number,
    String,
    Plus,
    Minus,
    Star,
    Slash,
    DoubleSlash,
    Percent,
    DoubleStar,
    LParen,
    RParen,
    LBracket,
    RBracket,
    Comma,
    Eq,
    NotEq,
    Lt,
    Gt,
    LtE,
    GtE,
    True,
    False,
    None,
    Name,
    Eof,
};

const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,
};

/// Expression parser that compiles directly to bytecode
pub const ExprParser = struct {
    source: []const u8,
    pos: usize,
    current: Token,
    compiler: bytecode.Compiler,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) ExprParser {
        var parser = ExprParser{
            .source = source,
            .pos = 0,
            .current = undefined,
            .compiler = bytecode.Compiler.init(allocator),
            .allocator = allocator,
        };
        parser.advance() catch {};
        return parser;
    }

    pub fn deinit(self: *ExprParser) void {
        self.compiler.deinit();
    }

    /// Parse expression and return compiled bytecode
    pub fn parse(self: *ExprParser) !bytecode.BytecodeProgram {
        try self.parseExpr();
        try self.compiler.instructions.append(self.allocator, .{ .op = .Return });

        return .{
            .instructions = try self.compiler.instructions.toOwnedSlice(self.allocator),
            .constants = try self.compiler.constants.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    // ========== Lexer ==========

    fn advance(self: *ExprParser) !void {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            self.current = .{ .type = .Eof, .start = self.pos, .end = self.pos };
            return;
        }

        const start = self.pos;
        const c = self.source[self.pos];

        // Single character tokens
        switch (c) {
            '+' => {
                self.pos += 1;
                self.current = .{ .type = .Plus, .start = start, .end = self.pos };
                return;
            },
            '-' => {
                self.pos += 1;
                self.current = .{ .type = .Minus, .start = start, .end = self.pos };
                return;
            },
            '*' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                    self.pos += 2;
                    self.current = .{ .type = .DoubleStar, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    self.current = .{ .type = .Star, .start = start, .end = self.pos };
                }
                return;
            },
            '/' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                    self.pos += 2;
                    self.current = .{ .type = .DoubleSlash, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    self.current = .{ .type = .Slash, .start = start, .end = self.pos };
                }
                return;
            },
            '%' => {
                self.pos += 1;
                self.current = .{ .type = .Percent, .start = start, .end = self.pos };
                return;
            },
            '(' => {
                self.pos += 1;
                self.current = .{ .type = .LParen, .start = start, .end = self.pos };
                return;
            },
            ')' => {
                self.pos += 1;
                self.current = .{ .type = .RParen, .start = start, .end = self.pos };
                return;
            },
            '[' => {
                self.pos += 1;
                self.current = .{ .type = .LBracket, .start = start, .end = self.pos };
                return;
            },
            ']' => {
                self.pos += 1;
                self.current = .{ .type = .RBracket, .start = start, .end = self.pos };
                return;
            },
            ',' => {
                self.pos += 1;
                self.current = .{ .type = .Comma, .start = start, .end = self.pos };
                return;
            },
            '=' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    self.current = .{ .type = .Eq, .start = start, .end = self.pos };
                } else {
                    return ParseError.UnexpectedToken;
                }
                return;
            },
            '!' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    self.current = .{ .type = .NotEq, .start = start, .end = self.pos };
                } else {
                    return ParseError.UnexpectedToken;
                }
                return;
            },
            '<' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    self.current = .{ .type = .LtE, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    self.current = .{ .type = .Lt, .start = start, .end = self.pos };
                }
                return;
            },
            '>' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    self.current = .{ .type = .GtE, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    self.current = .{ .type = .Gt, .start = start, .end = self.pos };
                }
                return;
            },
            '"', '\'' => {
                try self.scanString(c);
                return;
            },
            else => {},
        }

        // Number (including .14 style floats)
        if (std.ascii.isDigit(c) or (c == '.' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))) {
            try self.scanNumber();
            return;
        }

        // Identifier/keyword
        if (std.ascii.isAlphabetic(c) or c == '_') {
            try self.scanIdentifier();
            return;
        }

        return ParseError.UnexpectedToken;
    }

    fn skipWhitespace(self: *ExprParser) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }

    fn scanNumber(self: *ExprParser) !void {
        const start = self.pos;
        // Check for base prefix: 0b, 0o, 0x
        if (self.pos + 1 < self.source.len and self.source[self.pos] == '0') {
            const prefix = self.source[self.pos + 1];
            if (prefix == 'b' or prefix == 'B' or prefix == 'o' or prefix == 'O' or prefix == 'x' or prefix == 'X') {
                self.pos += 2; // Skip "0x" etc.
                // Scan hex/binary/octal digits plus underscores
                while (self.pos < self.source.len) {
                    const c = self.source[self.pos];
                    if (std.ascii.isAlphanumeric(c) or c == '_') {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                self.current = .{ .type = .Number, .start = start, .end = self.pos };
                return;
            }
        }
        // Include digits, underscores (Python 3.6+), decimal point, and scientific notation (e/E)
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isDigit(c) or c == '.' or c == '_') {
                self.pos += 1;
            } else if (c == 'e' or c == 'E') {
                // Scientific notation - include e and optional sign
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
        self.current = .{ .type = .Number, .start = start, .end = self.pos };
    }

    fn scanString(self: *ExprParser, quote: u8) !void {
        const start = self.pos;
        self.pos += 1; // skip opening quote
        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2; // skip escape
            } else {
                self.pos += 1;
            }
        }
        if (self.pos >= self.source.len) return ParseError.UnclosedString;
        self.pos += 1; // skip closing quote
        self.current = .{ .type = .String, .start = start, .end = self.pos };
    }

    fn scanIdentifier(self: *ExprParser) !void {
        const start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        const text = self.source[start..self.pos];

        // Check keywords
        const tok_type: TokenType = if (std.mem.eql(u8, text, "True"))
            .True
        else if (std.mem.eql(u8, text, "False"))
            .False
        else if (std.mem.eql(u8, text, "None"))
            .None
        else
            .Name;

        self.current = .{ .type = tok_type, .start = start, .end = self.pos };
    }

    fn getText(self: *ExprParser, token: Token) []const u8 {
        return self.source[token.start..token.end];
    }

    // ========== Parser (Pratt-style precedence climbing) ==========

    fn parseExpr(self: *ExprParser) ParseError!void {
        try self.parseComparison();
    }

    fn parseComparison(self: *ExprParser) ParseError!void {
        try self.parseAddSub();

        while (self.current.type == .Eq or self.current.type == .NotEq or
            self.current.type == .Lt or self.current.type == .Gt or
            self.current.type == .LtE or self.current.type == .GtE)
        {
            const op = self.current.type;
            try self.advance();
            try self.parseAddSub();

            const bc_op: bytecode.OpCode = switch (op) {
                .Eq => .Eq,
                .NotEq => .NotEq,
                .Lt => .Lt,
                .Gt => .Gt,
                .LtE => .LtE,
                .GtE => .GtE,
                else => unreachable,
            };
            self.compiler.instructions.append(self.allocator, .{ .op = bc_op }) catch return ParseError.OutOfMemory;
        }
    }

    fn parseAddSub(self: *ExprParser) ParseError!void {
        try self.parseMulDiv();

        while (self.current.type == .Plus or self.current.type == .Minus) {
            const op = self.current.type;
            try self.advance();
            try self.parseMulDiv();

            const bc_op: bytecode.OpCode = if (op == .Plus) .Add else .Sub;
            self.compiler.instructions.append(self.allocator, .{ .op = bc_op }) catch return ParseError.OutOfMemory;
        }
    }

    fn parseMulDiv(self: *ExprParser) ParseError!void {
        try self.parsePower();

        while (self.current.type == .Star or self.current.type == .Slash or
            self.current.type == .DoubleSlash or self.current.type == .Percent)
        {
            const op = self.current.type;
            try self.advance();
            try self.parsePower();

            const bc_op: bytecode.OpCode = switch (op) {
                .Star => .Mult,
                .Slash => .Div,
                .DoubleSlash => .FloorDiv,
                .Percent => .Mod,
                else => unreachable,
            };
            self.compiler.instructions.append(self.allocator, .{ .op = bc_op }) catch return ParseError.OutOfMemory;
        }
    }

    fn parsePower(self: *ExprParser) ParseError!void {
        try self.parseUnary();

        if (self.current.type == .DoubleStar) {
            try self.advance();
            try self.parsePower(); // Right associative
            self.compiler.instructions.append(self.allocator, .{ .op = .Pow }) catch return ParseError.OutOfMemory;
        }
    }

    fn parseUnary(self: *ExprParser) ParseError!void {
        if (self.current.type == .Minus) {
            try self.advance();
            try self.parseUnary();
            // Negate: 0 - value
            const zero_idx = @as(u32, @intCast(self.compiler.constants.items.len));
            self.compiler.constants.append(self.allocator, .{ .int = 0 }) catch return ParseError.OutOfMemory;
            // Insert LoadConst 0 before the value (swap stack positions)
            // Actually for unary minus we need: push 0, then value is on stack, then Sub
            // But value already on stack from recursive call, so we need different approach
            // Simpler: multiply by -1
            const neg_idx = @as(u32, @intCast(self.compiler.constants.items.len));
            self.compiler.constants.append(self.allocator, .{ .int = -1 }) catch return ParseError.OutOfMemory;
            self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = neg_idx }) catch return ParseError.OutOfMemory;
            self.compiler.instructions.append(self.allocator, .{ .op = .Mult }) catch return ParseError.OutOfMemory;
            _ = zero_idx;
            return;
        }

        if (self.current.type == .Plus) {
            try self.advance();
            try self.parseUnary();
            return; // +x is just x
        }

        try self.parsePrimary();
    }

    fn parsePrimary(self: *ExprParser) ParseError!void {
        switch (self.current.type) {
            .Number => {
                const text = self.getText(self.current);
                // Determine base from prefix and strip it
                var base: u8 = 10;
                var num_text = text;
                if (text.len > 2 and text[0] == '0') {
                    const prefix = text[1];
                    if (prefix == 'b' or prefix == 'B') {
                        base = 2;
                        num_text = text[2..];
                    } else if (prefix == 'o' or prefix == 'O') {
                        base = 8;
                        num_text = text[2..];
                    } else if (prefix == 'x' or prefix == 'X') {
                        base = 16;
                        num_text = text[2..];
                    }
                }
                // Strip underscores from numeric literals (Python 3.6+)
                const clean = stripUnderscores(num_text) catch return ParseError.OutOfMemory;
                const value = std.fmt.parseInt(i64, clean, base) catch {
                    if (base != 10) return ParseError.InvalidNumber;
                    // Try float (only for base 10)
                    const fval = std.fmt.parseFloat(f64, clean) catch return ParseError.InvalidNumber;
                    // Emit float constant
                    const const_idx = @as(u32, @intCast(self.compiler.constants.items.len));
                    self.compiler.constants.append(self.allocator, .{ .float = fval }) catch return ParseError.OutOfMemory;
                    self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                    try self.advance();
                    return;
                };
                const const_idx = @as(u32, @intCast(self.compiler.constants.items.len));
                self.compiler.constants.append(self.allocator, .{ .int = value }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .String => {
                const text = self.getText(self.current);
                // Strip quotes
                const str = text[1 .. text.len - 1];
                const const_idx = @as(u32, @intCast(self.compiler.constants.items.len));
                self.compiler.constants.append(self.allocator, .{ .string = str }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .True => {
                const const_idx = @as(u32, @intCast(self.compiler.constants.items.len));
                self.compiler.constants.append(self.allocator, .{ .int = 1 }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .False => {
                const const_idx = @as(u32, @intCast(self.compiler.constants.items.len));
                self.compiler.constants.append(self.allocator, .{ .int = 0 }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .LParen => {
                try self.advance(); // skip (
                try self.parseExpr();
                if (self.current.type != .RParen) return ParseError.UnclosedParen;
                try self.advance(); // skip )
            },
            .LBracket => {
                // List literal - parse elements and emit BUILD_LIST
                try self.advance();
                var count: u32 = 0;
                while (self.current.type != .RBracket and self.current.type != .Eof) {
                    try self.parseExpr();
                    count += 1;
                    if (self.current.type == .Comma) {
                        try self.advance();
                    }
                }
                if (self.current.type != .RBracket) return ParseError.UnclosedParen;
                try self.advance();
                // Emit BUILD_LIST with count (uses Call opcode for now)
                self.compiler.instructions.append(self.allocator, .{ .op = .Call, .arg = count }) catch return ParseError.OutOfMemory;
            },
            else => return ParseError.UnexpectedToken,
        }
    }
};

/// Strip underscores from numeric literal (Python 3.6+ feature)
/// Uses a static buffer to avoid allocation and lifetime issues
var strip_buf: [64]u8 = undefined;

fn stripUnderscores(input: []const u8) error{OutOfMemory}![]const u8 {
    // Fast path: no underscores
    if (std.mem.indexOfScalar(u8, input, '_') == null) {
        return input;
    }
    // Use static buffer for small numbers
    var len: usize = 0;
    for (input) |c| {
        if (c != '_') {
            if (len >= strip_buf.len) return error.OutOfMemory; // Number too large for buffer
            strip_buf[len] = c;
            len += 1;
        }
    }
    // Handle case where result is empty (e.g., just "_")
    if (len == 0) return error.OutOfMemory;
    return strip_buf[0..len];
}

/// Parse and compile expression to bytecode
pub fn parseExpression(allocator: std.mem.Allocator, source: []const u8) !bytecode.BytecodeProgram {
    var parser = ExprParser.init(allocator, source);
    defer parser.deinit();
    return parser.parse();
}

// Tests
test "parse simple integer" {
    const allocator = std.testing.allocator;
    var program = try parseExpression(allocator, "42");
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 2), program.instructions.len);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[0].op);
    try std.testing.expectEqual(bytecode.OpCode.Return, program.instructions[1].op);
    try std.testing.expectEqual(@as(i64, 42), program.constants[0].int);
}

test "parse addition" {
    const allocator = std.testing.allocator;
    var program = try parseExpression(allocator, "1 + 2");
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 4), program.instructions.len);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[0].op);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[1].op);
    try std.testing.expectEqual(bytecode.OpCode.Add, program.instructions[2].op);
    try std.testing.expectEqual(bytecode.OpCode.Return, program.instructions[3].op);
}

test "parse precedence" {
    const allocator = std.testing.allocator;
    var program = try parseExpression(allocator, "1 + 2 * 3");
    defer program.deinit();

    // Should be: LOAD 1, LOAD 2, LOAD 3, MUL, ADD, RET
    try std.testing.expectEqual(@as(usize, 6), program.instructions.len);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[0].op);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[1].op);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[2].op);
    try std.testing.expectEqual(bytecode.OpCode.Mult, program.instructions[3].op);
    try std.testing.expectEqual(bytecode.OpCode.Add, program.instructions[4].op);
}
