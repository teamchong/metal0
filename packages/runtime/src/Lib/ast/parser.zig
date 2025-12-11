//! Python Runtime Parser
//! Parses tokens into AST nodes.

const std = @import("std");
const nodes = @import("nodes.zig");
const tokenizer = @import("tokenizer.zig");

const Token = tokenizer.Token;
const TokenType = tokenizer.TokenType;
const Tokenizer = tokenizer.Tokenizer;

// Re-export node types for convenience
const Module = nodes.Module;
const Statement = nodes.Statement;
const Expr = nodes.Expr;
const Arguments = nodes.Arguments;
const Arg = nodes.Arg;
const Alias = nodes.Alias;
const Keyword = nodes.Keyword;
const TypeParam = nodes.TypeParam;
const Operator = nodes.Operator;
const CmpOp = nodes.CmpOp;
const ConstantValue = nodes.ConstantValue;
const CodeObject = nodes.CodeObject;

pub const RuntimeParser = struct {
    tokens: []Token,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []Token) RuntimeParser {
        return .{ .tokens = tokens, .pos = 0, .allocator = allocator };
    }

    fn peek(self: *RuntimeParser) ?Token {
        if (self.pos >= self.tokens.len) return null;
        return self.tokens[self.pos];
    }

    fn advance(self: *RuntimeParser) ?Token {
        if (self.pos >= self.tokens.len) return null;
        const tok = self.tokens[self.pos];
        self.pos += 1;
        return tok;
    }

    fn match(self: *RuntimeParser, expected: TokenType) bool {
        if (self.peek()) |tok| {
            if (tok.type == expected) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    pub fn parseModule(self: *RuntimeParser) !*Module {
        var statements = std.ArrayList(Statement).init(self.allocator);

        while (self.peek()) |tok| {
            if (tok.type == .Eof) break;
            if (tok.type == .Newline) {
                _ = self.advance();
                continue;
            }
            const stmt = try self.parseStatement();
            try statements.append(stmt);
        }

        const module = try self.allocator.create(Module);
        module.* = .{
            .body = try statements.toOwnedSlice(),
            .type_ignores = &[_]nodes.TypeIgnore{},
        };
        return module;
    }

    fn parseStatement(self: *RuntimeParser) !Statement {
        const tok = self.peek() orelse return error.UnexpectedEof;

        return switch (tok.type) {
            .KwPass => {
                _ = self.advance();
                return .{ .pass_stmt = .{} };
            },
            .KwBreak => {
                _ = self.advance();
                return .{ .break_stmt = .{} };
            },
            .KwContinue => {
                _ = self.advance();
                return .{ .continue_stmt = .{} };
            },
            .KwReturn => try self.parseReturn(),
            .KwImport => try self.parseImport(),
            .KwDef => try self.parseFunctionDef(),
            .KwClass => try self.parseClassDef(),
            .KwIf => try self.parseIf(),
            .KwFor => try self.parseFor(),
            .KwWhile => try self.parseWhile(),
            else => try self.parseExprStatement(),
        };
    }

    fn parseReturn(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'return'
        var value: ?Expr = null;
        if (self.peek()) |tok| {
            if (tok.type != .Newline and tok.type != .Eof) {
                value = try self.parseExpr();
            }
        }
        return .{ .return_stmt = .{ .value = value } };
    }

    fn parseImport(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'import'
        var names = std.ArrayList(Alias).init(self.allocator);

        while (true) {
            const name_tok = self.advance() orelse return error.UnexpectedEof;
            if (name_tok.type != .Name) return error.UnexpectedToken;

            var asname: ?[]const u8 = null;
            if (self.match(.KwAs)) {
                const as_tok = self.advance() orelse return error.UnexpectedEof;
                if (as_tok.type != .Name) return error.UnexpectedToken;
                asname = as_tok.lexeme;
            }

            try names.append(.{ .name = name_tok.lexeme, .asname = asname });

            if (!self.match(.Comma)) break;
        }

        return .{ .import_stmt = .{ .names = try names.toOwnedSlice() } };
    }

    fn parseFunctionDef(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'def'
        const name_tok = self.advance() orelse return error.UnexpectedEof;
        if (name_tok.type != .Name) return error.UnexpectedToken;

        if (!self.match(.LeftParen)) return error.UnexpectedToken;
        const args = try self.parseArguments();
        if (!self.match(.RightParen)) return error.UnexpectedToken;

        var returns: ?Expr = null;
        if (self.match(.Arrow)) {
            returns = try self.parseExpr();
        }

        if (!self.match(.Colon)) return error.UnexpectedToken;

        const body = try self.parseBlock();

        return .{
            .function_def = .{
                .name = name_tok.lexeme,
                .args = args,
                .body = body,
                .decorator_list = &[_]Expr{},
                .returns = returns,
                .type_comment = null,
                .type_params = &[_]TypeParam{},
            },
        };
    }

    fn parseArguments(self: *RuntimeParser) !Arguments {
        var args_list = std.ArrayList(Arg).init(self.allocator);

        while (self.peek()) |tok| {
            if (tok.type == .RightParen) break;
            if (tok.type != .Name) break;

            const arg_tok = self.advance().?;
            var annotation: ?Expr = null;
            if (self.match(.Colon)) {
                annotation = try self.parseExpr();
            }

            try args_list.append(.{
                .arg = arg_tok.lexeme,
                .annotation = annotation,
                .type_comment = null,
            });

            if (!self.match(.Comma)) break;
        }

        return .{
            .posonlyargs = &[_]Arg{},
            .args = try args_list.toOwnedSlice(),
            .vararg = null,
            .kwonlyargs = &[_]Arg{},
            .kw_defaults = &[_]?Expr{},
            .kwarg = null,
            .defaults = &[_]Expr{},
        };
    }

    fn parseClassDef(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'class'
        const name_tok = self.advance() orelse return error.UnexpectedEof;
        if (name_tok.type != .Name) return error.UnexpectedToken;

        var bases = std.ArrayList(Expr).init(self.allocator);
        if (self.match(.LeftParen)) {
            while (self.peek()) |tok| {
                if (tok.type == .RightParen) break;
                const base = try self.parseExpr();
                try bases.append(base);
                if (!self.match(.Comma)) break;
            }
            if (!self.match(.RightParen)) return error.UnexpectedToken;
        }

        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        return .{
            .class_def = .{
                .name = name_tok.lexeme,
                .bases = try bases.toOwnedSlice(),
                .keywords = &[_]Keyword{},
                .body = body,
                .decorator_list = &[_]Expr{},
                .type_params = &[_]TypeParam{},
            },
        };
    }

    fn parseIf(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'if'
        const test_expr = try self.parseExpr();
        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        var orelse_body: []Statement = &[_]Statement{};
        if (self.match(.KwElse)) {
            if (!self.match(.Colon)) return error.UnexpectedToken;
            orelse_body = try self.parseBlock();
        }

        return .{
            .if_stmt = .{
                .test = test_expr,
                .body = body,
                .orelse = orelse_body,
            },
        };
    }

    fn parseFor(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'for'
        const target = try self.parseExpr();
        if (!self.match(.KwIn)) return error.UnexpectedToken;
        const iter = try self.parseExpr();
        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        return .{
            .for_stmt = .{
                .target = target,
                .iter = iter,
                .body = body,
                .orelse = &[_]Statement{},
                .type_comment = null,
            },
        };
    }

    fn parseWhile(self: *RuntimeParser) !Statement {
        _ = self.advance(); // consume 'while'
        const test_expr = try self.parseExpr();
        if (!self.match(.Colon)) return error.UnexpectedToken;
        const body = try self.parseBlock();

        return .{
            .while_stmt = .{
                .test = test_expr,
                .body = body,
                .orelse = &[_]Statement{},
            },
        };
    }

    fn parseBlock(self: *RuntimeParser) ![]Statement {
        // Skip newline after colon
        _ = self.match(.Newline);
        _ = self.match(.Indent);

        var statements = std.ArrayList(Statement).init(self.allocator);
        while (self.peek()) |tok| {
            if (tok.type == .Dedent or tok.type == .Eof) break;
            if (tok.type == .Newline) {
                _ = self.advance();
                continue;
            }
            // Check for next statement at same or lower indentation
            if (tok.type == .KwElse or tok.type == .KwElif or tok.type == .KwExcept or tok.type == .KwFinally) break;

            const stmt = try self.parseStatement();
            try statements.append(stmt);
        }
        _ = self.match(.Dedent);
        return statements.toOwnedSlice();
    }

    fn parseExprStatement(self: *RuntimeParser) !Statement {
        const expr = try self.parseExpr();

        // Check for assignment
        if (self.match(.Equal)) {
            const value = try self.parseExpr();
            var targets = try self.allocator.alloc(Expr, 1);
            targets[0] = expr;
            return .{
                .assign = .{
                    .targets = targets,
                    .value = value,
                    .type_comment = null,
                },
            };
        }

        return .{ .expr_stmt = .{ .value = expr } };
    }

    fn parseExpr(self: *RuntimeParser) !Expr {
        return self.parseOr();
    }

    fn parseOr(self: *RuntimeParser) !Expr {
        var left = try self.parseAnd();
        while (self.match(.KwOr)) {
            const right = try self.parseAnd();
            var values = try self.allocator.alloc(Expr, 2);
            values[0] = left;
            values[1] = right;
            left = .{ .bool_op = .{ .op = .@"or", .values = values } };
        }
        return left;
    }

    fn parseAnd(self: *RuntimeParser) !Expr {
        var left = try self.parseNot();
        while (self.match(.KwAnd)) {
            const right = try self.parseNot();
            var values = try self.allocator.alloc(Expr, 2);
            values[0] = left;
            values[1] = right;
            left = .{ .bool_op = .{ .op = .@"and", .values = values } };
        }
        return left;
    }

    fn parseNot(self: *RuntimeParser) !Expr {
        if (self.match(.KwNot)) {
            const operand = try self.parseNot();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .not, .operand = operand_ptr } };
        }
        return self.parseComparison();
    }

    fn parseComparison(self: *RuntimeParser) !Expr {
        var left = try self.parseAddSub();

        var ops = std.ArrayList(CmpOp).init(self.allocator);
        var comparators = std.ArrayList(Expr).init(self.allocator);

        while (true) {
            const op: ?CmpOp = if (self.match(.Less)) .lt else if (self.match(.Greater)) .gt else if (self.match(.LessEqual)) .lte else if (self.match(.GreaterEqual)) .gte else if (self.match(.EqualEqual)) .eq else if (self.match(.NotEqual)) .not_eq else if (self.match(.KwIn)) .in else if (self.match(.KwIs)) .is else null;

            if (op) |o| {
                try ops.append(o);
                const right = try self.parseAddSub();
                try comparators.append(right);
            } else break;
        }

        if (ops.items.len > 0) {
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return .{
                .compare = .{
                    .left = left_ptr,
                    .ops = try ops.toOwnedSlice(),
                    .comparators = try comparators.toOwnedSlice(),
                },
            };
        }

        return left;
    }

    fn parseAddSub(self: *RuntimeParser) !Expr {
        var left = try self.parseMulDiv();

        while (true) {
            const op: ?Operator = if (self.match(.Plus)) .add else if (self.match(.Minus)) .sub else null;

            if (op) |o| {
                const right = try self.parseMulDiv();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = right;
                left = .{ .bin_op = .{ .left = left_ptr, .op = o, .right = right_ptr } };
            } else break;
        }

        return left;
    }

    fn parseMulDiv(self: *RuntimeParser) !Expr {
        var left = try self.parsePower();

        while (true) {
            const op: ?Operator = if (self.match(.Star)) .mult else if (self.match(.Slash)) .div else if (self.match(.DoubleSlash)) .floor_div else if (self.match(.Percent)) .mod else if (self.match(.At)) .mat_mult else null;

            if (op) |o| {
                const right = try self.parsePower();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = right;
                left = .{ .bin_op = .{ .left = left_ptr, .op = o, .right = right_ptr } };
            } else break;
        }

        return left;
    }

    fn parsePower(self: *RuntimeParser) !Expr {
        var base = try self.parseUnary();

        if (self.match(.DoubleStar)) {
            const exp = try self.parsePower(); // Right associative
            const base_ptr = try self.allocator.create(Expr);
            base_ptr.* = base;
            const exp_ptr = try self.allocator.create(Expr);
            exp_ptr.* = exp;
            return .{ .bin_op = .{ .left = base_ptr, .op = .pow, .right = exp_ptr } };
        }

        return base;
    }

    fn parseUnary(self: *RuntimeParser) !Expr {
        if (self.match(.Minus)) {
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .usub, .operand = operand_ptr } };
        }
        if (self.match(.Plus)) {
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .uadd, .operand = operand_ptr } };
        }
        if (self.match(.Tilde)) {
            const operand = try self.parseUnary();
            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;
            return .{ .unary_op = .{ .op = .invert, .operand = operand_ptr } };
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *RuntimeParser) !Expr {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.match(.LeftParen)) {
                // Function call
                var args = std.ArrayList(Expr).init(self.allocator);
                while (self.peek()) |tok| {
                    if (tok.type == .RightParen) break;
                    const arg = try self.parseExpr();
                    try args.append(arg);
                    if (!self.match(.Comma)) break;
                }
                if (!self.match(.RightParen)) return error.UnexpectedToken;

                const func_ptr = try self.allocator.create(Expr);
                func_ptr.* = expr;
                expr = .{
                    .call = .{
                        .func = func_ptr,
                        .args = try args.toOwnedSlice(),
                        .keywords = &[_]Keyword{},
                    },
                };
            } else if (self.match(.LeftBracket)) {
                // Subscript
                const index = try self.parseExpr();
                if (!self.match(.RightBracket)) return error.UnexpectedToken;

                const value_ptr = try self.allocator.create(Expr);
                value_ptr.* = expr;
                const slice_ptr = try self.allocator.create(Expr);
                slice_ptr.* = index;
                expr = .{
                    .subscript = .{
                        .value = value_ptr,
                        .slice = slice_ptr,
                        .ctx = .load,
                    },
                };
            } else if (self.match(.Dot)) {
                // Attribute access
                const attr_tok = self.advance() orelse return error.UnexpectedEof;
                if (attr_tok.type != .Name) return error.UnexpectedToken;

                const value_ptr = try self.allocator.create(Expr);
                value_ptr.* = expr;
                expr = .{
                    .attribute = .{
                        .value = value_ptr,
                        .attr = attr_tok.lexeme,
                        .ctx = .load,
                    },
                };
            } else break;
        }

        return expr;
    }

    fn parsePrimary(self: *RuntimeParser) !Expr {
        const tok = self.advance() orelse return error.UnexpectedEof;

        return switch (tok.type) {
            .Number => .{
                .constant = .{
                    .value = if (std.mem.indexOf(u8, tok.lexeme, ".") != null)
                        .{ .float_val = std.fmt.parseFloat(f64, tok.lexeme) catch 0.0 }
                    else
                        .{ .int_val = std.fmt.parseInt(i64, tok.lexeme, 0) catch 0 },
                    .kind = null,
                },
            },
            .String => .{
                .constant = .{
                    .value = .{ .string_val = tok.lexeme },
                    .kind = null,
                },
            },
            .Name => .{
                .name = .{
                    .id = tok.lexeme,
                    .ctx = .load,
                },
            },
            .KwTrue => .{ .constant = .{ .value = .{ .bool_val = true }, .kind = null } },
            .KwFalse => .{ .constant = .{ .value = .{ .bool_val = false }, .kind = null } },
            .KwNone => .{ .constant = .{ .value = .none, .kind = null } },
            .LeftParen => blk: {
                // Tuple or grouped expression
                if (self.match(.RightParen)) {
                    break :blk .{ .tuple = .{ .elts = &[_]Expr{}, .ctx = .load } };
                }
                const inner = try self.parseExpr();
                if (self.match(.Comma)) {
                    // It's a tuple
                    var elts = std.ArrayList(Expr).init(self.allocator);
                    try elts.append(inner);
                    while (self.peek()) |t| {
                        if (t.type == .RightParen) break;
                        const elt = try self.parseExpr();
                        try elts.append(elt);
                        if (!self.match(.Comma)) break;
                    }
                    if (!self.match(.RightParen)) return error.UnexpectedToken;
                    break :blk .{ .tuple = .{ .elts = try elts.toOwnedSlice(), .ctx = .load } };
                }
                if (!self.match(.RightParen)) return error.UnexpectedToken;
                break :blk inner;
            },
            .LeftBracket => blk: {
                // List
                var elts = std.ArrayList(Expr).init(self.allocator);
                while (self.peek()) |t| {
                    if (t.type == .RightBracket) break;
                    const elt = try self.parseExpr();
                    try elts.append(elt);
                    if (!self.match(.Comma)) break;
                }
                if (!self.match(.RightBracket)) return error.UnexpectedToken;
                break :blk .{ .list = .{ .elts = try elts.toOwnedSlice(), .ctx = .load } };
            },
            .LeftBrace => blk: {
                // Dict or set
                if (self.match(.RightBrace)) {
                    break :blk .{ .dict = .{ .keys = &[_]?Expr{}, .values = &[_]Expr{} } };
                }
                const first = try self.parseExpr();
                if (self.match(.Colon)) {
                    // Dict
                    var keys = std.ArrayList(?Expr).init(self.allocator);
                    var values = std.ArrayList(Expr).init(self.allocator);
                    const first_value = try self.parseExpr();
                    try keys.append(first);
                    try values.append(first_value);

                    while (self.match(.Comma)) {
                        if (self.peek()) |t| {
                            if (t.type == .RightBrace) break;
                        }
                        const key = try self.parseExpr();
                        if (!self.match(.Colon)) return error.UnexpectedToken;
                        const value = try self.parseExpr();
                        try keys.append(key);
                        try values.append(value);
                    }
                    if (!self.match(.RightBrace)) return error.UnexpectedToken;
                    break :blk .{ .dict = .{ .keys = try keys.toOwnedSlice(), .values = try values.toOwnedSlice() } };
                } else {
                    // Set
                    var elts = std.ArrayList(Expr).init(self.allocator);
                    try elts.append(first);
                    while (self.match(.Comma)) {
                        if (self.peek()) |t| {
                            if (t.type == .RightBrace) break;
                        }
                        const elt = try self.parseExpr();
                        try elts.append(elt);
                    }
                    if (!self.match(.RightBrace)) return error.UnexpectedToken;
                    break :blk .{ .set = .{ .elts = try elts.toOwnedSlice() } };
                }
            },
            else => error.UnexpectedToken,
        };
    }
};

/// Parse source code into an AST
pub fn parse(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8) !*Module {
    _ = filename;
    _ = mode;

    var tok = Tokenizer.init(allocator, source);
    defer tok.deinit();
    const tokens = try tok.tokenize();

    var parser = RuntimeParser.init(allocator, tokens);
    return parser.parseModule();
}

/// Compile an AST into a code object
pub fn compile_ast(allocator: std.mem.Allocator, node: *Module, filename: []const u8, mode: []const u8) !*CodeObject {
    _ = mode;

    const code = try allocator.create(CodeObject);
    code.* = .{
        .co_filename = filename,
        .co_name = "<module>",
        .co_code = &[_]u8{},
        .co_consts = &[_]ConstantValue{},
        .co_names = &[_][]const u8{},
        .co_varnames = &[_][]const u8{},
        .co_argcount = 0,
        .co_nlocals = 0,
        .co_stacksize = 0,
        .co_flags = 0,
        .body = node.body,
    };
    return code;
}
