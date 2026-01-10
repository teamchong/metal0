//! xml.sax.xmlreader - XMLReader classes
//! Reference: cpython/Lib/xml/sax/xmlreader.py
//!
//! CPython __all__: ['XMLReader', 'IncrementalParser', 'Locator',
//!                   'InputSource', 'AttributesImpl', 'AttributesNSImpl']

const std = @import("std");
const sax = @import("../sax.zig");

// Re-export from parent (DRY)
pub const XMLReader = sax.XMLReader;
pub const Locator = sax.Locator;
pub const InputSource = sax.InputSource;
pub const ContentHandler = sax.ContentHandler;
pub const ErrorHandler = sax.ErrorHandler;
pub const DTDHandler = sax.DTDHandler;
pub const EntityResolver = sax.EntityResolver;

// ============================================================================
// IncrementalParser
// ============================================================================

/// Incremental parser interface
/// CPython: class IncrementalParser(XMLReader)
pub const IncrementalParser = struct {
    const Self = @This();

    base: XMLReader,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = XMLReader.init(allocator),
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.base.allocator);
    }

    /// Feed data to parser
    pub fn feed(self: *Self, data: []const u8) !void {
        try self.buffer.appendSlice(self.base.allocator, data);
    }

    /// Close parser and process remaining data
    pub fn close(self: *Self) !void {
        try self.base.parse(self.buffer.items);
        self.buffer.clearRetainingCapacity();
    }

    /// Reset parser
    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }
};

// ============================================================================
// AttributesImpl
// ============================================================================

/// Attributes implementation
/// CPython: class AttributesImpl
pub const AttributesImpl = struct {
    const Self = @This();

    attrs: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .attrs = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.attrs.deinit();
    }

    /// Get number of attributes
    pub fn getLength(self: *const Self) usize {
        return self.attrs.count();
    }

    /// Get attribute names
    pub fn getNames(self: *Self) ![][]const u8 {
        var result = std.ArrayList([]const u8){};
        var iter = self.attrs.keyIterator();
        while (iter.next()) |key| {
            try result.append(self.allocator, key.*);
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Get attribute type (always "CDATA")
    pub fn getType(self: *const Self, name: []const u8) []const u8 {
        _ = self;
        _ = name;
        return "CDATA";
    }

    /// Get attribute value by name
    pub fn getValue(self: *const Self, name: []const u8) ?[]const u8 {
        return self.attrs.get(name);
    }

    /// Get attribute value by index
    pub fn getValueByQName(self: *const Self, name: []const u8) ?[]const u8 {
        return self.getValue(name);
    }

    /// Get QName by name
    pub fn getQNameByName(self: *const Self, name: []const u8) []const u8 {
        _ = self;
        return name;
    }

    /// Get name by QName
    pub fn getNameByQName(self: *const Self, name: []const u8) []const u8 {
        _ = self;
        return name;
    }

    /// Check if attribute exists
    pub fn contains(self: *const Self, name: []const u8) bool {
        return self.attrs.contains(name);
    }

    /// Set attribute
    pub fn put(self: *Self, name: []const u8, value: []const u8) !void {
        try self.attrs.put(name, value);
    }
};

// ============================================================================
// AttributesNSImpl
// ============================================================================

/// Namespace-aware attributes implementation
/// CPython: class AttributesNSImpl(AttributesImpl)
pub const AttributesNSImpl = struct {
    const Self = @This();

    base: AttributesImpl,
    qnames: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = AttributesImpl.init(allocator),
            .qnames = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
        self.qnames.deinit();
    }

    /// Get value by namespace and local name
    pub fn getValueByNS(self: *const Self, namespace: ?[]const u8, localname: []const u8) ?[]const u8 {
        _ = namespace;
        return self.base.getValue(localname);
    }

    /// Get QName by namespace and local name
    pub fn getQNameByNS(self: *const Self, namespace: ?[]const u8, localname: []const u8) ?[]const u8 {
        _ = namespace;
        return self.qnames.get(localname);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "AttributesImpl" {
    const allocator = std.testing.allocator;
    var attrs = AttributesImpl.init(allocator);
    defer attrs.deinit();

    try attrs.put("id", "123");
    try attrs.put("class", "main");

    try std.testing.expectEqual(@as(usize, 2), attrs.getLength());
    try std.testing.expectEqualStrings("123", attrs.getValue("id").?);
    try std.testing.expect(attrs.contains("class"));
}

test "IncrementalParser" {
    const allocator = std.testing.allocator;
    var parser = IncrementalParser.init(allocator);
    defer parser.deinit();

    try parser.feed("<root>");
    try parser.feed("</root>");
    try parser.close();
}
