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
