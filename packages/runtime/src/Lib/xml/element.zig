//! XML Element class - represents an XML element with attributes and children
//!
//! This module provides the Element type which represents a node in an XML tree.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// XML Element
pub const Element = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tag: []const u8,
    text: ?[]const u8,
    tail: ?[]const u8,
    attrib: hashmap_helper.StringHashMap([]const u8),
    children: std.ArrayList(*Element),
    parent: ?*Element,

    pub fn init(allocator: std.mem.Allocator, tag: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .tag = try allocator.dupe(u8, tag),
            .text = null,
            .tail = null,
            .attrib = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .children = .{},
            .parent = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tag);
        if (self.text) |t| self.allocator.free(t);
        if (self.tail) |t| self.allocator.free(t);

        var attrib_iter = self.attrib.iterator();
        while (attrib_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.attrib.deinit();

        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit(self.allocator);
    }

    /// Get attribute value
    pub fn get(self: *Self, key: []const u8, default: ?[]const u8) ?[]const u8 {
        return self.attrib.get(key) orelse default;
    }

    /// Set attribute value
    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        const k = try self.allocator.dupe(u8, key);
        const v = try self.allocator.dupe(u8, value);
        try self.attrib.put(k, v);
    }

    /// Get all attribute keys
    pub fn keys(self: *Self) ![][]const u8 {
        var result: std.ArrayList([]const u8) = .{};
        for (self.attrib.keys()) |key| {
            try result.append(self.allocator, key);
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Get all attribute items
    pub fn items(self: *Self) ![]struct { key: []const u8, value: []const u8 } {
        var result: std.ArrayList(struct { key: []const u8, value: []const u8 }) = .{};
        var attrib_iter = self.attrib.iterator();
        while (attrib_iter.next()) |entry| {
            try result.append(self.allocator, .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Append a child element
    pub fn append(self: *Self, child: *Element) !void {
        child.parent = self;
        try self.children.append(self.allocator, child);
    }

    /// Insert a child at index
    pub fn insert(self: *Self, index: usize, child: *Element) !void {
        child.parent = self;
        try self.children.insert(self.allocator, index, child);
    }

    /// Remove a child element
    pub fn remove(self: *Self, child: *Element) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.orderedRemove(i);
                child.parent = null;
                break;
            }
        }
    }

    /// Find first child with matching tag
    pub fn find(self: *Self, path: []const u8) ?*Element {
        for (self.children.items) |child| {
            if (std.mem.eql(u8, child.tag, path)) {
                return child;
            }
        }
        return null;
    }

    /// Find all children with matching tag
    pub fn findall(self: *Self, path: []const u8) ![]*Element {
        var result: std.ArrayList(*Element) = .{};
        for (self.children.items) |child| {
            if (std.mem.eql(u8, child.tag, path)) {
                try result.append(self.allocator, child);
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Find text of first child with matching tag
    pub fn findtext(self: *Self, path: []const u8, default: ?[]const u8) ?[]const u8 {
        if (self.find(path)) |elem| {
            return elem.text orelse default;
        }
        return default;
    }

    /// Iterate over children
    pub fn iter(self: *Self, tag: ?[]const u8) ChildIterator {
        return ChildIterator{
            .element = self,
            .tag = tag,
            .index = 0,
        };
    }

    /// Get number of children
    pub fn len(self: *Self) usize {
        return self.children.items.len;
    }

    /// Create a subelement
    pub fn makeElement(self: *Self, tag: []const u8) !*Element {
        const child = try Element.init(self.allocator, tag);
        try self.append(child);
        return child;
    }

    /// Set text content
    pub fn setText(self: *Self, text: []const u8) !void {
        if (self.text) |t| self.allocator.free(t);
        self.text = try self.allocator.dupe(u8, text);
    }

    /// Set tail content
    pub fn setTail(self: *Self, text: []const u8) !void {
        if (self.tail) |t| self.allocator.free(t);
        self.tail = try self.allocator.dupe(u8, text);
    }
};

/// Iterator over element children
pub const ChildIterator = struct {
    element: *Element,
    tag: ?[]const u8,
    index: usize,

    pub fn next(self: *ChildIterator) ?*Element {
        while (self.index < self.element.children.items.len) {
            const child = self.element.children.items[self.index];
            self.index += 1;

            if (self.tag) |t| {
                if (std.mem.eql(u8, child.tag, t)) {
                    return child;
                }
            } else {
                return child;
            }
        }
        return null;
    }
};
