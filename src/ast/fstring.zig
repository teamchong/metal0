const std = @import("std");

// Forward declaration - Node is defined in core.zig
// We only use *Node (pointer), so we don't need the complete type here
const Node = @import("core.zig").Node;

/// F-string part - can be literal text, expression, or formatted expression
pub const FStringPart = union(enum) {
    literal: []const u8,
    expr: *Node,
    format_expr: struct {
        expr: *Node,
        format_spec: []const u8,
        conversion: ?u8 = null, // 'r', 's', or 'a' for !r, !s, !a
    },
    // Expression with conversion but no format spec (e.g., {x!r})
    conv_expr: struct {
        expr: *Node,
        conversion: u8, // 'r', 's', or 'a'
    },
};

/// F-string node - contains multiple parts
pub const FString = struct {
    parts: []FStringPart,
};
