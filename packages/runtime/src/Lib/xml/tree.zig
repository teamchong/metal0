//! ElementTree - XML element tree wrapper with file I/O
//!
//! This module provides the ElementTree class for managing XML documents.

const std = @import("std");
const Element = @import("element.zig").Element;
const parser = @import("parser.zig");

/// ElementTree wrapper
pub const ElementTree = struct {
    allocator: std.mem.Allocator,
    root: ?*Element,

    pub fn init(allocator: std.mem.Allocator, root: ?*Element) ElementTree {
        return .{
            .allocator = allocator,
            .root = root,
        };
    }

    pub fn deinit(self: *ElementTree) void {
        if (self.root) |r| {
            r.deinit();
            self.allocator.destroy(r);
        }
    }

    pub fn getroot(self: *ElementTree) ?*Element {
        return self.root;
    }

    pub fn setroot(self: *ElementTree, root: *Element) void {
        self.root = root;
    }

    /// Parse XML from string
    pub fn parse(self: *ElementTree, source: []const u8) !void {
        var pos: usize = 0;

        // Skip XML declaration if present
        if (std.mem.startsWith(u8, source, "<?xml")) {
            if (std.mem.indexOf(u8, source, "?>")) |end| {
                pos = end + 2;
            }
        }

        // Skip whitespace
        while (pos < source.len and std.ascii.isWhitespace(source[pos])) {
            pos += 1;
        }

        // Parse root element
        if (pos < source.len and source[pos] == '<') {
            self.root = try parser.parseElement(self.allocator, source, &pos);
        }
    }

    /// Write XML to string
    pub fn tostring(self: *ElementTree, allocator: std.mem.Allocator) ![]u8 {
        if (self.root) |root| {
            return elementToString(allocator, root, 0);
        }
        return allocator.dupe(u8, "");
    }

    /// Write XML to file
    pub fn write(self: *ElementTree, file: std.fs.File, encoding: ?[]const u8, xml_declaration: bool) !void {
        _ = encoding;
        var writer = file.writer();

        if (xml_declaration) {
            try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        }

        if (self.root) |root| {
            try writeElement(writer, root, 0);
        }
    }
};

/// Convert element to string (helper)
fn elementToString(allocator: std.mem.Allocator, elem: *Element, depth: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Indent
    for (0..depth) |_| {
        try result.appendSlice("  ");
    }

    // Start tag
    try result.append('<');
    try result.appendSlice(elem.tag);

    // Attributes
    var iter = elem.attrib.iterator();
    while (iter.next()) |entry| {
        try result.append(' ');
        try result.appendSlice(entry.key_ptr.*);
        try result.appendSlice("=\"");
        try result.appendSlice(entry.value_ptr.*);
        try result.append('"');
    }

    if (elem.children.items.len == 0 and elem.text == null) {
        // Self-closing
        try result.appendSlice("/>\n");
    } else {
        try result.append('>');

        // Text
        if (elem.text) |text| {
            try result.appendSlice(text);
        }

        // Children
        if (elem.children.items.len > 0) {
            try result.append('\n');
            for (elem.children.items) |child| {
                const child_str = try elementToString(allocator, child, depth + 1);
                defer allocator.free(child_str);
                try result.appendSlice(child_str);
            }

            // Indent closing tag
            for (0..depth) |_| {
                try result.appendSlice("  ");
            }
        }

        // End tag
        try result.appendSlice("</");
        try result.appendSlice(elem.tag);
        try result.appendSlice(">\n");
    }

    // Tail
    if (elem.tail) |tail| {
        try result.appendSlice(tail);
    }

    return result.toOwnedSlice();
}

/// Write element to writer (helper)
fn writeElement(writer: anytype, elem: *Element, depth: usize) !void {
    // Indent
    for (0..depth) |_| {
        try writer.writeAll("  ");
    }

    // Start tag
    try writer.writeByte('<');
    try writer.writeAll(elem.tag);

    // Attributes
    var iter = elem.attrib.iterator();
    while (iter.next()) |entry| {
        try writer.writeByte(' ');
        try writer.writeAll(entry.key_ptr.*);
        try writer.writeAll("=\"");
        try writer.writeAll(entry.value_ptr.*);
        try writer.writeByte('"');
    }

    if (elem.children.items.len == 0 and elem.text == null) {
        try writer.writeAll("/>\n");
    } else {
        try writer.writeByte('>');

        if (elem.text) |text| {
            try writer.writeAll(text);
        }

        if (elem.children.items.len > 0) {
            try writer.writeByte('\n');
            for (elem.children.items) |child| {
                try writeElement(writer, child, depth + 1);
            }
            for (0..depth) |_| {
                try writer.writeAll("  ");
            }
        }

        try writer.writeAll("</");
        try writer.writeAll(elem.tag);
        try writer.writeAll(">\n");
    }
}

/// Parse XML file to ElementTree
pub fn parseFile(allocator: std.mem.Allocator, filename: []const u8) !ElementTree {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    const root = try parser.parseXML(allocator, content);
    return ElementTree.init(allocator, root);
}
