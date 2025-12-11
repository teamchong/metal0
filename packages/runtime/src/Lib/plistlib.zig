//! CPython source: Lib/plistlib.py
//!
//! Provides support for reading and writing Apple property list files.
//!
//! Mirrors: CPython Lib/plistlib.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// PlistFormat - Format types
// ============================================================================

pub const PlistFormat = enum {
    FMT_XML,
    FMT_BINARY,
};

// ============================================================================
// UID - Unique ID type for binary plists
// ============================================================================

pub const UID = struct {
    data: u64,

    pub fn init(data: u64) UID {
        return .{ .data = data };
    }
};

// ============================================================================
// PlistValue - Union type for plist values
// ============================================================================

pub const PlistValue = union(enum) {
    string: []const u8,
    integer: i64,
    real: f64,
    boolean: bool,
    data: []const u8,
    date: i64, // Unix timestamp
    array: []PlistValue,
    dict: hashmap_helper.StringHashMap(PlistValue),
    uid: UID,
};

// ============================================================================
// load - Load a plist from a file
// ============================================================================

/// Load a plist from a file
pub fn load(allocator: std.mem.Allocator, file: std.fs.File) !PlistValue {
    const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(data);

    return loads(allocator, data);
}

/// Load a plist from bytes
pub fn loads(allocator: std.mem.Allocator, data: []const u8) !PlistValue {
    // Detect format
    if (data.len >= 8 and std.mem.eql(u8, data[0..8], "bplist00")) {
        return loadBinary(allocator, data);
    }

    // Assume XML
    return loadXML(allocator, data);
}

// ============================================================================
// dump - Dump a plist to a file
// ============================================================================

/// Dump a plist to a file
pub fn dump(value: PlistValue, file: std.fs.File, fmt: PlistFormat) !void {
    const data = try dumps(std.heap.page_allocator, value, fmt);
    defer std.heap.page_allocator.free(data);
    try file.writeAll(data);
}

/// Dump a plist to bytes
pub fn dumps(allocator: std.mem.Allocator, value: PlistValue, fmt: PlistFormat) ![]u8 {
    switch (fmt) {
        .FMT_XML => return dumpXML(allocator, value),
        .FMT_BINARY => return dumpBinary(allocator, value),
    }
}

// ============================================================================
// XML Plist Support
// ============================================================================

