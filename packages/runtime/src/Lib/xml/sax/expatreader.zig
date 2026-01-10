//! xml.sax.expatreader - Expat-based SAX reader
//! Reference: cpython/Lib/xml/sax/expatreader.py
//!
//! This module provides an expat-based SAX parser.

const std = @import("std");
const sax = @import("../sax.zig");
const xmlreader = @import("xmlreader.zig");

// Re-export from parent (DRY)
pub const XMLReader = sax.XMLReader;
pub const IncrementalParser = xmlreader.IncrementalParser;
pub const ContentHandler = sax.ContentHandler;
pub const ErrorHandler = sax.ErrorHandler;
pub const Locator = sax.Locator;
pub const InputSource = sax.InputSource;
pub const AttributesImpl = xmlreader.AttributesImpl;

// ============================================================================
// ExpatParser
// ============================================================================

/// Expat-based SAX parser
/// CPython: class ExpatParser(IncrementalParser, Locator)
pub const ExpatParser = struct {
    const Self = @This();

    base: IncrementalParser,
    locator: Locator,
    namespace_prefixes: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = IncrementalParser.init(allocator),
            .locator = .{},
            .namespace_prefixes = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    /// Get locator
    pub fn getLocator(self: *Self) *Locator {
        return &self.locator;
    }

    /// Set feature
    pub fn setFeature(self: *Self, name: []const u8, value: bool) !void {
        if (std.mem.eql(u8, name, "http://xml.org/sax/features/namespace-prefixes")) {
            self.namespace_prefixes = value;
        } else {
            return sax.SAXException.SAXNotRecognizedException;
        }
    }

    /// Get feature
    pub fn getFeature(self: *const Self, name: []const u8) !bool {
        if (std.mem.eql(u8, name, "http://xml.org/sax/features/namespace-prefixes")) {
            return self.namespace_prefixes;
        }
        return sax.SAXException.SAXNotRecognizedException;
    }

    /// Parse data
    pub fn parse(self: *Self, source: []const u8) !void {
        try self.base.base.parse(source);
    }

    /// Parse file
    pub fn parseFile(self: *Self, filename: []const u8) !void {
        try self.base.base.parseFile(filename);
    }

    /// Feed data incrementally
    pub fn feed(self: *Self, data: []const u8) !void {
        try self.base.feed(data);
    }

    /// Close parser
    pub fn close(self: *Self) !void {
        try self.base.close();
    }

    /// Reset parser
    pub fn reset(self: *Self) void {
        self.base.reset();
        self.locator = .{};
    }

    /// Set content handler
    pub fn setContentHandler(self: *Self, handler: ContentHandler) void {
        self.base.base.setContentHandler(handler);
    }

    /// Set error handler
    pub fn setErrorHandler(self: *Self, handler: ErrorHandler) void {
        self.base.base.setErrorHandler(handler);
    }
};

// ============================================================================
// Factory Function
// ============================================================================

/// Create expat parser
/// CPython: def create_parser()
pub fn create_parser(allocator: std.mem.Allocator) ExpatParser {
    return ExpatParser.init(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "ExpatParser" {
    const allocator = std.testing.allocator;
    var parser = create_parser(allocator);
    defer parser.deinit();

    try parser.parse("<root><child/></root>");
}

test "ExpatParser incremental" {
    const allocator = std.testing.allocator;
    var parser = create_parser(allocator);
    defer parser.deinit();

    try parser.feed("<root>");
    try parser.feed("<child/>");
    try parser.feed("</root>");
    try parser.close();
}
