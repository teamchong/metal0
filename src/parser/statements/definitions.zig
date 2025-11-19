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

        // Check for 'async' keyword
        const is_async = self.match(.Async);

        _ = try self.expect(.Def);
        const name_tok = try self.expect(.Ident);
        _ = try self.expect(.LParen);

        var args = std.ArrayList(ast.Arg){};
        defer args.deinit(self.allocator);

        while (!self.match(.RParen)) {
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
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try misc.parseBlock(self);

        _ = try self.expect(.Dedent);

        return ast.Node{
            .function_def = .{
                .name = name_tok.lexeme,
                .args = try args.toOwnedSlice(self.allocator),
                .body = body,
                .is_async = is_async,
                .decorators = &[_]ast.Node{}, // Empty decorators for now
                .return_type = return_type,
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
                const base_tok = try self.expect(.Ident);
                try bases.append(self.allocator, base_tok.lexeme);

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
