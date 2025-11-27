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
    var owned = true; // Track if we still own node (for cleanup)

    errdefer {
        if (owned) {
            node.deinit(self.allocator);
        }
    }

    while (true) {
        if (self.match(.LParen)) {
            // parseCall takes ownership - if it fails after copying, it cleans up
            // We don't own node anymore once we pass it
            owned = false;
            node = try parseCall(self, node);
            owned = true; // We now own the result
        } else if (self.match(.LBracket)) {
            owned = false;
            node = try subscript.parseSubscript(self, node);
            owned = true;
        } else if (self.match(.Dot)) {
            owned = false;
            node = try parseAttribute(self, node);
            owned = true;
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
    errdefer val.deinit(self.allocator);

    const attr_tok = try self.expect(.Ident);

    const node_ptr = try self.allocator.create(ast.Node);
    node_ptr.* = val;
    // On success, ownership transfers to node_ptr in returned node

    return ast.Node{
        .attribute = .{
            .value = node_ptr,
            .attr = attr_tok.lexeme,
        },
    };
}
