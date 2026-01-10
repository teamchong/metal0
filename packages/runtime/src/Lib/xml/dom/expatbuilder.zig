//! xml.dom.expatbuilder - Expat-based DOM builder
//! Reference: cpython/Lib/xml/dom/expatbuilder.py
//!
//! This module provides an expat-based DOM tree builder.

const std = @import("std");
const dom = @import("../dom.zig");
const minidom = @import("minidom.zig");

// Re-export parseString (DRY)
pub const parse = minidom.parse;
pub const parseString = minidom.parseString;

// ============================================================================
// ExpatBuilder
// ============================================================================

/// Expat-based DOM builder
/// CPython: class ExpatBuilder
pub const ExpatBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    document: ?*dom.Document,
    cur_node: ?*dom.Node,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .document = null,
            .cur_node = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Parse XML and return document
    pub fn parseFile(self: *Self, filename: []const u8) !*dom.Document {
        return minidom.parse(self.allocator, filename);
    }

    /// Parse XML string and return document
    pub fn parseStringDoc(self: *Self, xml_string: []const u8) !*dom.Document {
        return minidom.parseString(self.allocator, xml_string);
    }

    /// Reset the builder
    pub fn reset(self: *Self) void {
        self.document = null;
        self.cur_node = null;
    }
};

/// ExpatBuilderNS - Namespace-aware expat builder
/// CPython: class ExpatBuilderNS(ExpatBuilder)
pub const ExpatBuilderNS = ExpatBuilder;

// ============================================================================
// Tests
// ============================================================================

test "ExpatBuilder" {
    const allocator = std.testing.allocator;
    var builder = ExpatBuilder.init(allocator);
    defer builder.deinit();

    const doc = try builder.parseStringDoc("<root/>");
    defer {
        doc.deinit();
        allocator.destroy(doc);
    }

    try std.testing.expect(doc.document_element != null);
}
