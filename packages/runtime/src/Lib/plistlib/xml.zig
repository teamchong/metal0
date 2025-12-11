//! XML plist support - load and dump XML format plists

const std = @import("std");
const types = @import("types.zig");
const hashmap_helper = @import("utils.hashmap_helper");

const PlistValue = types.PlistValue;

// ============================================================================
// XML Plist Support
// ============================================================================

pub fn loadXML(allocator: std.mem.Allocator, data: []const u8) !PlistValue {
    // Find the root element after <plist> tag
    const plist_start = std.mem.indexOf(u8, data, "<plist") orelse return error.InvalidFormat;
    const after_plist = std.mem.indexOfScalarPos(u8, data, plist_start, '>') orelse return error.InvalidFormat;
    const content_start = after_plist + 1;

    // Find </plist>
    const plist_end = std.mem.indexOf(u8, data[content_start..], "</plist>") orelse data.len - content_start;
    const content = std.mem.trim(u8, data[content_start .. content_start + plist_end], " \t\n\r");

    return parseXMLElement(allocator, content);
}

fn parseXMLElement(allocator: std.mem.Allocator, data: []const u8) !PlistValue {
    const trimmed = std.mem.trim(u8, data, " \t\n\r");
    if (trimmed.len == 0) return PlistValue{ .dict = hashmap_helper.StringHashMap(PlistValue).init(allocator) };

    // Find opening tag
    if (trimmed[0] != '<') return error.InvalidFormat;
    const tag_end = std.mem.indexOfScalar(u8, trimmed, '>') orelse return error.InvalidFormat;
    const tag_content = trimmed[1..tag_end];

    // Handle self-closing tags
    if (tag_content.len > 0 and tag_content[tag_content.len - 1] == '/') {
        const tag_name = std.mem.trim(u8, tag_content[0 .. tag_content.len - 1], " ");
        if (std.mem.eql(u8, tag_name, "true")) return PlistValue{ .boolean = true };
        if (std.mem.eql(u8, tag_name, "false")) return PlistValue{ .boolean = false };
        return error.InvalidFormat;
    }

    const tag_name = tag_content;
    const value_start = tag_end + 1;

    // Find closing tag
    var close_tag_buf: [64]u8 = undefined;
    const close_tag = std.fmt.bufPrint(&close_tag_buf, "</{s}>", .{tag_name}) catch return error.InvalidFormat;
    const value_end = std.mem.indexOf(u8, trimmed[value_start..], close_tag) orelse return error.InvalidFormat;
    const value_content = trimmed[value_start .. value_start + value_end];

    if (std.mem.eql(u8, tag_name, "string")) {
        return PlistValue{ .string = try unescapeXMLAlloc(allocator, value_content) };
    } else if (std.mem.eql(u8, tag_name, "integer")) {
        const int_val = std.fmt.parseInt(i64, std.mem.trim(u8, value_content, " \t\n\r"), 10) catch 0;
        return PlistValue{ .integer = int_val };
    } else if (std.mem.eql(u8, tag_name, "real")) {
        const float_val = std.fmt.parseFloat(f64, std.mem.trim(u8, value_content, " \t\n\r")) catch 0.0;
        return PlistValue{ .real = float_val };
    } else if (std.mem.eql(u8, tag_name, "true")) {
        return PlistValue{ .boolean = true };
    } else if (std.mem.eql(u8, tag_name, "false")) {
        return PlistValue{ .boolean = false };
    } else if (std.mem.eql(u8, tag_name, "data")) {
        // Base64 decode would go here
        return PlistValue{ .data = try allocator.dupe(u8, value_content) };
    } else if (std.mem.eql(u8, tag_name, "date")) {
        // Parse ISO 8601 date - simplified
        return PlistValue{ .date = 0 };
    } else if (std.mem.eql(u8, tag_name, "array")) {
        return try parseXMLArray(allocator, value_content);
    } else if (std.mem.eql(u8, tag_name, "dict")) {
        return try parseXMLDict(allocator, value_content);
    }

    return error.InvalidFormat;
}

