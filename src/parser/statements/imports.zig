/// Import statement parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseImport(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Import);

        const module_tok = try self.expect(.Ident);
        const module_name = module_tok.lexeme;

        var asname: ?[]const u8 = null;

        // Check for "as" clause
        if (self.match(.As)) {
            const alias_tok = try self.expect(.Ident);
            asname = alias_tok.lexeme;
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .import_stmt = .{
                .module = module_name,
                .asname = asname,
            },
        };
    }

    /// Parse from-import: from numpy import array, zeros
pub fn parseImportFrom(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.From);

        const module_tok = try self.expect(.Ident);
        const module_name = module_tok.lexeme;

        _ = try self.expect(.Import);

        var names = std.ArrayList([]const u8){};
        var asnames = std.ArrayList(?[]const u8){};

        // Parse comma-separated names
        while (true) {
            const name_tok = try self.expect(.Ident);
            try names.append(self.allocator, name_tok.lexeme);

            // Check for "as" alias
            if (self.match(.As)) {
                const alias_tok = try self.expect(.Ident);
                try asnames.append(self.allocator, alias_tok.lexeme);
            } else {
                try asnames.append(self.allocator, null);
            }

            if (!self.match(.Comma)) break;
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .import_from = .{
                .module = module_name,
                .names = try names.toOwnedSlice(self.allocator),
                .asnames = try asnames.toOwnedSlice(self.allocator),
            },
        };
    }
