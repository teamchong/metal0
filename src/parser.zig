const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
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

    pub fn init(allocator: std.mem.Allocator, tokens: []const lexer.Token) Parser {
        return Parser{
            .tokens = tokens,
            .current = 0,
            .allocator = allocator,
            .function_depth = 0,
            .is_first_statement = true,
        };
    }

    pub fn parse(self: *Parser) ParseError!ast.Node {
        var stmts = std.ArrayList(ast.Node){};
        defer stmts.deinit(self.allocator);

        // Skip leading newlines
        while (self.match(.Newline)) {}

        while (!self.isAtEnd()) {
            if (self.match(.Newline)) continue;
            const stmt = try self.parseStatement();
            try stmts.append(self.allocator, stmt);
            self.is_first_statement = false;
        }

        return ast.Node{
            .module = .{
                .body = try stmts.toOwnedSlice(self.allocator),
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
                .With => return try statements.parseWith(self),
                .Del => return try statements.parseDel(self),
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
        return try expressions.parseOrExpr(self);
    }

    pub fn parsePostfix(self: *Parser) ParseError!ast.Node {
        return try postfix.parsePostfix(self);
    }

    pub fn parsePrimary(self: *Parser) ParseError!ast.Node {
        return try postfix.parsePrimary(self);
    }
};
