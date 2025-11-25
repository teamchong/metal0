/// Function and class definition parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

/// Parse type annotation supporting PEP 585 generics (e.g., int, str, list[int], tuple[str, str], dict[str, int])
fn parseTypeAnnotation(self: *Parser) ParseError!?[]const u8 {
    if (self.current >= self.tokens.len or self.tokens[self.current].type != .Ident) {
        return null;
    }

    const base_type = self.tokens[self.current].lexeme;
    self.current += 1;

    // Check for generic type parameters: Type[...]
    if (self.current < self.tokens.len and self.tokens[self.current].type == .LBracket) {
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);

        try type_buf.appendSlice(self.allocator, base_type);
        try type_buf.append(self.allocator, '[');
        self.current += 1; // consume '['

        var bracket_depth: usize = 1;
        var need_separator = false;

        while (self.current < self.tokens.len and bracket_depth > 0) {
            const tok = self.tokens[self.current];
            switch (tok.type) {
                .LBracket => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.append(self.allocator, '[');
                    bracket_depth += 1;
                    need_separator = false;
                },
                .RBracket => {
                    try type_buf.append(self.allocator, ']');
                    bracket_depth -= 1;
                    need_separator = true;
                },
                .Comma => {
                    try type_buf.appendSlice(self.allocator, ", ");
                    need_separator = false;
                },
                .Ident => {
                    if (need_separator) try type_buf.appendSlice(self.allocator, ", ");
                    try type_buf.appendSlice(self.allocator, tok.lexeme);
                    need_separator = true;
                },
                else => break, // unexpected token, stop parsing
            }
            self.current += 1;
        }

        return try self.allocator.dupe(u8, type_buf.items);
    }

    return base_type;
}

pub fn parseFunctionDef(self: *Parser) ParseError!ast.Node {
        // Parse decorators first (if any)
        var decorators = std.ArrayList(ast.Node){};
        defer decorators.deinit(self.allocator);

        // Note: Decorators should be parsed by the caller before calling this function
        // This function only handles the actual function definition

        // Track if this is a nested function
        const is_nested = self.function_depth > 0;

        // Check for 'async' keyword
        const is_async = self.match(.Async);

        _ = try self.expect(.Def);
        const name_tok = try self.expect(.Ident);
        _ = try self.expect(.LParen);

        var args = std.ArrayList(ast.Arg){};
        defer args.deinit(self.allocator);
        var vararg_name: ?[]const u8 = null;
        var kwarg_name: ?[]const u8 = null;

        while (!self.match(.RParen)) {
            // Check for **kwargs (must check before *args since ** starts with *)
            if (self.match(.DoubleStar)) {
                const arg_name = try self.expect(.Ident);
                kwarg_name = arg_name.lexeme;

                // **kwargs must be last parameter
                if (!self.match(.Comma)) {
                    _ = try self.expect(.RParen);
                    break;
                }
                continue;
            }

            // Check for *args
            if (self.match(.Star)) {
                const arg_name = try self.expect(.Ident);
                vararg_name = arg_name.lexeme;

                // *args can be followed by **kwargs
                if (!self.match(.Comma)) {
                    _ = try self.expect(.RParen);
                    break;
                }
                continue;
            }

            const arg_name = try self.expect(.Ident);

            // Parse type annotation if present (e.g., : int, : str, : list[int])
            var type_annotation: ?[]const u8 = null;
            if (self.match(.Colon)) {
                type_annotation = try parseTypeAnnotation(self);
            }

            // Parse default value if present (e.g., = 0.1)
            var default_value: ?*ast.Node = null;
            if (self.match(.Eq)) {
                // Parse the default expression
                const default_expr = try self.parseExpression();
                const default_ptr = try self.allocator.create(ast.Node);
                default_ptr.* = default_expr;
                default_value = default_ptr;
            }

            try args.append(self.allocator, .{
                .name = arg_name.lexeme,
                .type_annotation = type_annotation,
                .default = default_value,
            });

            if (!self.match(.Comma)) {
                _ = try self.expect(.RParen);
                break;
            }
        }

        // Capture return type annotation if present (e.g., -> int, -> str, -> tuple[str, str])
        var return_type: ?[]const u8 = null;
        if (self.tokens[self.current].type == .Arrow or
            (self.tokens[self.current].type == .Minus and
                self.current + 1 < self.tokens.len and
                self.tokens[self.current + 1].type == .Gt))
        {
            // Skip -> or - >
            if (self.match(.Arrow)) {
                // Single arrow token
            } else {
                _ = self.match(.Minus);
                _ = self.match(.Gt);
            }
            // Parse the return type annotation (supports generics like tuple[str, str])
            return_type = try parseTypeAnnotation(self);
        }

        _ = try self.expect(.Colon);

        // Check if this is a one-liner function (def foo(): pass or def foo(): ...)
        var body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Ellipsis or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise;

            if (is_oneliner) {
                // Parse single statement without Indent/Dedent
                self.function_depth += 1;
                const stmt = try self.parseStatement();
                self.function_depth -= 1;

                // Create body with single statement
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                body = body_slice;
            } else {
                // Normal multi-line function
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);

                self.function_depth += 1;
                body = try misc.parseBlock(self);
                self.function_depth -= 1;

                _ = try self.expect(.Dedent);
            }
        } else {
            return ParseError.UnexpectedEof;
        }

        return ast.Node{
            .function_def = .{
                .name = name_tok.lexeme,
                .args = try args.toOwnedSlice(self.allocator),
                .body = body,
                .is_async = is_async,
                .decorators = &[_]ast.Node{}, // Empty decorators for now
                .return_type = return_type,
                .is_nested = is_nested,
                .vararg = vararg_name,
                .kwarg = kwarg_name,
            },
        };
    }

