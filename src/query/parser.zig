//! SQL Parser - recursive descent parser for SELECT statements.
//!
//! Grammar (simplified):
//!   select_stmt = SELECT [DISTINCT] select_list FROM table_name
//!                 [WHERE expr]
//!                 [GROUP BY column_list]
//!                 [HAVING expr]
//!                 [ORDER BY order_list]
//!                 [LIMIT number]
//!                 [OFFSET number]
//!
//!   select_list = select_item (, select_item)*
//!   select_item = * | expr [AS alias]
//!   expr        = or_expr
//!   or_expr     = and_expr (OR and_expr)*
//!   and_expr    = cmp_expr (AND cmp_expr)*
//!   cmp_expr    = add_expr ((= | != | < | <= | > | >=) add_expr)?
//!   add_expr    = mul_expr ((+ | -) mul_expr)*
//!   mul_expr    = unary_expr ((* | /) unary_expr)*
//!   unary_expr  = [NOT | -] primary
//!   primary     = literal | identifier | function_call | ( expr )

const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const ast = @import("ast.zig");
const SelectStmt = ast.SelectStmt;
const SelectItem = ast.SelectItem;
const OrderBy = ast.OrderBy;
const expr_mod = @import("expr.zig");
const Expr = expr_mod.Expr;
const BinaryOp = expr_mod.BinaryOp;
const UnaryOp = expr_mod.UnaryOp;
const Value = @import("lanceql.value").Value;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidNumber,
    OutOfMemory,
};