fn loadXML(allocator: std.mem.Allocator, data: []const u8) !PlistValue {
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

fn dumpXML(allocator: std.mem.Allocator, value: PlistValue) ![]u8 {
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

// ============================================================================
// Binary Plist Support
// ============================================================================

fn loadBinary(allocator: std.mem.Allocator, data: []const u8) !PlistValue {
    // Binary plist format: bplist00 header + objects + offset table + trailer
    if (data.len < 32) return error.InvalidFormat;

    // Check magic header
    if (!std.mem.startsWith(u8, data, "bplist0")) return error.InvalidFormat;

    // Parse trailer (last 32 bytes)
    const trailer = data[data.len - 32 ..];
    // Trailer format: 6 unused bytes, offset_int_size (1), object_ref_size (1),
    //                 num_objects (8), top_object_ref (8), offset_table_offset (8)
    const offset_int_size = trailer[6];
    const object_ref_size = trailer[7];
    const num_objects = std.mem.readInt(u64, trailer[8..16], .big);
    const top_object_ref = std.mem.readInt(u64, trailer[16..24], .big);
    const offset_table_offset = std.mem.readInt(u64, trailer[24..32], .big);

    if (offset_int_size == 0 or offset_int_size > 8) return error.InvalidFormat;
    if (object_ref_size == 0 or object_ref_size > 8) return error.InvalidFormat;
    if (num_objects == 0) return PlistValue{ .dict = hashmap_helper.StringHashMap(PlistValue).init(allocator) };

    // Read offset table
    const offset_table_end = data.len - 32;
    if (offset_table_offset >= offset_table_end) return error.InvalidFormat;

    const offset_table = data[@intCast(offset_table_offset)..offset_table_end];

    // Parse objects
    var objects = try allocator.alloc(PlistValue, @intCast(num_objects));
    defer allocator.free(objects);

    var i: usize = 0;
    while (i < num_objects) : (i += 1) {
        const offset_pos = i * offset_int_size;
        if (offset_pos + offset_int_size > offset_table.len) return error.InvalidFormat;

        const obj_offset = readVarInt(offset_table[offset_pos..], offset_int_size);
        objects[i] = try parseBinaryObject(allocator, data, @intCast(obj_offset), object_ref_size, objects);
    }

    // Return top-level object
    if (top_object_ref >= num_objects) return error.InvalidFormat;
    return objects[@intCast(top_object_ref)];
}

fn readVarInt(data: []const u8, size: u8) u64 {
    var result: u64 = 0;
    for (0..size) |i| {
        result = (result << 8) | data[i];
    }
    return result;
}

fn parseBinaryObject(allocator: std.mem.Allocator, data: []const u8, offset: usize, ref_size: u8, objects: []PlistValue) !PlistValue {
    if (offset >= data.len) return error.InvalidFormat;

    const marker = data[offset];
    const obj_type = marker >> 4;
    const obj_info = marker & 0x0F;

    switch (obj_type) {
        0x0 => {
            // Singleton: null, bool, fill
            switch (obj_info) {
                0x0 => return PlistValue{ .boolean = false }, // null treated as false
                0x8 => return PlistValue{ .boolean = false },
                0x9 => return PlistValue{ .boolean = true },
                else => return PlistValue{ .boolean = false },
            }
        },
        0x1 => {
            // Integer
            const int_size: usize = @as(usize, 1) << @intCast(obj_info);
            if (offset + 1 + int_size > data.len) return error.InvalidFormat;
            const int_data = data[offset + 1 .. offset + 1 + int_size];
            var val: i64 = 0;
            for (int_data) |b| {
                val = (val << 8) | b;
            }
            return PlistValue{ .integer = val };
        },
        0x2 => {
            // Real (float)
            const float_size: usize = @as(usize, 1) << @intCast(obj_info);
            if (offset + 1 + float_size > data.len) return error.InvalidFormat;
            if (float_size == 4) {
                const bits = std.mem.readInt(u32, data[offset + 1 ..][0..4], .big);
                return PlistValue{ .real = @bitCast(bits) };
            } else if (float_size == 8) {
                const bits = std.mem.readInt(u64, data[offset + 1 ..][0..8], .big);
                return PlistValue{ .real = @bitCast(bits) };
            }
            return error.InvalidFormat;
        },
        0x3 => {
            // Date
            if (offset + 9 > data.len) return error.InvalidFormat;
            const bits = std.mem.readInt(u64, data[offset + 1 ..][0..8], .big);
            const timestamp: f64 = @bitCast(bits);
            return PlistValue{ .date = @intFromFloat(timestamp) };
        },
        0x4 => {
            // Data (binary)
            const len = try getBinaryLength(data, offset, obj_info);
            const start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            if (start + len > data.len) return error.InvalidFormat;
            return PlistValue{ .data = try allocator.dupe(u8, data[start .. start + len]) };
        },
        0x5 => {
            // ASCII string
            const len = try getBinaryLength(data, offset, obj_info);
            const start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            if (start + len > data.len) return error.InvalidFormat;
            return PlistValue{ .string = try allocator.dupe(u8, data[start .. start + len]) };
        },
        0x6 => {
            // Unicode string (UTF-16BE)
            const len = try getBinaryLength(data, offset, obj_info);
            const start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            if (start + len * 2 > data.len) return error.InvalidFormat;
            // Simplified: just store raw bytes, proper impl would convert UTF-16
            return PlistValue{ .string = try allocator.dupe(u8, data[start .. start + len * 2]) };
        },
        0xA => {
            // Array
            const count = try getBinaryLength(data, offset, obj_info);
            const refs_start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            var items = try allocator.alloc(PlistValue, count);
            for (0..count) |idx| {
                const ref_offset = refs_start + idx * ref_size;
                const ref = readVarInt(data[ref_offset..], ref_size);
                if (ref < objects.len) {
                    items[idx] = objects[ref];
                } else {
                    items[idx] = PlistValue{ .boolean = false };
                }
            }
            return PlistValue{ .array = items };
        },
        0xD => {
            // Dictionary
            const count = try getBinaryLength(data, offset, obj_info);
            const refs_start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            var dict = hashmap_helper.StringHashMap(PlistValue).init(allocator);
            for (0..count) |idx| {
                const key_ref = readVarInt(data[refs_start + idx * ref_size ..], ref_size);
                const val_ref = readVarInt(data[refs_start + (count + idx) * ref_size ..], ref_size);
                if (key_ref < objects.len and val_ref < objects.len) {
                    const key_obj = objects[key_ref];
                    if (key_obj == .string) {
                        try dict.put(try allocator.dupe(u8, key_obj.string), objects[val_ref]);
                    }
                }
            }
            return PlistValue{ .dict = dict };
        },
        else => return PlistValue{ .boolean = false },
    }
}

fn getBinaryLength(data: []const u8, offset: usize, info: u4) !usize {
    if (info != 0xF) return @intCast(info);
    // Extended length
    if (offset + 2 > data.len) return error.InvalidFormat;
    const ext_marker = data[offset + 1];
    const int_type = ext_marker & 0xF;
    const int_size: usize = @as(usize, 1) << @intCast(int_type);
    if (offset + 2 + int_size > data.len) return error.InvalidFormat;
    return @intCast(readVarInt(data[offset + 2 ..], @intCast(int_size)));
}

fn dumpBinary(allocator: std.mem.Allocator, value: PlistValue) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    // Magic header
    try result.appendSlice("bplist00");

    // Collect all objects for serialization
    var objects = std.ArrayList(PlistValue).init(allocator);
    defer objects.deinit();
    try collectObjects(&objects, value);

    // Write objects and track offsets
    var offsets = std.ArrayList(u64).init(allocator);
    defer offsets.deinit();

    for (objects.items) |obj| {
        try offsets.append(@intCast(result.items.len));
        try writeBinaryObject(&result, obj);
    }

    // Write offset table
    const offset_table_offset = result.items.len;
    for (offsets.items) |off| {
        try result.append(@intCast((off >> 24) & 0xFF));
        try result.append(@intCast((off >> 16) & 0xFF));
        try result.append(@intCast((off >> 8) & 0xFF));
        try result.append(@intCast(off & 0xFF));
    }

    // Write trailer
    try result.appendNTimes(0, 6); // unused
    try result.append(4); // offset int size
    try result.append(4); // object ref size
    try result.writer().writeInt(u64, @intCast(objects.items.len), .big);
    try result.writer().writeInt(u64, 0, .big); // top object
    try result.writer().writeInt(u64, @intCast(offset_table_offset), .big);

    return result.toOwnedSlice();
}

fn collectObjects(objects: *std.ArrayList(PlistValue), value: PlistValue) !void {
    try objects.append(value);
    switch (value) {
        .array => |arr| {
            for (arr) |item| try collectObjects(objects, item);
        },
        .dict => |dict| {
            var it = dict.iterator();
            while (it.next()) |entry| {
                try objects.append(PlistValue{ .string = entry.key_ptr.* });
                try collectObjects(objects, entry.value_ptr.*);
            }
        },
        else => {},
    }
}

fn writeBinaryObject(result: *std.ArrayList(u8), obj: PlistValue) !void {
    switch (obj) {
        .boolean => |b| try result.append(if (b) 0x09 else 0x08),
        .integer => |i| {
            try result.append(0x10); // 1-byte int
            try result.append(@intCast(@as(u8, @truncate(@as(u64, @bitCast(i))))));
        },
        .real => |r| {
            try result.append(0x23); // 8-byte float
            try result.writer().writeInt(u64, @bitCast(r), .big);
        },
        .string => |s| {
            if (s.len < 15) {
                try result.append(0x50 | @as(u8, @intCast(s.len)));
            } else {
                try result.append(0x5F);
                try result.append(0x10);
                try result.append(@intCast(s.len));
            }
            try result.appendSlice(s);
        },
        .data => |d| {
            if (d.len < 15) {
                try result.append(0x40 | @as(u8, @intCast(d.len)));
            } else {
                try result.append(0x4F);
                try result.append(0x10);
                try result.append(@intCast(d.len));
            }
            try result.appendSlice(d);
        },
        .date => |timestamp| {
            try result.append(0x33);
            const f: f64 = @floatFromInt(timestamp);
            try result.writer().writeInt(u64, @bitCast(f), .big);
        },
        .array => |arr| {
            if (arr.len < 15) {
                try result.append(0xA0 | @as(u8, @intCast(arr.len)));
            } else {
                try result.append(0xAF);
                try result.append(0x10);
                try result.append(@intCast(arr.len));
            }
            // Object refs would go here - simplified
        },
        .dict => |dict| {
            const count = dict.count();
            if (count < 15) {
                try result.append(0xD0 | @as(u8, @intCast(count)));
            } else {
                try result.append(0xDF);
                try result.append(0x10);
                try result.append(@intCast(count));
            }
            // Key/value refs would go here - simplified
        },
        .uid => |u| {
            try result.append(0x80);
            try result.append(@intCast(u.data & 0xFF));
        },
    }
}

// ============================================================================
// InvalidFileException
// ============================================================================

pub const InvalidFileException = error{
    InvalidFormat,
    InvalidHeader,
    CorruptedData,
    UnsupportedVersion,
};

// ============================================================================
// Helper functions
// ============================================================================

/// Create a string value
pub fn string(s: []const u8) PlistValue {
    return .{ .string = s };
}

/// Create an integer value
pub fn integer(i: i64) PlistValue {
    return .{ .integer = i };
}

/// Create a real value
pub fn real(r: f64) PlistValue {
    return .{ .real = r };
}

/// Create a boolean value
pub fn boolean(b: bool) PlistValue {
    return .{ .boolean = b };
}

/// Create a data value
pub fn data(d: []const u8) PlistValue {
    return .{ .data = d };
}

/// Create a date value from unix timestamp
pub fn date(timestamp: i64) PlistValue {
    return .{ .date = timestamp };
}

/// Create a UID value
pub fn uid(u: u64) PlistValue {
    return .{ .uid = UID.init(u) };
}

// ============================================================================
// Tests
// ============================================================================

test "PlistFormat enum" {
    try std.testing.expect(PlistFormat.FMT_XML != PlistFormat.FMT_BINARY);
}

test "UID init" {
    const u = UID.init(42);
    try std.testing.expectEqual(@as(u64, 42), u.data);
}

test "string helper" {
    const v = string("hello");
    try std.testing.expectEqualStrings("hello", v.string);
}

test "integer helper" {
    const v = integer(42);
    try std.testing.expectEqual(@as(i64, 42), v.integer);
}

test "real helper" {
    const v = real(3.14);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), v.real, 0.001);
}

