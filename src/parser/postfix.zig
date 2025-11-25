const std = @import("std");
const ast = @import("../ast.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

// Re-export sub-modules
const subscript = @import("postfix/subscript.zig");
const call = @import("postfix/call.zig");
const primary = @import("postfix/primary.zig");

pub const parseCall = call.parseCall;
pub const parsePrimary = primary.parsePrimary;

/// Parse postfix expressions: function calls, subscripts, attribute access
pub fn parsePostfix(self: *Parser) ParseError!ast.Node {
    var node = try parsePrimary(self);

    while (true) {
        if (self.match(.LParen)) {
            node = try parseCall(self, node);
        } else if (self.match(.LBracket)) {
            node = try subscript.parseSubscript(self, node);
        } else if (self.match(.Dot)) {
            node = try parseAttribute(self, node);
        } else {
            break;
        }
    }

    return node;
}

/// Parse attribute access: value.attr
fn parseAttribute(self: *Parser, value: ast.Node) ParseError!ast.Node {
    const attr_tok = try self.expect(.Ident);

    const node_ptr = try self.allocator.create(ast.Node);
    node_ptr.* = value;

    return ast.Node{
        .attribute = .{
            .value = node_ptr,
            .attr = attr_tok.lexeme,
        },
    };
}
