//! re._parser - Regular expression parser
//! Reference: cpython/Lib/re/_parser.py
//!
//! Internal module that parses regex patterns into an AST.
//! The actual parsing is handled by the native regex engine.

const std = @import("std");
const constants = @import("_constants.zig");

/// Pattern node types
pub const NodeType = enum {
    LITERAL, // Single character
    NOT_LITERAL, // Negated character
    ANY, // . (any character)
    BRANCH, // Alternation |
    IN, // Character class [...]
    NOT_IN, // Negated character class [^...]
    SUBPATTERN, // Group (...)
    GROUPREF, // Backreference \1
    AT, // Anchor (^, $, \b, etc.)
    REPEAT, // Quantifier (*, +, ?, {n,m})
    ASSERT, // Lookahead (?=...)
    ASSERT_NOT, // Negative lookahead (?!...)
    AT_BEGINNING,
    AT_END,
};

/// Pattern AST node
pub const Node = struct {
    type: NodeType,
    value: i32 = 0,
    children: ?[]Node = null,
    min: u32 = 0,
    max: u32 = 0,
    name: ?[]const u8 = null,
};

/// Parser state
pub const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pattern: []const u8,
    pos: usize,
    flags: u32,
    groups: u32,
    groupdict: std.StringHashMap(u32),

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8, flags: u32) Self {
        return .{
            .allocator = allocator,
            .pattern = pattern,
            .pos = 0,
            .flags = flags,
            .groups = 0,
            .groupdict = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.groupdict.deinit();
    }

    /// Get current character
    pub fn current(self: *Self) ?u8 {
        if (self.pos < self.pattern.len) {
            return self.pattern[self.pos];
        }
        return null;
    }

    /// Advance position
    pub fn advance(self: *Self) void {
        if (self.pos < self.pattern.len) {
            self.pos += 1;
        }
    }

    /// Peek at next character
    pub fn peek(self: *Self) ?u8 {
        if (self.pos + 1 < self.pattern.len) {
            return self.pattern[self.pos + 1];
        }
        return null;
    }

    /// Match a character and advance
    pub fn match(self: *Self, c: u8) bool {
        if (self.current() == c) {
            self.advance();
            return true;
        }
        return false;
    }

    /// Parse escape sequence
    pub fn parseEscape(self: *Self) !Node {
        self.advance(); // Skip backslash
        const c = self.current() orelse return error.IncompleteEscape;
        self.advance();

        return switch (c) {
            'd' => .{ .type = .IN, .value = constants.CATEGORY.DIGIT },
            'D' => .{ .type = .NOT_IN, .value = constants.CATEGORY.NOT_DIGIT },
            's' => .{ .type = .IN, .value = constants.CATEGORY.SPACE },
            'S' => .{ .type = .NOT_IN, .value = constants.CATEGORY.NOT_SPACE },
            'w' => .{ .type = .IN, .value = constants.CATEGORY.WORD },
            'W' => .{ .type = .NOT_IN, .value = constants.CATEGORY.NOT_WORD },
            'b' => .{ .type = .AT, .value = constants.AT.BOUNDARY },
            'B' => .{ .type = .AT, .value = constants.AT.NON_BOUNDARY },
            'A' => .{ .type = .AT, .value = constants.AT.BEGINNING_STRING },
            'Z' => .{ .type = .AT, .value = constants.AT.END_STRING },
            'n' => .{ .type = .LITERAL, .value = '\n' },
            'r' => .{ .type = .LITERAL, .value = '\r' },
            't' => .{ .type = .LITERAL, .value = '\t' },
            '0'...'9' => .{ .type = .GROUPREF, .value = c - '0' },
            else => .{ .type = .LITERAL, .value = c },
        };
    }

    /// Open a new group
    pub fn openGroup(self: *Self, name: ?[]const u8) !u32 {
        self.groups += 1;
        const gid = self.groups;
        if (name) |n| {
            try self.groupdict.put(n, gid);
        }
        return gid;
    }

    /// Close current group
    pub fn closeGroup(self: *Self, gid: u32, p: Node) Node {
        _ = gid;
        return p;
    }
};

/// Parse a pattern string
pub fn parse(allocator: std.mem.Allocator, pattern: []const u8, flags: u32) !std.ArrayList(Node) {
    var parser = Parser.init(allocator, pattern, flags);
    defer parser.deinit();

    var nodes: std.ArrayList(Node) = .{};
    errdefer nodes.deinit(allocator);

    while (parser.current()) |c| {
        const node = switch (c) {
            '.' => blk: {
                parser.advance();
                break :blk Node{ .type = .ANY };
            },
            '^' => blk: {
                parser.advance();
                break :blk Node{ .type = .AT_BEGINNING };
            },
            '$' => blk: {
                parser.advance();
                break :blk Node{ .type = .AT_END };
            },
            '\\' => try parser.parseEscape(),
            else => blk: {
                parser.advance();
                break :blk Node{ .type = .LITERAL, .value = c };
            },
        };
        try nodes.append(allocator, node);
    }

    return nodes;
}

/// Error type from regex parsing
pub const PatternError = error{
    IncompleteEscape,
    InvalidEscape,
    InvalidGroup,
    InvalidRange,
    UnbalancedParenthesis,
    UnbalancedBracket,
    OutOfMemory,
};

// ============================================================================
// Tests
// ============================================================================

test "Parser basic" {
    const allocator = std.testing.allocator;
    var nodes = try parse(allocator, "abc", 0);
    defer nodes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), nodes.items.len);
    try std.testing.expectEqual(NodeType.LITERAL, nodes.items[0].type);
}

test "Parser anchors" {
    const allocator = std.testing.allocator;
    var nodes = try parse(allocator, "^abc$", 0);
    defer nodes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), nodes.items.len);
    try std.testing.expectEqual(NodeType.AT_BEGINNING, nodes.items[0].type);
    try std.testing.expectEqual(NodeType.AT_END, nodes.items[4].type);
}

test "Parser dot" {
    const allocator = std.testing.allocator;
    var nodes = try parse(allocator, "a.b", 0);
    defer nodes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), nodes.items.len);
    try std.testing.expectEqual(NodeType.ANY, nodes.items[1].type);
}
