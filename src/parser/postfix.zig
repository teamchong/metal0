const std = @import("std");
const ast = @import("ast");
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
    // We own node until we successfully return it or pass it to a sub-function
    // Sub-functions take ownership and are responsible for cleanup on error

    while (true) {
        if (self.match(.LParen)) {
            // parseCall takes ownership immediately - if it fails, it cleans up
            node = parseCall(self, node) catch |err| return err;
        } else if (self.match(.LBracket)) {
            // parseSubscript takes ownership immediately
            node = subscript.parseSubscript(self, node) catch |err| return err;
        } else if (self.match(.Dot)) {
            // parseAttribute takes ownership immediately
            node = parseAttribute(self, node) catch |err| return err;
        } else {
            break;
        }
    }

    return node;
}

/// Parse attribute access: value.attr
/// Takes ownership of `value` - cleans it up on error
fn parseAttribute(self: *Parser, value: ast.Node) ParseError!ast.Node {
    var val = value;

    const attr_tok = self.expect(.Ident) catch |err| {
        val.deinit(self.allocator);
        return err;
    };

    const node_ptr = self.allocator.create(ast.Node) catch |err| {
        val.deinit(self.allocator);
        return err;
    };
    node_ptr.* = val;
    // On success, ownership transfers to node_ptr in returned node

    return ast.Node{
        .attribute = .{
            .value = node_ptr,
            .attr = attr_tok.lexeme,
        },
    };
}
