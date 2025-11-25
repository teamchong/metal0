/// Import statement parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseImport(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Import);

        const first_tok = try self.expect(.Ident);

        // Check for dotted module path (os.path, unittest.mock)
        var module_name: []const u8 = first_tok.lexeme;

        if (self.check(.Dot)) {
            // Need to construct dotted name
            var module_parts = std.ArrayList(u8){};
            defer module_parts.deinit(self.allocator);

            try module_parts.appendSlice(self.allocator, first_tok.lexeme);

            while (self.match(.Dot)) {
                try module_parts.append(self.allocator, '.');
                const next_tok = try self.expect(.Ident);
                try module_parts.appendSlice(self.allocator, next_tok.lexeme);
            }

            // Only allocate new string if we found dots
            if (module_parts.items.len > first_tok.lexeme.len) {
                module_name = try self.allocator.dupe(u8, module_parts.items);
            }
        }

        var asname: ?[]const u8 = null;

        // Check for "as" clause
        if (self.match(.As)) {
            const alias_tok = try self.expect(.Ident);
            asname = alias_tok.lexeme;
        }

        _ = self.match(.Newline);

        return ast.Node{
            .import_stmt = .{
                .module = module_name,
                .asname = asname,
            },
        };
    }

    /// Parse from-import: from numpy import array, zeros
/// Also handles dotted imports: from os.path import join
/// Also handles relative imports: from .module import X, from ..module import X
pub fn parseImportFrom(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.From);

        // Parse module name (may be dotted: os.path, test.support.os_helper)
        // Or relative: .module, ..module
        var module_parts = std.ArrayList(u8){};
        defer module_parts.deinit(self.allocator);

        // Handle relative imports (leading dots)
        while (self.match(.Dot)) {
            try module_parts.append(self.allocator, '.');
        }

        // After dots, we may have a module name or just dots (from . import X)
        if (self.check(.Ident)) {
            const first_tok = try self.expect(.Ident);
            try module_parts.appendSlice(self.allocator, first_tok.lexeme);

            // Handle dotted module path
            while (self.match(.Dot)) {
                try module_parts.append(self.allocator, '.');
                const next_tok = try self.expect(.Ident);
                try module_parts.appendSlice(self.allocator, next_tok.lexeme);
            }
        }

        const module_name = try self.allocator.dupe(u8, module_parts.items);
        errdefer self.allocator.free(module_name);

        _ = try self.expect(.Import);

        var names = std.ArrayList([]const u8){};
        errdefer names.deinit(self.allocator);
        var asnames = std.ArrayList(?[]const u8){};
        errdefer asnames.deinit(self.allocator);

        // Handle optional parentheses for multiline imports
        const has_parens = self.match(.LParen);
        if (has_parens) {
            _ = self.match(.Newline); // Skip newline after opening paren
        }

        // Parse comma-separated names
        while (true) {
            _ = self.match(.Newline); // Skip leading newlines (for multiline)

            const name_tok = try self.expect(.Ident);
            try names.append(self.allocator, name_tok.lexeme);

            // Check for "as" alias
            if (self.match(.As)) {
                const alias_tok = try self.expect(.Ident);
                try asnames.append(self.allocator, alias_tok.lexeme);
            } else {
                try asnames.append(self.allocator, null);
            }

            _ = self.match(.Newline); // Skip trailing newlines (for multiline)

            if (!self.match(.Comma)) break;
        }

        if (has_parens) {
            _ = self.match(.Newline); // Skip newline before closing paren
            _ = try self.expect(.RParen);
        }

        _ = self.match(.Newline);

        return ast.Node{
            .import_from = .{
                .module = module_name,
                .names = try names.toOwnedSlice(self.allocator),
                .asnames = try asnames.toOwnedSlice(self.allocator),
            },
        };
    }
