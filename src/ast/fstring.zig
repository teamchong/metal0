const std = @import("std");

// Forward declaration - Node is defined in core.zig
// We only use *Node (pointer), so we don't need the complete type here
const Node = @import("core.zig").Node;

/// Format spec part - for nested expressions in format specs (PEP 701)
/// e.g., f'{value:{width}}' has format spec parts: [expr("width")]
pub const FormatSpecPart = union(enum) {
    literal: []const u8,
    expr: *Node, // Nested expression like {width}
};

/// F-string part - can be literal text, expression, or formatted expression
pub const FStringPart = union(enum) {
    literal: []const u8,
    expr: struct {
        node: *Node,
        debug_text: ?[]const u8 = null, // For f"{x=}" stores "x="
    },
    format_expr: struct {
        expr: *Node,
        format_spec: []const u8, // Keep for simple format specs
        format_spec_parts: ?[]FormatSpecPart = null, // For nested expressions (PEP 701)
        conversion: ?u8 = null, // 'r', 's', or 'a' for !r, !s, !a
        debug_text: ?[]const u8 = null, // For f"{x=:...}" stores "x="
    },
    // Expression with conversion but no format spec (e.g., {x!r})
    conv_expr: struct {
        expr: *Node,
        conversion: u8, // 'r', 's', or 'a'
        debug_text: ?[]const u8 = null, // For f"{x=!r}" stores "x="
    },
};

/// F-string node - contains multiple parts
pub const FString = struct {
    parts: []FStringPart,
};
