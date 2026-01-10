//! xml.etree.ElementPath - XPath-like element path expressions
//! Reference: cpython/Lib/xml/etree/ElementPath.py
//!
//! This module provides XPath-like path expressions for Element trees.

const std = @import("std");
const Element = @import("../element.zig").Element;

// ============================================================================
// Path Expression Tokens
// ============================================================================

/// Path token types
const TokenType = enum {
    tag, // Tag name
    star, // Wildcard *
    dot, // Current node .
    dotdot, // Parent ..
    slash, // Child /
    double_slash, // Descendant //
    at, // Attribute @
    bracket_open, // Predicate [
    bracket_close, // ]
    text, // text()
    position, // position()
    last, // last()
};

/// Path token
const Token = struct {
    token_type: TokenType,
    value: ?[]const u8,
};

// ============================================================================
// Path Operations
// ============================================================================

/// Prepare a path pattern for matching
/// CPython: _build_path_iterator
pub fn prepare(allocator: std.mem.Allocator, path: []const u8) !PathMatcher {
    return PathMatcher.compile(allocator, path);
}

/// Find first matching element
/// CPython: def find(elem, path, namespaces=None)
pub fn find(elem: *Element, path: []const u8) ?*Element {
    // Simple path matching
    if (std.mem.eql(u8, path, ".")) {
        return elem;
    }
    if (std.mem.eql(u8, path, "*")) {
        if (elem.children.items.len > 0) {
            return elem.children.items[0];
        }
        return null;
    }

    // Direct child by tag
    return elem.find(path);
}

/// Find all matching elements
/// CPython: def findall(elem, path, namespaces=None)
pub fn findall(allocator: std.mem.Allocator, elem: *Element, path: []const u8) ![]*Element {
    var result = std.ArrayList(*Element){};
    errdefer result.deinit(allocator);

    if (std.mem.eql(u8, path, ".")) {
        try result.append(allocator, elem);
    } else if (std.mem.eql(u8, path, "*")) {
        for (elem.children.items) |child| {
            try result.append(allocator, child);
        }
    } else if (std.mem.startsWith(u8, path, ".//")) {
        // Descendant search
        const tag = path[3..];
        try findDescendants(allocator, &result, elem, tag);
    } else {
        // Direct children by tag
        for (elem.children.items) |child| {
            if (std.mem.eql(u8, child.tag, path)) {
                try result.append(allocator, child);
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Find text of first matching element
/// CPython: def findtext(elem, path, default=None, namespaces=None)
pub fn findtext(elem: *Element, path: []const u8, default: ?[]const u8) ?[]const u8 {
    if (find(elem, path)) |found| {
        return found.text orelse default;
    }
    return default;
}

/// Iterate over matching elements
/// CPython: def iterfind(elem, path, namespaces=None)
pub fn iterfind(elem: *Element, path: []const u8) PathIterator {
    return PathIterator.init(elem, path);
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Find all descendants with matching tag
fn findDescendants(allocator: std.mem.Allocator, result: *std.ArrayList(*Element), elem: *Element, tag: []const u8) !void {
    for (elem.children.items) |child| {
        if (std.mem.eql(u8, child.tag, tag) or std.mem.eql(u8, tag, "*")) {
            try result.append(allocator, child);
        }
        try findDescendants(allocator, result, child, tag);
    }
}

// ============================================================================
// PathMatcher
// ============================================================================

/// Compiled path matcher
pub const PathMatcher = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    path: []const u8,
    tokens: std.ArrayList(Token),

    pub fn compile(allocator: std.mem.Allocator, path: []const u8) !Self {
        var self = Self{
            .allocator = allocator,
            .path = path,
            .tokens = .{},
        };

        // Simple tokenization
        var pos: usize = 0;
        while (pos < path.len) {
            if (path[pos] == '/') {
                if (pos + 1 < path.len and path[pos + 1] == '/') {
                    try self.tokens.append(allocator, .{ .token_type = .double_slash, .value = null });
                    pos += 2;
                } else {
                    try self.tokens.append(allocator, .{ .token_type = .slash, .value = null });
                    pos += 1;
                }
            } else if (path[pos] == '*') {
                try self.tokens.append(allocator, .{ .token_type = .star, .value = null });
                pos += 1;
            } else if (path[pos] == '.') {
                if (pos + 1 < path.len and path[pos + 1] == '.') {
                    try self.tokens.append(allocator, .{ .token_type = .dotdot, .value = null });
                    pos += 2;
                } else {
                    try self.tokens.append(allocator, .{ .token_type = .dot, .value = null });
                    pos += 1;
                }
            } else if (path[pos] == '@') {
                try self.tokens.append(allocator, .{ .token_type = .at, .value = null });
                pos += 1;
            } else if (path[pos] == '[') {
                try self.tokens.append(allocator, .{ .token_type = .bracket_open, .value = null });
                pos += 1;
            } else if (path[pos] == ']') {
                try self.tokens.append(allocator, .{ .token_type = .bracket_close, .value = null });
                pos += 1;
            } else {
                // Tag name
                const start = pos;
                while (pos < path.len and path[pos] != '/' and path[pos] != '[' and path[pos] != '@') {
                    pos += 1;
                }
                try self.tokens.append(allocator, .{ .token_type = .tag, .value = path[start..pos] });
            }
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn match(self: *Self, elem: *Element) bool {
        _ = self;
        _ = elem;
        return true;
    }
};

// ============================================================================
// PathIterator
// ============================================================================

/// Iterator for path matches
pub const PathIterator = struct {
    const Self = @This();

    elem: *Element,
    path: []const u8,
    index: usize,

    pub fn init(elem: *Element, path: []const u8) Self {
        return .{
            .elem = elem,
            .path = path,
            .index = 0,
        };
    }

    pub fn next(self: *Self) ?*Element {
        while (self.index < self.elem.children.items.len) {
            const child = self.elem.children.items[self.index];
            self.index += 1;

            if (std.mem.eql(u8, self.path, "*") or std.mem.eql(u8, child.tag, self.path)) {
                return child;
            }
        }
        return null;
    }
};

// ============================================================================
// XPath Subset Support
// ============================================================================

/// Get element by predicate index
/// CPython: Supports elem[n] syntax
pub fn getByIndex(elem: *Element, path: []const u8, index: usize) ?*Element {
    var count: usize = 0;
    for (elem.children.items) |child| {
        if (std.mem.eql(u8, child.tag, path) or std.mem.eql(u8, path, "*")) {
            if (count == index) return child;
            count += 1;
        }
    }
    return null;
}

/// Get element by attribute value
/// CPython: Supports elem[@attr='value'] syntax
pub fn getByAttribute(elem: *Element, path: []const u8, attr: []const u8, value: []const u8) ?*Element {
    for (elem.children.items) |child| {
        if (std.mem.eql(u8, child.tag, path) or std.mem.eql(u8, path, "*")) {
            if (child.get(attr, null)) |v| {
                if (std.mem.eql(u8, v, value)) return child;
            }
        }
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "find" {
    const allocator = std.testing.allocator;
    const elem = try Element.init(allocator, "root");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    _ = try elem.makeElement("child");

    const found = find(elem, "child");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("child", found.?.tag);
}

test "findall" {
    const allocator = std.testing.allocator;
    const elem = try Element.init(allocator, "root");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    _ = try elem.makeElement("child");
    _ = try elem.makeElement("child");

    const found = try findall(allocator, elem, "child");
    defer allocator.free(found);
    try std.testing.expectEqual(@as(usize, 2), found.len);
}
