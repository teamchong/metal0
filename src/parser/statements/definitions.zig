/// Function and class definition parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

/// Extract base class name from expression node (for class bases)
/// Returns newly allocated string, or null for complex expressions like function calls
fn extractBaseName(self: *Parser, node: ast.Node) ?[]const u8 {
    switch (node) {
        .name => |n| return self.allocator.dupe(u8, n.id) catch null,
        .attribute => {
            // Build dotted name: a.b.c
            var parts = std.ArrayList(u8){};
            defer parts.deinit(self.allocator);

            // Build the full name by collecting parts
            collectDottedParts(self, node, &parts) catch return null;
            if (parts.items.len == 0) return null;

            return self.allocator.dupe(u8, parts.items) catch null;
        },
        else => return null, // Function calls, subscripts, etc. - not supported as base names
    }
}

/// Recursively collect parts of a dotted name
fn collectDottedParts(self: *Parser, node: ast.Node, parts: *std.ArrayList(u8)) !void {
    switch (node) {
        .name => |n| {
            try parts.appendSlice(self.allocator, n.id);
        },
        .attribute => |attr| {
            try collectDottedParts(self, attr.value.*, parts);
            try parts.append(self.allocator, '.');
            try parts.appendSlice(self.allocator, attr.attr);
        },
        else => {}, // Ignore complex expressions
    }
}

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
            // Check for positional-only parameter marker (/)
            // Python 3.8+ uses / to mark end of positional-only parameters
            // e.g., def foo(a, /, b): means a is positional-only
            if (self.match(.Slash)) {
                // Just skip it - it's a marker, not a parameter
                _ = self.match(.Comma); // optional comma after /
                continue;
            }

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

            // Check for *args or keyword-only marker (bare *)
            if (self.match(.Star)) {
                // Check if this is bare * (keyword-only marker) or *args
                if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                    // *args: has identifier after *
                    const arg_name = try self.expect(.Ident);
                    vararg_name = arg_name.lexeme;
                }
                // else: bare * is keyword-only marker, just skip it

                // *args or * can be followed by more parameters or **kwargs
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
                next_tok.type == .Raise or
                next_tok.type == .Ident; // for assignments and expressions like self.x = v

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
        // Supports: simple names (Animal), dotted names (abc.ABC), keyword args (metaclass=ABCMeta),
        // and function calls (with_metaclass(ABCMeta)) - function calls are parsed but not stored
        var bases = std.ArrayList([]const u8){};
        defer bases.deinit(self.allocator);

        if (self.match(.LParen)) {
            while (!self.match(.RParen)) {
                // Check for keyword argument (e.g., metaclass=ABCMeta)
                // We need to peek ahead to see if this is name=value pattern
                if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                    if (self.current + 1 < self.tokens.len and self.tokens[self.current + 1].type == .Eq) {
                        // Skip keyword argument: name = expression
                        _ = try self.expect(.Ident); // keyword name
                        _ = try self.expect(.Eq); // =
                        _ = try self.parseExpression(); // value expression
                        // Continue to next item or end
                        if (!self.match(.Comma)) {
                            _ = try self.expect(.RParen);
                            break;
                        }
                        continue;
                    }
                }

                // Parse base class as a full expression
                // This handles: simple names, dotted names, and function calls
                const expr = try self.parseExpression();

                // Extract name from expression if it's a simple name or attribute access
                const base_name = extractBaseName(self, expr);
                if (base_name) |name| {
                    try bases.append(self.allocator, name);
                }
                // If it's a function call or other complex expression, we skip adding it to bases
                // (codegen won't use it, but at least parsing succeeds)

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