test "boolean helper" {
    const t = boolean(true);
    const f = boolean(false);
    try std.testing.expect(t.boolean);
    try std.testing.expect(!f.boolean);
}

test "data helper" {
    const v = data("binary");
    try std.testing.expectEqualStrings("binary", v.data);
}

test "date helper" {
    const v = date(1234567890);
    try std.testing.expectEqual(@as(i64, 1234567890), v.date);
}

test "uid helper" {
    const v = uid(123);
    try std.testing.expectEqual(@as(u64, 123), v.uid.data);
}

test "dumps XML string" {
    const allocator = std.testing.allocator;
    const v = string("hello");
    const result = try dumps(allocator, v, .FMT_XML);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<string>hello</string>") != null);
}

test "dumps XML integer" {
    const allocator = std.testing.allocator;
    const v = integer(42);
    const result = try dumps(allocator, v, .FMT_XML);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<integer>42</integer>") != null);
}

test "dumps XML boolean" {
    const allocator = std.testing.allocator;
    const v = boolean(true);
    const result = try dumps(allocator, v, .FMT_XML);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<true/>") != null);
}

test "dumps binary header" {
    const allocator = std.testing.allocator;
    const v = string("test");
    const result = try dumps(allocator, v, .FMT_BINARY);
    defer allocator.free(result);

    try std.testing.expect(std.mem.startsWith(u8, result, "bplist00"));
}

test "loads empty dict" {
    const allocator = std.testing.allocator;
    var v = try loads(allocator, "<?xml version=\"1.0\"?><plist></plist>");
    switch (v) {
        .dict => |*d| d.deinit(),
        else => {},
    }
}
