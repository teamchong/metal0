/// Parser implementation for expressions (Pratt-style precedence climbing)
const std = @import("std");
const bytecode = @import("../compile.zig");
const tokens = @import("tokens.zig");
const lexer_mod = @import("lexer.zig");
const numeric = @import("numeric_utils.zig");

const TokenType = tokens.TokenType;
const Token = tokens.Token;
const ParseError = tokens.ParseError;
const Lexer = lexer_mod.Lexer;

/// Expression parser that compiles directly to bytecode
pub const ExprParser = struct {
    source: []const u8,
    lexer: Lexer,
    current: Token,
    compiler: bytecode.Compiler,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) ExprParser {
        var parser = ExprParser{
            .source = source,
            .lexer = Lexer.init(source),
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

        // Duplicate name strings for the program (program owns the strings)
        var names_owned = try self.allocator.alloc([]const u8, self.compiler.names.items.len);
        for (self.compiler.names.items, 0..) |name, i| {
            names_owned[i] = try self.allocator.dupe(u8, name);
        }

        return .{
            .instructions = try self.compiler.instructions.toOwnedSlice(self.allocator),
            .constants = try self.compiler.consts.toOwnedSlice(self.allocator),
            .names = names_owned,
            .allocator = self.allocator,
        };
    }

    fn advance(self: *ExprParser) !void {
        self.current = try self.lexer.advance();
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
            // Emit USub opcode for type checking and negation
            self.compiler.instructions.append(self.allocator, .{ .op = .USub }) catch return ParseError.OutOfMemory;
            return;
        }

        if (self.current.type == .Plus) {
            try self.advance();
            try self.parseUnary();
            // Emit UAdd opcode for type checking (strings/bytes should raise TypeError)
            self.compiler.instructions.append(self.allocator, .{ .op = .UAdd }) catch return ParseError.OutOfMemory;
            return;
        }

        if (self.current.type == .Tilde) {
            try self.advance();
            try self.parseUnary();
            // Bitwise NOT: ~x
            self.compiler.instructions.append(self.allocator, .{ .op = .Invert }) catch return ParseError.OutOfMemory;
            return;
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
                const clean = numeric.stripUnderscores(num_text) catch |err| return switch (err) {
                    error.OutOfMemory => ParseError.OutOfMemory,
                    error.InvalidNumber => ParseError.InvalidNumber,
                };
                // Check if it's a float (has decimal point)
                const is_float = std.mem.indexOfScalar(u8, clean, '.') != null or
                    std.mem.indexOfScalar(u8, clean, 'e') != null or
                    std.mem.indexOfScalar(u8, clean, 'E') != null;
                if (is_float) {
                    // Parse as float
                    const fval = std.fmt.parseFloat(f64, clean) catch return ParseError.InvalidNumber;
                    const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                    self.compiler.consts.append(self.allocator, .{ .float = fval }) catch return ParseError.OutOfMemory;
                    self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                    try self.advance();
                    return;
                }
                // Try integer first
                const value = std.fmt.parseInt(i64, clean, base) catch |err| {
                    if (err == error.Overflow) {
                        // Integer overflow - store as BigInt decimal string
                        // For non-base-10, we need to convert to decimal for storage
                        const bigint_str = if (base == 10) clean else blk: {
                            // Parse to BigInt and convert to decimal string
                            // For now, store the original and let VM handle base conversion
                            break :blk clean;
                        };
                        const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                        // Store as bigint with base info (base:value format for non-decimal)
                        if (base != 10) {
                            // For non-decimal bases, prefix with base info
                            const prefix_char: u8 = if (base == 2) 'b' else if (base == 8) 'o' else 'x';
                            var buf: [128]u8 = undefined;
                            const formatted = std.fmt.bufPrint(&buf, "0{c}{s}", .{ prefix_char, bigint_str }) catch return ParseError.OutOfMemory;
                            // Allocate copy of formatted string
                            const str_copy = self.allocator.dupe(u8, formatted) catch return ParseError.OutOfMemory;
                            self.compiler.consts.append(self.allocator, .{ .bigint = str_copy }) catch return ParseError.OutOfMemory;
                        } else {
                            self.compiler.consts.append(self.allocator, .{ .bigint = bigint_str }) catch return ParseError.OutOfMemory;
                        }
                        self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                        try self.advance();
                        return;
                    }
                    return ParseError.InvalidNumber;
                };
                const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                self.compiler.consts.append(self.allocator, .{ .int = value }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .Complex => {
                // Complex number like 2j or 3.14j
                const text = self.getText(self.current);
                // Strip trailing 'j' or 'J'
                const num_text = text[0 .. text.len - 1];
                const clean = numeric.stripUnderscores(num_text) catch |err| return switch (err) {
                    error.OutOfMemory => ParseError.OutOfMemory,
                    error.InvalidNumber => ParseError.InvalidNumber,
                };
                // Parse imaginary part as float
                const imag = std.fmt.parseFloat(f64, clean) catch return ParseError.InvalidNumber;
                const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                self.compiler.consts.append(self.allocator, .{ .complex = imag }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .String => {
                const text = self.getText(self.current);
                // Strip quotes
                const str = text[1 .. text.len - 1];
                const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                self.compiler.consts.append(self.allocator, .{ .string = str }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .True => {
                const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                self.compiler.consts.append(self.allocator, .{ .bool = true }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            .False => {
                const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                self.compiler.consts.append(self.allocator, .{ .bool = false }) catch return ParseError.OutOfMemory;
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
                // Emit BUILD_LIST with count
                self.compiler.instructions.append(self.allocator, .{ .op = .BuildList, .arg = count }) catch return ParseError.OutOfMemory;
            },
            .Name => {
                // Variable reference - emit LoadName
                const name = self.getText(self.current);
                const name_idx = self.compiler.addName(name) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadName, .arg = name_idx }) catch return ParseError.OutOfMemory;
                try self.advance();

                // Check for function call: name(args)
                if (self.current.type == .LParen) {
                    try self.advance(); // skip (

                    // Parse arguments
                    var arg_count: u32 = 0;
                    while (self.current.type != .RParen and self.current.type != .Eof) {
                        try self.parseExpr();
                        arg_count += 1;
                        if (self.current.type == .Comma) {
                            try self.advance();
                        } else {
                            break; // No comma means end of args (or closing paren)
                        }
                    }

                    if (self.current.type != .RParen) return ParseError.UnclosedParen;
                    try self.advance(); // skip )

                    // Emit Call with argument count
                    self.compiler.instructions.append(self.allocator, .{ .op = .Call, .arg = arg_count }) catch return ParseError.OutOfMemory;
                }
            },
            .None => {
                // Python None
                const const_idx = @as(u32, @intCast(self.compiler.consts.items.len));
                self.compiler.consts.append(self.allocator, .{ .none = {} }) catch return ParseError.OutOfMemory;
                self.compiler.instructions.append(self.allocator, .{ .op = .LoadConst, .arg = const_idx }) catch return ParseError.OutOfMemory;
                try self.advance();
            },
            else => return ParseError.UnexpectedToken,
        }
    }
};
