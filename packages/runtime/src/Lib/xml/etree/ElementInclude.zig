//! xml.etree.ElementInclude - XInclude support for ElementTree
//! Reference: cpython/Lib/xml/etree/ElementInclude.py
//!
//! This module provides limited XInclude support for ElementTree.
//!
//! CPython __all__: ['default_loader', 'include', 'FatalIncludeError',
//!                   'LimitedRecursiveIncludeError', 'XINCLUDE', 'XINCLUDE_INCLUDE',
//!                   'XINCLUDE_FALLBACK']

const std = @import("std");
const Element = @import("../element.zig").Element;

// ============================================================================
// Constants
// ============================================================================

/// XInclude namespace
pub const XINCLUDE = "{http://www.w3.org/2001/XInclude}";

/// XInclude include element
pub const XINCLUDE_INCLUDE = XINCLUDE ++ "include";

/// XInclude fallback element
pub const XINCLUDE_FALLBACK = XINCLUDE ++ "fallback";

/// Maximum include depth to prevent infinite recursion
pub const MAX_INCLUDE_DEPTH = 100;

// ============================================================================
// Errors
// ============================================================================

/// Fatal include error
/// CPython: class FatalIncludeError(SyntaxError)
pub const FatalIncludeError = error{
    FatalIncludeError,
    ResourceNotFound,
    ParseError,
    CircularInclude,
};

/// Recursive include limit exceeded
/// CPython: class LimitedRecursiveIncludeError(FatalIncludeError)
pub const LimitedRecursiveIncludeError = error{
    LimitedRecursiveIncludeError,
};

// ============================================================================
// Loader Interface
// ============================================================================

/// Loader function type
pub const LoaderFn = *const fn (allocator: std.mem.Allocator, href: []const u8, parse_mode: ParseMode, encoding: ?[]const u8) anyerror!LoadResult;

/// Parse mode for includes
pub const ParseMode = enum {
    xml,
    text,
};

/// Result of loading a resource
pub const LoadResult = union(enum) {
    element: *Element,
    text: []const u8,
};

// ============================================================================
// Default Loader
// ============================================================================

/// Default loader - loads from file system
/// CPython: def default_loader(href, parse, encoding=None)
pub fn default_loader(allocator: std.mem.Allocator, href: []const u8, parse_mode: ParseMode, encoding: ?[]const u8) !LoadResult {
    _ = encoding;

    const file = std.fs.cwd().openFile(href, .{}) catch {
        return FatalIncludeError.ResourceNotFound;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);

    switch (parse_mode) {
        .xml => {
            const parser = @import("../parser.zig");
            const elem = try parser.parseXML(allocator, content);
            allocator.free(content);
            return .{ .element = elem };
        },
        .text => {
            return .{ .text = content };
        },
    }
}

// ============================================================================
// Include Processing
// ============================================================================

/// Process XInclude directives in element tree
/// CPython: def include(elem, loader=None, base_url=None, max_depth=DEFAULT_MAX_INCLUSION_DEPTH)
pub fn include(allocator: std.mem.Allocator, elem: *Element, loader: ?LoaderFn, base_url: ?[]const u8, max_depth: ?usize) !void {
    const actual_loader = loader orelse default_loader;
    const actual_max_depth = max_depth orelse MAX_INCLUDE_DEPTH;
    try processIncludes(allocator, elem, actual_loader, base_url, actual_max_depth, 0);
}

/// Process includes recursively
fn processIncludes(
    allocator: std.mem.Allocator,
    elem: *Element,
    loader: LoaderFn,
    base_url: ?[]const u8,
    max_depth: usize,
    current_depth: usize,
) !void {
    if (current_depth > max_depth) {
        return LimitedRecursiveIncludeError.LimitedRecursiveIncludeError;
    }

    var i: usize = 0;
    while (i < elem.children.items.len) {
        const child = elem.children.items[i];

        if (std.mem.eql(u8, child.tag, XINCLUDE_INCLUDE) or
            std.mem.eql(u8, child.tag, "include") or
            std.mem.eql(u8, child.tag, "{http://www.w3.org/2001/XInclude}include"))
        {
            // Process xi:include
            const href = child.get("href", null) orelse {
                i += 1;
                continue;
            };

            const parse_str = child.get("parse", "xml");
            const parse_mode: ParseMode = if (std.mem.eql(u8, parse_str, "text")) .text else .xml;

            // Resolve href against base URL
            const resolved_href = if (base_url) |base| blk: {
                // Simple path joining
                if (std.mem.startsWith(u8, href, "/") or std.mem.indexOf(u8, href, "://") != null) {
                    break :blk href;
                }
                // Join with base
                const last_slash = std.mem.lastIndexOf(u8, base, "/") orelse 0;
                const dir = base[0 .. last_slash + 1];
                const joined = try std.mem.concat(allocator, u8, &.{ dir, href });
                break :blk joined;
            } else href;

            // Load the resource
            const result = loader(allocator, resolved_href, parse_mode, null) catch |err| {
                // Check for fallback
                if (child.find(XINCLUDE_FALLBACK)) |fallback| {
                    // Use fallback content
                    for (fallback.children.items) |fc| {
                        try elem.insert(i, fc);
                        i += 1;
                    }
                    elem.remove(child);
                    continue;
                }
                return err;
            };

            switch (result) {
                .element => |included| {
                    // Replace include element with included element
                    try elem.insert(i, included);
                    elem.remove(child);
                    // Process includes in the included element
                    try processIncludes(allocator, included, loader, base_url, max_depth, current_depth + 1);
                },
                .text => |text| {
                    // Replace with text node
                    if (i > 0) {
                        const prev = elem.children.items[i - 1];
                        const new_text = if (prev.tail) |t|
                            try std.mem.concat(allocator, u8, &.{ t, text })
                        else
                            text;
                        try prev.setTail(new_text);
                    } else {
                        const new_text = if (elem.text) |t|
                            try std.mem.concat(allocator, u8, &.{ t, text })
                        else
                            text;
                        try elem.setText(new_text);
                    }
                    elem.remove(child);
                },
            }
        } else {
            // Recursively process children
            try processIncludes(allocator, child, loader, base_url, max_depth, current_depth);
            i += 1;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqualStrings("{http://www.w3.org/2001/XInclude}", XINCLUDE);
    try std.testing.expectEqualStrings("{http://www.w3.org/2001/XInclude}include", XINCLUDE_INCLUDE);
}
