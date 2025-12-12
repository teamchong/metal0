//! XML Parser - functions for parsing XML from strings
//!
//! This module provides low-level XML parsing utilities.

const std = @import("std");
const Element = @import("element.zig").Element;

/// Parse XML string to Element
pub fn parseXML(allocator: std.mem.Allocator, text: []const u8) !*Element {
    // Simple XML parser
    var stack: std.ArrayList(*Element) = .{};
    defer stack.deinit(allocator);

    var root: ?*Element = null;
    var current: ?*Element = null;
    var i: usize = 0;

    while (i < text.len) {
        if (text[i] == '<') {
            if (i + 1 < text.len and text[i + 1] == '/') {
                // End tag
                const end = std.mem.indexOfScalarPos(u8, text, i + 2, '>') orelse break;
                i = end + 1;
                if (stack.items.len > 0) {
                    _ = stack.pop();
                    current = if (stack.items.len > 0) stack.items[stack.items.len - 1] else null;
                }
            } else if (i + 1 < text.len and text[i + 1] == '?') {
                // XML declaration
                const end = std.mem.indexOf(u8, text[i..], "?>") orelse break;
                i = i + end + 2;
            } else if (i + 1 < text.len and text[i + 1] == '!') {
                // Comment or DOCTYPE
                if (i + 4 < text.len and std.mem.eql(u8, text[i + 2 .. i + 4], "--")) {
                    const end = std.mem.indexOf(u8, text[i..], "-->") orelse break;
                    i = i + end + 3;
                } else {
                    const end = std.mem.indexOfScalarPos(u8, text, i + 2, '>') orelse break;
                    i = end + 1;
                }
            } else {
                // Start tag
                const end = std.mem.indexOfScalarPos(u8, text, i + 1, '>') orelse break;
                const tag_content = text[i + 1 .. end];

                // Check for self-closing
                const self_closing = tag_content.len > 0 and tag_content[tag_content.len - 1] == '/';
                const tag_end = if (self_closing) tag_content.len - 1 else tag_content.len;

                // Parse tag name
                var tag_name_end: usize = 0;
                for (tag_content[0..tag_end], 0..) |c, idx| {
                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        tag_name_end = idx;
                        break;
                    }
                    tag_name_end = idx + 1;
                }

                const tag_name = tag_content[0..tag_name_end];
                const elem = try Element.init(allocator, tag_name);

                // Parse attributes (simplified)
                if (tag_name_end < tag_end) {
                    const attrs_str = tag_content[tag_name_end..tag_end];
                    try parseAttributes(elem, attrs_str);
                }

                if (current) |cur| {
                    try cur.append(elem);
                } else {
                    root = elem;
                }

                if (!self_closing) {
                    try stack.append(allocator, elem);
                    current = elem;
                }

                i = end + 1;
            }
        } else {
            // Text content
            const start = i;
            while (i < text.len and text[i] != '<') {
                i += 1;
            }

            if (current) |cur| {
                const text_content = std.mem.trim(u8, text[start..i], " \t\n\r");
                if (text_content.len > 0) {
                    try cur.setText(text_content);
                }
            }
        }
    }

    return root orelse error.ParseError;
}

/// Parse attributes from attribute string
pub fn parseAttributes(elem: *Element, attrs_str: []const u8) !void {
    var i: usize = 0;
    while (i < attrs_str.len) {
        // Skip whitespace
        while (i < attrs_str.len and (attrs_str[i] == ' ' or attrs_str[i] == '\t' or attrs_str[i] == '\n')) {
            i += 1;
        }
        if (i >= attrs_str.len) break;

        // Find attribute name
        const name_start = i;
        while (i < attrs_str.len and attrs_str[i] != '=' and attrs_str[i] != ' ') {
            i += 1;
        }
        const name = attrs_str[name_start..i];
        if (name.len == 0) break;

        // Skip to =
        while (i < attrs_str.len and attrs_str[i] != '=') {
            i += 1;
        }
        if (i >= attrs_str.len) break;
        i += 1; // Skip =

        // Skip whitespace
        while (i < attrs_str.len and (attrs_str[i] == ' ' or attrs_str[i] == '\t')) {
            i += 1;
        }
        if (i >= attrs_str.len) break;

        // Parse value
        if (attrs_str[i] == '"' or attrs_str[i] == '\'') {
            const quote = attrs_str[i];
            i += 1;
            const value_start = i;
            while (i < attrs_str.len and attrs_str[i] != quote) {
                i += 1;
            }
            const value = attrs_str[value_start..i];
            i += 1; // Skip closing quote

            try elem.set(name, value);
        }
    }
}

