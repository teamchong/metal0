const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast");
const literals = @import("parser/literals.zig");
const expressions = @import("parser/expressions.zig");
const postfix = @import("parser/postfix.zig");
const statements = @import("parser/statements.zig");

pub const ParseError = error{
    UnexpectedEof,
    UnexpectedToken,
    UnexpectedCharacter,
    OutOfMemory,
    InvalidCharacter,
    Overflow,
};

pub const Parser = struct {
    tokens: []const lexer.Token,
    current: usize,
    allocator: std.mem.Allocator,
    function_depth: usize = 0,
    is_first_statement: bool = true,
    /// Track strings allocated during parsing (e.g., string concatenation)
    /// These need to be freed separately since they're not token lexemes
    allocated_strings: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, tokens: []const lexer.Token) Parser {
        return Parser{
            .tokens = tokens,
            .current = 0,
            .allocator = allocator,
            .function_depth = 0,
            .is_first_statement = true,
            .allocated_strings = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *Parser) void {
        for (self.allocated_strings.items) |str| {
            self.allocator.free(str);
        }
        self.allocated_strings.deinit(self.allocator);
    }

    pub fn parse(self: *Parser) ParseError!ast.Node {
        var stmts = std.ArrayList(ast.Node){};
        errdefer {
            // On error, clean up any statements we've already parsed
            for (stmts.items) |*stmt| {
                stmt.deinit(self.allocator);
            }
            stmts.deinit(self.allocator);
        }

        // Skip leading newlines
        while (self.match(.Newline)) {}

        while (!self.isAtEnd()) {
            if (self.match(.Newline)) continue;
            const stmt = try self.parseStatement();
            try stmts.append(self.allocator, stmt);
            self.is_first_statement = false;
        }

        // Success path - transfer ownership, don't clean up
        const body = try stmts.toOwnedSlice(self.allocator);
        stmts = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
        return ast.Node{
            .module = .{
                .body = body,
            },
        };
    }

    // ===== Utility Methods =====

    pub fn peek(self: *Parser) ?lexer.Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }

    fn peekType(self: *Parser) ?lexer.TokenType {
        if (self.peek()) |tok| return tok.type;
        return null;
    }

    pub fn advance(self: *Parser) ?lexer.Token {
        if (self.current >= self.tokens.len) return null;
        const tok = self.tokens[self.current];
        self.current += 1;
        return tok;
    }

    pub fn expect(self: *Parser, token_type: lexer.TokenType) !lexer.Token {
        const tok = self.peek() orelse return error.UnexpectedEof;
        if (tok.type != token_type) {
            std.debug.print("Expected {s}, got {s} at line {d}:{d}\n", .{
                @tagName(token_type),
                @tagName(tok.type),
                tok.line,
                tok.column,
            });
            return error.UnexpectedToken;
        }
        return self.advance().?;
    }

    pub fn match(self: *Parser, token_type: lexer.TokenType) bool {
        if (self.peek()) |tok| {
            if (tok.type == token_type) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    pub fn check(self: *Parser, token_type: lexer.TokenType) bool {
        if (self.peek()) |tok| {
            return tok.type == token_type;
        }
        return false;
    }

    fn matchAny(self: *Parser, types: []const lexer.TokenType) bool {
        for (types) |t| {
            if (self.match(t)) return true;
        }
        return false;
    }

    fn isAtEnd(self: *Parser) bool {
        if (self.peek()) |tok| {
            return tok.type == .Eof;
        }
        return true;
    }

    pub fn skipNewlines(self: *Parser) void {
        while (self.match(.Newline)) {}
    }

    // ===== Parser Helpers =====

    /// Allocate a node on the heap and copy value into it.
    /// On allocation failure, cleans up the source value and returns error.
    pub fn allocNode(self: *Parser, value: ast.Node) error{OutOfMemory}!*ast.Node {
        const ptr = try self.allocator.create(ast.Node);
        ptr.* = value;
        return ptr;
    }

    /// Allocate a node on the heap, cleaning up source value on failure.
    /// Returns null if value is null.
    pub fn allocNodeOpt(self: *Parser, value: ?ast.Node) error{OutOfMemory}!?*ast.Node {
        if (value) |v| {
            const ptr = try self.allocator.create(ast.Node);
            ptr.* = v;
            return ptr;
        }
        return null;
    }

    /// Token-to-operator mapping for binary expression parsing
    pub const OpMapping = struct {
        token: lexer.TokenType,
        op: ast.Operator,
    };

    /// Generic binary operator parser - left-associative
    /// Reduces repetitive binop parsing code by ~150 lines
    pub fn parseBinOp(
        self: *Parser,
        comptime next_parser: fn (*Parser) ParseError!ast.Node,
        comptime mappings: []const OpMapping,
    ) ParseError!ast.Node {
        var left = try next_parser(self);
        errdefer left.deinit(self.allocator);

        while (true) {
            var op: ?ast.Operator = null;
            inline for (mappings) |m| {
                if (self.match(m.token)) {
                    op = m.op;
                    break;
                }
            }
            if (op == null) break;

            var right = try next_parser(self);
            errdefer right.deinit(self.allocator);

            const left_ptr = try self.allocNode(left);
            const right_ptr = try self.allocNode(right);

            left = ast.Node{ .binop = .{ .left = left_ptr, .op = op.?, .right = right_ptr } };
        }
        return left;
    }

    // ===== Statement Parsing =====

    pub fn parseStatement(self: *Parser) ParseError!ast.Node {
        // Try to determine statement type
        if (self.peek()) |tok| {
            switch (tok.type) {
                .At => return try statements.parseDecorated(self),
                .Async => return try statements.parseFunctionDef(self),
                .Def => return try statements.parseFunctionDef(self),
                .Class => return try statements.parseClassDef(self),
                .If => return try statements.parseIf(self),
                .For => return try statements.parseFor(self),
                .While => return try statements.parseWhile(self),
                .Return => return try statements.parseReturn(self),
                .Import => return try statements.parseImport(self),
                .From => return try statements.parseImportFrom(self),
                .Assert => return try statements.parseAssert(self),
                .Try => return try statements.parseTry(self),
                .Raise => return try statements.parseRaise(self),
                .Pass => return try statements.parsePass(self),
                .Break => return try statements.parseBreak(self),
                .Continue => return try statements.parseContinue(self),
                .Global => return try statements.parseGlobal(self),
                .Nonlocal => return try statements.parseNonlocal(self),
                .With => return try statements.parseWith(self),
                .Del => return try statements.parseDel(self),
                .Ellipsis => return try statements.parseEllipsis(self),
                .Yield => return try statements.parseYield(self),
                else => {
                    // Could be assignment or expression statement
                    return try statements.parseExprOrAssign(self);
                },
            }
        }
        return error.UnexpectedEof;
    }

    // ===== Expression Parsing =====

    pub fn parseExpression(self: *Parser) ParseError!ast.Node {
        return try expressions.parseConditionalExpr(self);
    }

    /// Parse expression without conditional (for list comprehension iter/condition)
    /// Stops at 'if' keyword so comprehension can handle it
    pub fn parseOrExpr(self: *Parser) ParseError!ast.Node {
        return try expressions.parseOrExpr(self);
    }

    pub fn parsePostfix(self: *Parser) ParseError!ast.Node {
        return try postfix.parsePostfix(self);
    }

    pub fn parsePrimary(self: *Parser) ParseError!ast.Node {
        return try postfix.parsePrimary(self);
    }
};