/// SQL Parser.
pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,
    current: Token,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, sql: []const u8) Self {
        var lexer = Lexer.init(sql);
        const first_token = lexer.next();
        return .{
            .lexer = lexer,
            .allocator = allocator,
            .current = first_token,
        };
    }

    /// Parse a SQL string into a SelectStmt.
    pub fn parse(allocator: std.mem.Allocator, sql: []const u8) ParseError!SelectStmt {
        var parser = Parser.init(allocator, sql);
        return parser.parseSelect();
    }

    // ========================================================================
    // Token handling
    // ========================================================================

    fn advance(self: *Self) void {
        self.current = self.lexer.next();
    }

    fn expect(self: *Self, expected: TokenType) ParseError!Token {
        if (self.current.type != expected) {
            return error.UnexpectedToken;
        }
        const tok = self.current;
        self.advance();
        return tok;
    }

    fn check(self: *Self, token_type: TokenType) bool {
        return self.current.type == token_type;
    }

    fn match(self: *Self, token_type: TokenType) bool {
        if (self.check(token_type)) {
            self.advance();
            return true;
        }
        return false;
    }

    // ========================================================================
    // Statement parsing
    // ========================================================================

    fn parseSelect(self: *Self) ParseError!SelectStmt {
        _ = try self.expect(.select);

        // DISTINCT?
        const distinct = self.match(.distinct);

        // Select list
        const columns = try self.parseSelectList();

        // FROM
        var from: ?[]const u8 = null;
        if (self.match(.from)) {
            const table_tok = try self.expect(.identifier);
            from = table_tok.value;
        }

        // WHERE
        var where: ?*Expr = null;
        if (self.match(.where)) {
            where = try self.parseExpr();
        }

        // GROUP BY
        var group_by: [][]const u8 = &.{};
        if (self.match(.group)) {
            _ = try self.expect(.by);
            group_by = try self.parseColumnList();
        }

        // HAVING
        var having: ?*Expr = null;
        if (self.match(.having)) {
            having = try self.parseExpr();
        }

        // ORDER BY
        var order_by: []OrderBy = &.{};
        if (self.match(.order)) {
            _ = try self.expect(.by);
            order_by = try self.parseOrderByList();
        }

        // LIMIT
        var limit: ?u64 = null;
        if (self.match(.limit)) {
            const limit_tok = try self.expect(.integer);
            limit = std.fmt.parseInt(u64, limit_tok.value, 10) catch return error.InvalidNumber;
        }

        // OFFSET
        var offset: ?u64 = null;
        if (self.match(.offset)) {
            const offset_tok = try self.expect(.integer);
            offset = std.fmt.parseInt(u64, offset_tok.value, 10) catch return error.InvalidNumber;
        }

        return SelectStmt{
            .columns = columns,
            .from = from,
            .where = where,
            .group_by = group_by,
            .having = having,
            .order_by = order_by,
            .limit = limit,
            .offset = offset,
            .distinct = distinct,
        };
    }

    fn parseSelectList(self: *Self) ParseError![]SelectItem {
        var items: std.ArrayListUnmanaged(SelectItem) = .empty;

        items.append(self.allocator, try self.parseSelectItem()) catch return error.OutOfMemory;

        while (self.match(.comma)) {
            items.append(self.allocator, try self.parseSelectItem()) catch return error.OutOfMemory;
        }

        return items.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
    }

    fn parseSelectItem(self: *Self) ParseError!SelectItem {
        // Check for *
        if (self.match(.star)) {
            return .star;
        }

        // Expression
        const expression = try self.parseExpr();

        // Optional AS alias (only explicit AS keyword now to avoid ambiguity)
        var alias: ?[]const u8 = null;
        if (self.match(.as)) {
            const alias_tok = try self.expect(.identifier);
            alias = alias_tok.value;
        }

        return .{ .expr = .{ .expression = expression, .alias = alias } };
    }

    fn parseColumnList(self: *Self) ParseError![][]const u8 {
        var columns: std.ArrayListUnmanaged([]const u8) = .empty;

        const first = try self.expect(.identifier);
        columns.append(self.allocator, first.value) catch return error.OutOfMemory;

        while (self.match(.comma)) {
            const col = try self.expect(.identifier);
            columns.append(self.allocator, col.value) catch return error.OutOfMemory;
        }

        return columns.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
    }

    fn parseOrderByList(self: *Self) ParseError![]OrderBy {
        var items: std.ArrayListUnmanaged(OrderBy) = .empty;

        items.append(self.allocator, try self.parseOrderByItem()) catch return error.OutOfMemory;

        while (self.match(.comma)) {
            items.append(self.allocator, try self.parseOrderByItem()) catch return error.OutOfMemory;
        }

        return items.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
    }

    fn parseOrderByItem(self: *Self) ParseError!OrderBy {
        const col = try self.expect(.identifier);

        var descending = false;
        if (self.match(.desc)) {
            descending = true;
        } else {
            _ = self.match(.asc); // Optional ASC
        }

        return OrderBy{
            .column = col.value,
            .descending = descending,
        };
    }

    // ========================================================================
    // Expression parsing (precedence climbing)
    // ========================================================================

    fn parseExpr(self: *Self) ParseError!*Expr {
        return self.parseOrExpr();
    }

    fn parseOrExpr(self: *Self) ParseError!*Expr {
        var left = try self.parseAndExpr();

        while (self.match(.or_)) {
            const right = try self.parseAndExpr();
            const binary = try self.allocator.create(Expr);
            binary.* = .{ .binary = .{
                .op = .or_,
                .left = left,
                .right = right,
            } };
            left = binary;
        }

        return left;
    }

    fn parseAndExpr(self: *Self) ParseError!*Expr {
        var left = try self.parseNotExpr();

        while (self.match(.and_)) {
            const right = try self.parseNotExpr();
            const binary = try self.allocator.create(Expr);
            binary.* = .{ .binary = .{
                .op = .and_,
                .left = left,
                .right = right,
            } };
            left = binary;
        }

        return left;
    }

    fn parseNotExpr(self: *Self) ParseError!*Expr {
        if (self.match(.not)) {
            const operand = try self.parseNotExpr();
            const unary = try self.allocator.create(Expr);
            unary.* = .{ .unary = .{
                .op = .not,
                .operand = operand,
            } };
            return unary;
        }
        return self.parseCmpExpr();
    }

    fn parseCmpExpr(self: *Self) ParseError!*Expr {
        var left = try self.parseAddExpr();

        const op: ?BinaryOp = switch (self.current.type) {
            .eq => .eq,
            .ne => .ne,
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
            else => null,
        };

        if (op) |binary_op| {
            self.advance();

            // Handle IS NULL / IS NOT NULL
            if (self.current.type == .null_) {
                self.advance();
                const null_lit = try self.allocator.create(Expr);
                null_lit.* = Expr.nullLit();
                const binary = try self.allocator.create(Expr);
                binary.* = .{ .binary = .{
                    .op = binary_op,
                    .left = left,
                    .right = null_lit,
                } };
                return binary;
            }

            const right = try self.parseAddExpr();
            const binary = try self.allocator.create(Expr);
            binary.* = .{ .binary = .{
                .op = binary_op,
                .left = left,
                .right = right,
            } };
            left = binary;
        }

        // Handle IS NULL / IS NOT NULL
        if (self.match(.is)) {
            const negated = self.match(.not);
            _ = try self.expect(.null_);

            const null_lit = try self.allocator.create(Expr);
            null_lit.* = Expr.nullLit();

            const cmp_op: BinaryOp = if (negated) .ne else .eq;
            const binary = try self.allocator.create(Expr);
            binary.* = .{ .binary = .{
                .op = cmp_op,
                .left = left,
                .right = null_lit,
            } };
            return binary;
        }

        return left;
    }

    fn parseAddExpr(self: *Self) ParseError!*Expr {
        var left = try self.parseMulExpr();

        while (true) {
            const op: ?BinaryOp = switch (self.current.type) {
                .plus => .add,
                .minus => .sub,
                else => null,
            };

            if (op) |binary_op| {
                self.advance();
                const right = try self.parseMulExpr();
                const binary = try self.allocator.create(Expr);
                binary.* = .{ .binary = .{
                    .op = binary_op,
                    .left = left,
                    .right = right,
                } };
                left = binary;
            } else {
                break;
            }
        }

        return left;
    }

    fn parseMulExpr(self: *Self) ParseError!*Expr {
        var left = try self.parseUnaryExpr();

        while (true) {
            const op: ?BinaryOp = switch (self.current.type) {
                .star => .mul,
                .slash => .div,
                else => null,
            };

            if (op) |binary_op| {
                self.advance();
                const right = try self.parseUnaryExpr();
                const binary = try self.allocator.create(Expr);
                binary.* = .{ .binary = .{
                    .op = binary_op,
                    .left = left,
                    .right = right,
                } };
                left = binary;
            } else {
                break;
            }
        }

        return left;
    }

    fn parseUnaryExpr(self: *Self) ParseError!*Expr {
        if (self.match(.minus)) {
            const operand = try self.parseUnaryExpr();
            const unary = try self.allocator.create(Expr);
            unary.* = .{ .unary = .{
                .op = .neg,
                .operand = operand,
            } };
            return unary;
        }

        return self.parsePrimary();
    }

    fn parsePrimary(self: *Self) ParseError!*Expr {
        const result = try self.allocator.create(Expr);

        switch (self.current.type) {
            .integer => {
                const val = std.fmt.parseInt(i64, self.current.value, 10) catch return error.InvalidNumber;
                result.* = Expr.intLit(val);
                self.advance();
                return result;
            },
            .float => {
                const val = std.fmt.parseFloat(f64, self.current.value) catch return error.InvalidNumber;
                result.* = Expr.floatLit(val);
                self.advance();
                return result;
            },
            .string => {
                result.* = Expr.strLit(self.current.value);
                self.advance();
                return result;
            },
            .true_ => {
                result.* = Expr.boolLit(true);
                self.advance();
                return result;
            },
            .false_ => {
                result.* = Expr.boolLit(false);
                self.advance();
                return result;
            },
            .null_ => {
                result.* = Expr.nullLit();
                self.advance();
                return result;
            },
            .identifier => {
                const name = self.current.value;
                self.advance();

                // Check for function call
                if (self.match(.lparen)) {
                    return self.parseFunctionCall(result, name);
                }

                result.* = Expr.col(name);
                return result;
            },
            .lparen => {
                self.advance();
                self.allocator.destroy(result);
                const inner = try self.parseExpr();
                _ = try self.expect(.rparen);
                return inner;
            },
            .star => {
                result.* = .star;
                self.advance();
                return result;
            },
            else => {
                return error.UnexpectedToken;
            },
        }
    }

    fn parseFunctionCall(self: *Self, result: *Expr, name: []const u8) ParseError!*Expr {
        var args: std.ArrayListUnmanaged(Expr) = .empty;
        var distinct = false;

        // Check for DISTINCT
        if (self.match(.distinct)) {
            distinct = true;
        }

        // Parse arguments
        if (!self.check(.rparen)) {
            // Handle COUNT(*)
            if (self.check(.star)) {
                self.advance();
                const star_expr = try self.allocator.create(Expr);
                star_expr.* = .star;
                args.append(self.allocator, star_expr.*) catch return error.OutOfMemory;
            } else {
                const first_arg = try self.parseExpr();
                args.append(self.allocator, first_arg.*) catch return error.OutOfMemory;

                while (self.match(.comma)) {
                    const arg = try self.parseExpr();
                    args.append(self.allocator, arg.*) catch return error.OutOfMemory;
                }
            }
        }

        _ = try self.expect(.rparen);

        result.* = .{ .call = .{
            .name = name,
            .args = args.toOwnedSlice(self.allocator) catch return error.OutOfMemory,
            .distinct = distinct,
        } };

        return result;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Parser simple select" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT id, name FROM users");

    try std.testing.expectEqual(@as(usize, 2), stmt.columns.len);
    try std.testing.expectEqualStrings("users", stmt.from.?);
}

