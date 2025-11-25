/// Function and class definition parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

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

            // Parse type annotation if present (e.g., : int, : str)
            var type_annotation: ?[]const u8 = null;
            if (self.match(.Colon)) {
                // Next token should be the type name
                if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                    type_annotation = self.tokens[self.current].lexeme;
                    self.current += 1;
                }
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

        // Capture return type annotation if present (e.g., -> int, -> str)
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
            // Capture the return type
            if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                return_type = self.tokens[self.current].lexeme;
                self.current += 1;
            }
        }

        _ = try self.expect(.Colon);

        // Check if this is a one-liner function (def foo(): pass)
        var body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
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
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try misc.parseBlock(self);

        _ = try self.expect(.Dedent);

        return ast.Node{
            .class_def = .{
                .name = name_tok.lexeme,
                .bases = try bases.toOwnedSlice(self.allocator),
                .body = body,
            },
        };
    }
