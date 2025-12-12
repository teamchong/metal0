//! XML Builder - helper functions for creating XML elements
//!
//! This module provides convenience functions for building XML documents.

const std = @import("std");
const Element = @import("element.zig").Element;
const parser = @import("parser.zig");

/// Parse XML string to Element
pub fn fromstring(allocator: std.mem.Allocator, text: []const u8) !*Element {
    return parser.parseXML(allocator, text);
}

/// Convert element to string
pub fn tostring(allocator: std.mem.Allocator, elem: *Element) ![]u8 {
    return elementToString(allocator, elem, 0);
}

/// Create a new element
pub fn createElement(allocator: std.mem.Allocator, tag: []const u8) !*Element {
    return Element.init(allocator, tag);
}

/// Create a subelement
pub fn SubElement(parent: *Element, tag: []const u8) !*Element {
    return parent.makeElement(tag);
}

/// Comment element
pub fn Comment(allocator: std.mem.Allocator, text: []const u8) !*Element {
    const elem = try Element.init(allocator, "!--");
    try elem.setText(text);
    return elem;
}

/// ProcessingInstruction element
pub fn ProcessingInstruction(allocator: std.mem.Allocator, target: []const u8, text: ?[]const u8) !*Element {
    const elem = try Element.init(allocator, target);
    if (text) |t| try elem.setText(t);
    return elem;
}

/// Check if element is comment
pub fn iselement(elem: *Element) bool {
    _ = elem;
    return true;
}

/// Convert element to string (helper)
fn elementToString(allocator: std.mem.Allocator, elem: *Element, depth: usize) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    // Indent
    for (0..depth) |_| {
        try result.appendSlice(allocator, "  ");
    }

    // Start tag
    try result.append(allocator, '<');
    try result.appendSlice(allocator, elem.tag);

    // Attributes
    var iter = elem.attrib.iterator();
    while (iter.next()) |entry| {
        try result.append(allocator, ' ');
        try result.appendSlice(allocator, entry.key_ptr.*);
        try result.appendSlice(allocator, "=\"");
        try result.appendSlice(allocator, entry.value_ptr.*);
        try result.append(allocator, '"');
    }

    if (elem.children.items.len == 0 and elem.text == null) {
        // Self-closing
        try result.appendSlice(allocator, "/>\n");
    } else {
        try result.append(allocator, '>');

        // Text
        if (elem.text) |text| {
            try result.appendSlice(allocator, text);
        }

        // Children
        if (elem.children.items.len > 0) {
            try result.append(allocator, '\n');
            for (elem.children.items) |child| {
                const child_str = try elementToString(allocator, child, depth + 1);
                defer allocator.free(child_str);
                try result.appendSlice(allocator, child_str);
            }

            // Indent closing tag
            for (0..depth) |_| {
                try result.appendSlice(allocator, "  ");
            }
        }

        // End tag
        try result.appendSlice(allocator, "</");
        try result.appendSlice(allocator, elem.tag);
        try result.appendSlice(allocator, ">\n");
    }

    // Tail
    if (elem.tail) |tail| {
        try result.appendSlice(allocator, tail);
    }

    return result.toOwnedSlice(allocator);
}
