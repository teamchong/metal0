//! CPython source: Lib/plistlib.py
//!
//! Provides support for reading and writing Apple property list files.
//!
//! Mirrors: CPython Lib/plistlib.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");

// Import modules
pub const types = @import("plistlib/types.zig");
pub const xml = @import("plistlib/xml.zig");
pub const binary = @import("plistlib/binary.zig");
pub const helpers = @import("plistlib/helpers.zig");
pub const errors = @import("plistlib/errors.zig");

// Re-export types
pub const PlistFormat = types.PlistFormat;
pub const UID = types.UID;
pub const PlistValue = types.PlistValue;
pub const InvalidFileException = errors.InvalidFileException;

// Re-export helper functions
pub const string = helpers.string;
pub const integer = helpers.integer;
pub const real = helpers.real;
pub const boolean = helpers.boolean;
pub const data = helpers.data;
pub const date = helpers.date;
pub const uid = helpers.uid;

// ============================================================================
// load - Load a plist from a file
// ============================================================================

/// Load a plist from a file
pub fn load(allocator: std.mem.Allocator, file: std.fs.File) !PlistValue {
    const data_bytes = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(data_bytes);

    return loads(allocator, data_bytes);
}

/// Load a plist from bytes
pub fn loads(allocator: std.mem.Allocator, data_bytes: []const u8) !PlistValue {
    // Detect format
    if (data_bytes.len >= 8 and std.mem.eql(u8, data_bytes[0..8], "bplist00")) {
        return binary.loadBinary(allocator, data_bytes);
    }

    // Assume XML
    return xml.loadXML(allocator, data_bytes);
}

// ============================================================================
// dump - Dump a plist to a file
// ============================================================================

/// Dump a plist to a file
pub fn dump(value: PlistValue, file: std.fs.File, fmt: PlistFormat) !void {
    const data_bytes = try dumps(allocator_helper.fast_allocator, value, fmt);
    defer allocator_helper.fast_allocator.free(data_bytes);
    try file.writeAll(data_bytes);
}

/// Dump a plist to bytes
pub fn dumps(allocator: std.mem.Allocator, value: PlistValue, fmt: PlistFormat) ![]u8 {
    switch (fmt) {
        .FMT_XML => return xml.dumpXML(allocator, value),
        .FMT_BINARY => return binary.dumpBinary(allocator, value),
    }
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