pub fn parseClassDef(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Class);
        const name_tok = try self.expect(.Ident);

        // Parse optional base classes: class Dog(Animal):
        var bases = std.ArrayList([]const u8){};
        defer bases.deinit(self.allocator);

        if (self.match(.LParen)) {
            while (!self.match(.RParen)) {
                // Parse base class name, supporting dotted names like "unittest.TestCase"
                const first_tok = try self.expect(.Ident);

                // Check for keyword argument (e.g., metaclass=ABCMeta)
                if (self.match(.Eq)) {
                    // Skip the keyword argument value - could be simple name or dotted
                    _ = try self.expect(.Ident);
                    while (self.match(.Dot)) {
                        _ = try self.expect(.Ident);
                    }
                    // Continue to next item or end
                    if (!self.match(.Comma)) {
                        _ = try self.expect(.RParen);
                        break;
                    }
                    continue;
                }

                var base_name = std.ArrayList(u8){};
                defer base_name.deinit(self.allocator);
                try base_name.appendSlice(self.allocator, first_tok.lexeme);

                // Check for dotted name (module.Class)
                while (self.match(.Dot)) {
                    try base_name.append(self.allocator, '.');
                    const next_tok = try self.expect(.Ident);
                    try base_name.appendSlice(self.allocator, next_tok.lexeme);
                }

                // Allocate and store the full dotted name
                const owned_name = try self.allocator.dupe(u8, base_name.items);
                try bases.append(self.allocator, owned_name);

                if (!self.match(.Comma)) {
                    _ = try self.expect(.RParen);
                    break;
                }
            }
        }

        _ = try self.expect(.Colon);

        // Check if this is a one-liner class (class C: pass or class C: ...)
        var body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Ellipsis or
                next_tok.type == .Ident; // for simple statements

            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                body = body_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                body = try misc.parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        } else {
            return ParseError.UnexpectedEof;
        }

        return ast.Node{
            .class_def = .{
                .name = name_tok.lexeme,
                .bases = try bases.toOwnedSlice(self.allocator),
                .body = body,
            },
        };
    }