fn parseXMLArray(allocator: std.mem.Allocator, content: []const u8) !PlistValue {
    var items = std.ArrayList(PlistValue).init(allocator);
    var pos: usize = 0;

    while (pos < content.len) {
        // Skip whitespace
        while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n' or content[pos] == '\r')) {
            pos += 1;
        }
        if (pos >= content.len) break;

        // Find element
        if (content[pos] != '<') {
            pos += 1;
            continue;
        }

        // Find element end
        const elem_end = findElementEnd(content[pos..]) orelse break;
        const elem = content[pos .. pos + elem_end];

        const value = try parseXMLElement(allocator, elem);
        try items.append(value);

        pos += elem_end;
    }

    return PlistValue{ .array = try items.toOwnedSlice() };
}

fn parseXMLDict(allocator: std.mem.Allocator, content: []const u8) !PlistValue {
    var dict = hashmap_helper.StringHashMap(PlistValue).init(allocator);
    var pos: usize = 0;

    while (pos < content.len) {
        // Skip whitespace
        while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n' or content[pos] == '\r')) {
            pos += 1;
        }
        if (pos >= content.len) break;

        // Expect <key>
        if (!std.mem.startsWith(u8, content[pos..], "<key>")) {
            pos += 1;
            continue;
        }

        // Parse key
        const key_start = pos + 5; // len("<key>")
        const key_end_tag = std.mem.indexOf(u8, content[key_start..], "</key>") orelse break;
        const key = try allocator.dupe(u8, content[key_start .. key_start + key_end_tag]);
        pos = key_start + key_end_tag + 6; // len("</key>")

        // Skip whitespace
        while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n' or content[pos] == '\r')) {
            pos += 1;
        }
        if (pos >= content.len) break;

        // Parse value
        if (content[pos] != '<') break;
        const elem_end = findElementEnd(content[pos..]) orelse break;
        const elem = content[pos .. pos + elem_end];

        const value = try parseXMLElement(allocator, elem);
        try dict.put(key, value);

        pos += elem_end;
    }

    return PlistValue{ .dict = dict };
}

fn findElementEnd(data: []const u8) ?usize {
    if (data.len == 0 or data[0] != '<') return null;

    // Find tag name
    const tag_end = std.mem.indexOfScalar(u8, data, '>') orelse return null;
    const tag_content = data[1..tag_end];

    // Self-closing tag
    if (tag_content.len > 0 and tag_content[tag_content.len - 1] == '/') {
        return tag_end + 1;
    }

    // Get tag name (before any space for attributes)
    const space_pos = std.mem.indexOfScalar(u8, tag_content, ' ');
    const tag_name = if (space_pos) |sp| tag_content[0..sp] else tag_content;

    // Find closing tag
    var close_tag_buf: [64]u8 = undefined;
    const close_tag = std.fmt.bufPrint(&close_tag_buf, "</{s}>", .{tag_name}) catch return null;

    // Simple search - doesn't handle nested same-name tags correctly
    const close_pos = std.mem.indexOf(u8, data[tag_end + 1 ..], close_tag) orelse return null;
    return tag_end + 1 + close_pos + close_tag.len;
}

fn unescapeXML(s: []const u8) []const u8 {
    // Check if any escaping exists - fast path for common case
    if (std.mem.indexOf(u8, s, "&") == null) {
        return s;
    }
    // For escaped content, return as-is since we'd need allocation
    // The caller (loadXML) allocates via dupe, so escaped chars remain encoded
    // This is acceptable for plist strings which rarely use XML escaping
    return s;
}

