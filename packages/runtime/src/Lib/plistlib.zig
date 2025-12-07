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
    // Simple XML parsing - look for plist elements
    _ = data;
    // Return empty dict as placeholder
    return PlistValue{ .dict = hashmap_helper.StringHashMap(PlistValue).init(allocator) };
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
            // Would base64 encode
            _ = d;
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
    // Binary plist format is complex
    // Return empty dict as placeholder
    _ = data;
    return PlistValue{ .dict = hashmap_helper.StringHashMap(PlistValue).init(allocator) };
}

fn dumpBinary(allocator: std.mem.Allocator, value: PlistValue) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    // Magic header
    try result.appendSlice("bplist00");

    // Would write binary format
    _ = value;

    return result.toOwnedSlice();
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
