//! xml.etree - The xml.etree package
//! Reference: cpython/Lib/xml/etree/__init__.py
//!
//! This package provides the ElementTree API for XML processing.
//! The main module is ElementTree.

const std = @import("std");

// Re-export from parent xml module's etree (DRY)
const xml = @import("../xml.zig");
const element_mod = @import("element.zig");
const tree_mod = @import("tree.zig");
const builder_mod = @import("builder.zig");

// ============================================================================
// Re-exports
// ============================================================================

/// Element class
pub const Element = element_mod.Element;

/// ChildIterator
pub const ChildIterator = element_mod.ChildIterator;

/// ElementTree class
pub const ElementTree = tree_mod.ElementTree;

// Builder functions
pub const fromstring = builder_mod.fromstring;
pub const tostring = builder_mod.tostring;
pub const createElement = builder_mod.createElement;
pub const SubElement = builder_mod.SubElement;
pub const Comment = builder_mod.Comment;
pub const ProcessingInstruction = builder_mod.ProcessingInstruction;
pub const iselement = builder_mod.iselement;
pub const XML = fromstring;
pub const XMLID = fromstring;

// Tree functions
pub const parseFile = tree_mod.parseFile;
pub const parse = tree_mod.parseFile;

// ============================================================================
// Additional Functions
// ============================================================================

/// Parse XML string (alias for fromstring)
pub fn fromstringlist(allocator: std.mem.Allocator, sequence: []const []const u8) !*Element {
    // Concatenate all strings
    var total_len: usize = 0;
    for (sequence) |s| total_len += s.len;

    var buffer = try allocator.alloc(u8, total_len);
    defer allocator.free(buffer);

    var pos: usize = 0;
    for (sequence) |s| {
        @memcpy(buffer[pos..][0..s.len], s);
        pos += s.len;
    }

    return fromstring(allocator, buffer);
}

/// Convert element tree to list of strings
pub fn tostringlist(allocator: std.mem.Allocator, element: *Element) ![][]u8 {
    var result = std.ArrayList([]u8){};
    errdefer result.deinit(allocator);

    const str = try tostring(allocator, element);
    try result.append(allocator, str);

    return result.toOwnedSlice(allocator);
}

/// Indent an XML tree for pretty printing
/// CPython: def indent(tree, space="  ", level=0)
pub fn indent(element: *Element, space: []const u8, level: usize) void {
    _ = element;
    _ = space;
    _ = level;
    // Simplified - add indentation in a real implementation
}

/// Register namespace prefix
/// CPython: def register_namespace(prefix, uri)
pub fn register_namespace(prefix: []const u8, uri: []const u8) void {
    _ = prefix;
    _ = uri;
    // Namespace registration
}

/// Canonicalize XML
/// CPython: def canonicalize(xml_data=None, *, ...)
pub fn canonicalize(allocator: std.mem.Allocator, xml_data: []const u8) ![]u8 {
    // Return as-is for now (simplified)
    return allocator.dupe(u8, xml_data);
}

// ============================================================================
// Tests
// ============================================================================

test "fromstring" {
    const allocator = std.testing.allocator;
    const elem = try fromstring(allocator, "<root><child/></root>");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }
    try std.testing.expectEqualStrings("root", elem.tag);
}