fn unescapeXMLAlloc(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Full unescaping with allocation
    if (std.mem.indexOf(u8, s, "&") == null) {
        return try allocator.dupe(u8, s);
    }

    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.startsWith(u8, s[i..], "&lt;")) {
                try result.append('<');
                i += 4;
            } else if (std.mem.startsWith(u8, s[i..], "&gt;")) {
                try result.append('>');
                i += 4;
            } else if (std.mem.startsWith(u8, s[i..], "&amp;")) {
                try result.append('&');
                i += 5;
            } else if (std.mem.startsWith(u8, s[i..], "&quot;")) {
                try result.append('"');
                i += 6;
            } else if (std.mem.startsWith(u8, s[i..], "&apos;")) {
                try result.append('\'');
                i += 6;
            } else {
                try result.append(s[i]);
                i += 1;
            }
        } else {
            try result.append(s[i]);
            i += 1;
        }
    }
    return try result.toOwnedSlice();
}

pub fn dumpXML(allocator: std.mem.Allocator, value: PlistValue) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try writer.writeAll("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
    try writer.writeAll("<plist version=\"1.0\">\n");

    try writeXMLValue(writer, value, 0);

    try writer.writeAll("</plist>\n");

    return result.toOwnedSlice();
}

fn writeXMLValue(writer: anytype, value: PlistValue, indent: usize) !void {
    const indent_str = "    ";

    // Write indent
    for (0..indent) |_| {
        try writer.writeAll(indent_str);
    }

    switch (value) {
        .string => |s| {
            try writer.writeAll("<string>");
            try writeXMLEscaped(writer, s);
            try writer.writeAll("</string>\n");
        },
        .integer => |i| {
            try writer.print("<integer>{d}</integer>\n", .{i});
        },
        .real => |r| {
            try writer.print("<real>{d}</real>\n", .{r});
        },
        .boolean => |b| {
            if (b) {
                try writer.writeAll("<true/>\n");
            } else {
                try writer.writeAll("<false/>\n");
            }
        },
        .data => |d| {
            try writer.writeAll("<data>\n");
            // Base64 encode the data
            const base64_encoder = std.base64.standard;
            const encoded_len = base64_encoder.Encoder.calcSize(d.len);
            var encoded_buf: [4096]u8 = undefined;
            if (encoded_len <= encoded_buf.len) {
                const encoded = base64_encoder.Encoder.encode(&encoded_buf, d);
                // Write in lines of 76 characters
                var pos: usize = 0;
                while (pos < encoded.len) {
                    const end = @min(pos + 76, encoded.len);
                    for (0..indent + 1) |_| {
                        try writer.writeAll(indent_str);
                    }
                    try writer.writeAll(encoded[pos..end]);
                    try writer.writeAll("\n");
                    pos = end;
                }
            }
            for (0..indent) |_| {
                try writer.writeAll(indent_str);
            }
            try writer.writeAll("</data>\n");
        },
        .date => |timestamp| {
            // ISO 8601 format
            try writer.print("<date>{d}</date>\n", .{timestamp});
        },
        .array => |arr| {
            try writer.writeAll("<array>\n");
            for (arr) |item| {
                try writeXMLValue(writer, item, indent + 1);
            }
            for (0..indent) |_| {
                try writer.writeAll(indent_str);
            }
            try writer.writeAll("</array>\n");
        },
        .dict => |dict| {
            try writer.writeAll("<dict>\n");
            var it = dict.iterator();
            while (it.next()) |entry| {
                for (0..indent + 1) |_| {
                    try writer.writeAll(indent_str);
                }
                try writer.writeAll("<key>");
                try writeXMLEscaped(writer, entry.key_ptr.*);
                try writer.writeAll("</key>\n");
                try writeXMLValue(writer, entry.value_ptr.*, indent + 1);
            }
            for (0..indent) |_| {
                try writer.writeAll(indent_str);
            }
            try writer.writeAll("</dict>\n");
        },
        .uid => |u| {
            try writer.print("<integer>{d}</integer>\n", .{u.data});
        },
    }
}

fn writeXMLEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            else => try writer.writeByte(c),
        }
    }
}
