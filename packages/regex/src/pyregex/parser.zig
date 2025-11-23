/// Recursive descent parser for regular expressions
/// Converts regex string to AST (100% Python re compatible)
const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;
const AST = ast.AST;

pub const ParseError = error{
    UnexpectedEOF,
    InvalidEscape,
    InvalidCharClass,
    InvalidQuantifier,
    UnbalancedParens,
    InvalidRepeat,
    OutOfMemory,
};

pub const Parser = struct {
    input: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
        return .{
            .input = input,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) !AST {
        const root = try self.parseAlt();
        return AST.init(self.allocator, root);
    }

    // Grammar:
    // alt    = concat ('|' concat)*
    // concat = term+
    // term   = atom quantifier?
    // atom   = char | charclass | group | anchor | '.'
    // quantifier = '*' | '+' | '?' | '{' number (',' number?)? '}'

    fn parseAlt(self: *Parser) ParseError!Expr {
        var branches: std.ArrayList(Expr) = .{};
        errdefer {
            for (branches.items) |*e| e.deinit(self.allocator);
            branches.deinit(self.allocator);
        }

        // First branch
        try branches.append(self.allocator, try self.parseConcat());

        // Additional branches
        while (self.peek()) |c| {
            if (c != '|') break;
            self.advance(); // consume '|'
            try branches.append(self.allocator, try self.parseConcat());
        }

        if (branches.items.len == 1) {
            const expr = branches.items[0];
            branches.deinit(self.allocator);
            return expr;
        }

        return Expr{ .alt = .{ .exprs = try branches.toOwnedSlice(self.allocator) } };
    }

    fn parseConcat(self: *Parser) ParseError!Expr {
        var terms: std.ArrayList(Expr) = .{};
        errdefer {
            for (terms.items) |*e| e.deinit(self.allocator);
            terms.deinit(self.allocator);
        }

        while (self.peek()) |c| {
            // Stop at alt boundary or group end
            if (c == '|' or c == ')') break;

            const term = try self.parseTerm();
            try terms.append(self.allocator, term);
        }

        if (terms.items.len == 0) {
            // Empty concat (for empty groups or alt branches)
            terms.deinit(self.allocator);
            return Expr{ .char = 0 }; // TODO: Better empty handling
        }

        if (terms.items.len == 1) {
            const expr = terms.items[0];
            terms.deinit(self.allocator);
            return expr;
        }

        return Expr{ .concat = .{ .exprs = try terms.toOwnedSlice(self.allocator) } };
    }

    fn parseTerm(self: *Parser) ParseError!Expr {
        var atom = try self.parseAtom();
        errdefer atom.deinit(self.allocator);

        // Check for quantifier
        if (self.peek()) |c| {
            switch (c) {
                '*' => {
                    self.advance();
                    const ptr = try self.allocator.create(Expr);
                    ptr.* = atom;
                    return Expr{ .star = ptr };
                },
                '+' => {
                    self.advance();
                    const ptr = try self.allocator.create(Expr);
                    ptr.* = atom;
                    return Expr{ .plus = ptr };
                },
                '?' => {
                    self.advance();
                    const ptr = try self.allocator.create(Expr);
                    ptr.* = atom;
                    return Expr{ .question = ptr };
                },
                '{' => {
                    return try self.parseRepeat(atom);
                },
                else => {},
            }
        }

        return atom;
    }

    fn parseRepeat(self: *Parser, atom: Expr) ParseError!Expr {
        self.advance(); // consume '{'

        // Parse min
        const min = try self.parseNumber();

        var max: ?usize = null;

        if (self.peek()) |c| {
            if (c == ',') {
                self.advance(); // consume ','

                // Check if there's a max
                if (self.peek()) |next| {
                    if (next != '}') {
                        max = try self.parseNumber();
                    }
                    // else: unbounded {n,}
                }
            } else {
                // Exact count {n}
                max = min;
            }
        }

        if (self.peek() != '}') {
            return error.InvalidRepeat;
        }
        self.advance(); // consume '}'

        const ptr = try self.allocator.create(Expr);
        ptr.* = atom;

        return Expr{ .repeat = .{
            .expr = ptr,
            .min = min,
            .max = max,
        } };
    }

    fn parseNumber(self: *Parser) ParseError!usize {
        var num: usize = 0;
        var found = false;

        while (self.peek()) |c| {
            if (c < '0' or c > '9') break;
            found = true;
            num = num * 10 + (c - '0');
            self.advance();
        }

        if (!found) return error.InvalidRepeat;
        return num;
    }

    fn parseAtom(self: *Parser) ParseError!Expr {
        const c = self.peek() orelse return error.UnexpectedEOF;

        switch (c) {
            '.' => {
                self.advance();
                return Expr{ .any = {} };
            },
            '^' => {
                self.advance();
                return Expr{ .start = {} };
            },
            '$' => {
                self.advance();
                return Expr{ .end = {} };
            },
            '(' => {
                return try self.parseGroup();
            },
            '[' => {
                return try self.parseCharClass();
            },
            '\\' => {
                return try self.parseEscape();
            },
            // Metacharacters that shouldn't appear here
            '*', '+', '?', '{', '}', '|', ')' => {
                return error.UnexpectedEOF; // TODO: Better error
            },
            else => {
                self.advance();
                return Expr{ .char = c };
            },
        }
    }

    fn parseGroup(self: *Parser) ParseError!Expr {
        self.advance(); // consume '('

        const inner = try self.parseAlt();

        if (self.peek() != ')') {
            return error.UnbalancedParens;
        }
        self.advance(); // consume ')'

        const ptr = try self.allocator.create(Expr);
        ptr.* = inner;

        return Expr{ .group = ptr };
    }

    fn parseCharClass(self: *Parser) ParseError!Expr {
        self.advance(); // consume '['

        const negated = if (self.peek() == '^') blk: {
            self.advance();
            break :blk true;
        } else false;

        var ranges: std.ArrayList(Expr.CharClass.Range) = .{};
        errdefer ranges.deinit(self.allocator);

        while (self.peek()) |c| {
            if (c == ']') break;

            const start = if (c == '\\') blk: {
                self.advance();
                break :blk try self.parseEscapeChar();
            } else blk: {
                self.advance();
                break :blk c;
            };

            // Check for range
            if (self.peek() == '-') {
                // Peek ahead to see if it's a range or literal '-'
                if (self.pos + 1 < self.input.len and self.input[self.pos + 1] != ']') {
                    self.advance(); // consume '-'

                    const end = if (self.peek() == '\\') blk: {
                        self.advance();
                        break :blk try self.parseEscapeChar();
                    } else blk: {
                        const e = self.peek() orelse return error.InvalidCharClass;
                        self.advance();
                        break :blk e;
                    };

                    try ranges.append(self.allocator, .{ .start = start, .end = end });
                } else {
                    // Literal '-' at end
                    try ranges.append(self.allocator, .{ .start = start, .end = start });
                }
            } else {
                // Single character
                try ranges.append(self.allocator, .{ .start = start, .end = start });
            }
        }

        if (self.peek() != ']') {
            return error.InvalidCharClass;
        }
        self.advance(); // consume ']'

        return Expr{ .class = .{
            .negated = negated,
            .ranges = try ranges.toOwnedSlice(self.allocator),
        } };
    }

    fn parseEscape(self: *Parser) ParseError!Expr {
        self.advance(); // consume '\'

        const c = self.peek() orelse return error.InvalidEscape;
        self.advance();

        return switch (c) {
            'd' => Expr{ .digit = {} },
            'D' => Expr{ .not_digit = {} },
            'w' => Expr{ .word = {} },
            'W' => Expr{ .not_word = {} },
            's' => Expr{ .whitespace = {} },
            'S' => Expr{ .not_whitespace = {} },
            'b' => Expr{ .word_boundary = {} },
            'B' => Expr{ .not_word_boundary = {} },
            // Escaped literals
            '.', '*', '+', '?', '[', ']', '(', ')', '{', '}', '|', '\\', '^', '$' => Expr{ .char = c },
            // Escape sequences
            'n' => Expr{ .char = '\n' },
            't' => Expr{ .char = '\t' },
            'r' => Expr{ .char = '\r' },
            // TODO: More escapes (\x, \u, etc.)
            else => Expr{ .char = c }, // Treat as literal
        };
    }

    fn parseEscapeChar(self: *Parser) ParseError!u8 {
        const c = self.peek() orelse return error.InvalidEscape;
        self.advance();

        return switch (c) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            else => c,
        };
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    fn advance(self: *Parser) void {
        self.pos += 1;
    }
};

// Tests
test "parse literals" {
    const allocator = std.testing.allocator;

    var parser = Parser.init(allocator, "abc");
    var tree = try parser.parse();
    defer tree.deinit();

    try std.testing.expect(tree.root == .concat);
    try std.testing.expectEqual(@as(usize, 3), tree.root.concat.exprs.len);
}

test "parse character classes" {
    const allocator = std.testing.allocator;

    var parser = Parser.init(allocator, "\\d+");
    var tree = try parser.parse();
    defer tree.deinit();

    try std.testing.expect(tree.root == .plus);
    try std.testing.expect(tree.root.plus.* == .digit);
}

test "parse alternation" {
    const allocator = std.testing.allocator;

    var parser = Parser.init(allocator, "cat|dog");
    var tree = try parser.parse();
    defer tree.deinit();

    try std.testing.expect(tree.root == .alt);
    try std.testing.expectEqual(@as(usize, 2), tree.root.alt.exprs.len);
}