test "Parser select star" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT * FROM t");

    try std.testing.expectEqual(@as(usize, 1), stmt.columns.len);
    try std.testing.expectEqual(SelectItem.star, stmt.columns[0]);
}

test "Parser where clause" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT * FROM t WHERE id > 10");

    try std.testing.expect(stmt.where != null);
}

test "Parser group by and having" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT category, COUNT(*) FROM t GROUP BY category HAVING COUNT(*) > 5");

    try std.testing.expectEqual(@as(usize, 1), stmt.group_by.len);
    try std.testing.expectEqualStrings("category", stmt.group_by[0]);
    try std.testing.expect(stmt.having != null);
}

test "Parser order by" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT * FROM t ORDER BY id DESC, name ASC");

    try std.testing.expectEqual(@as(usize, 2), stmt.order_by.len);
    try std.testing.expectEqualStrings("id", stmt.order_by[0].column);
    try std.testing.expect(stmt.order_by[0].descending);
    try std.testing.expectEqualStrings("name", stmt.order_by[1].column);
    try std.testing.expect(!stmt.order_by[1].descending);
}

test "Parser limit offset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT * FROM t LIMIT 10 OFFSET 20");

    try std.testing.expectEqual(@as(u64, 10), stmt.limit.?);
    try std.testing.expectEqual(@as(u64, 20), stmt.offset.?);
}

test "Parser aggregate functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const stmt = try Parser.parse(arena.allocator(), "SELECT COUNT(*), SUM(value), AVG(score) FROM t");

    try std.testing.expectEqual(@as(usize, 3), stmt.columns.len);
}