/// Parse element recursively (alternative parser for ElementTree.parse)
pub fn parseElement(allocator: std.mem.Allocator, source: []const u8, pos: *usize) !*Element {
    // Skip '<'
    pos.* += 1;

    // Skip whitespace
    while (pos.* < source.len and std.ascii.isWhitespace(source[pos.*])) {
        pos.* += 1;
    }

    // Get tag name
    const tag_start = pos.*;
    while (pos.* < source.len and !std.ascii.isWhitespace(source[pos.*]) and
        source[pos.*] != '>' and source[pos.*] != '/')
    {
        pos.* += 1;
    }
    const tag = source[tag_start..pos.*];

    var elem = try Element.init(allocator, tag);
    errdefer elem.deinit();

    // Parse attributes
    while (pos.* < source.len and source[pos.*] != '>' and source[pos.*] != '/') {
        // Skip whitespace
        while (pos.* < source.len and std.ascii.isWhitespace(source[pos.*])) {
            pos.* += 1;
        }

        if (pos.* >= source.len or source[pos.*] == '>' or source[pos.*] == '/') break;

        // Parse attribute name
        const attr_start = pos.*;
        while (pos.* < source.len and source[pos.*] != '=' and !std.ascii.isWhitespace(source[pos.*])) {
            pos.* += 1;
        }
        const attr_name = source[attr_start..pos.*];

        // Skip to '='
        while (pos.* < source.len and source[pos.*] != '=') {
            pos.* += 1;
        }
        pos.* += 1; // Skip '='

        // Skip whitespace and quote
        while (pos.* < source.len and (std.ascii.isWhitespace(source[pos.*]) or source[pos.*] == '"' or source[pos.*] == '\'')) {
            pos.* += 1;
        }

        // Parse attribute value
        const val_start = pos.*;
        while (pos.* < source.len and source[pos.*] != '"' and source[pos.*] != '\'') {
            pos.* += 1;
        }
        const attr_value = source[val_start..pos.*];

        // Skip closing quote
        if (pos.* < source.len) pos.* += 1;

        try elem.set(attr_name, attr_value);
    }

    // Check for self-closing tag
    if (pos.* < source.len and source[pos.*] == '/') {
        pos.* += 1;
        if (pos.* < source.len and source[pos.*] == '>') pos.* += 1;
        return elem;
    }

    // Skip '>'
    if (pos.* < source.len and source[pos.*] == '>') {
        pos.* += 1;
    }

    // Parse content and children
    var text_buf: std.ArrayList(u8) = .{};
    defer text_buf.deinit(allocator);

    while (pos.* < source.len) {
        if (source[pos.*] == '<') {
            // Save accumulated text
            if (text_buf.items.len > 0) {
                elem.text = try allocator.dupe(u8, text_buf.items);
                text_buf.clearRetainingCapacity();
            }

            // Check for closing tag
            if (pos.* + 1 < source.len and source[pos.* + 1] == '/') {
                // Find end of closing tag
                while (pos.* < source.len and source[pos.*] != '>') {
                    pos.* += 1;
                }
                if (pos.* < source.len) pos.* += 1;
                break;
            }

            // Parse child element
            const child = try parseElement(allocator, source, pos);
            try elem.append(child);
        } else {
            try text_buf.append(allocator, source[pos.*]);
            pos.* += 1;
        }
    }

    return elem;
}
