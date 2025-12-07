//! Python 'pydoc' module - Documentation generator and online help system
//!
//! Provides a documentation viewer and HTML generator.
//!
//! Mirrors: CPython Lib/pydoc.py

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const PydocError = error{
    ModuleNotFound,
    DocumentationError,
    ServerError,
    IoError,
    OutOfMemory,
};

// ============================================================================
// Doc - Documentation helper
// ============================================================================

/// Documentation helper class
pub const Doc = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Maximum line length for text output
    max_width: usize = 80,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Format documentation for an object
    pub fn document(self: *Self, obj: anytype, name: ?[]const u8) ![]u8 {
        _ = obj;
        const doc_name = name orelse "object";
        return std.fmt.allocPrint(self.allocator, "Help on {s}:\n\n{s}\n", .{ doc_name, "No documentation available." });
    }

    /// Get a one-line description
    pub fn describe(self: *Self, obj: anytype) ![]u8 {
        _ = obj;
        return try self.allocator.dupe(u8, "No description available.");
    }
};

// ============================================================================
// TextDoc - Plain text documentation
// ============================================================================

/// Plain text documentation formatter
pub const TextDoc = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    max_width: usize = 80,
    indent: usize = 4,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Format text with word wrapping
    pub fn wrap(self: *Self, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        var col: usize = 0;
        var iter = std.mem.splitScalar(u8, text, ' ');

        while (iter.next()) |word| {
            if (col > 0 and col + word.len + 1 > self.max_width) {
                try writer.writeByte('\n');
                col = 0;
            } else if (col > 0) {
                try writer.writeByte(' ');
                col += 1;
            }
            try writer.writeAll(word);
            col += word.len;
        }

        return result.toOwnedSlice();
    }

    /// Add indentation to text
    pub fn indentText(self: *Self, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        var lines = std.mem.splitScalar(u8, text, '\n');
        var first = true;

        while (lines.next()) |line| {
            if (!first) try writer.writeByte('\n');
            first = false;

            if (line.len > 0) {
                for (0..self.indent) |_| try writer.writeByte(' ');
                try writer.writeAll(line);
            }
        }

        return result.toOwnedSlice();
    }

    /// Format module documentation
    pub fn docModule(self: *Self, name: []const u8, synopsis: ?[]const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.print("NAME\n    {s}", .{name});
        if (synopsis) |s| {
            try writer.print(" - {s}", .{s});
        }
        try writer.writeAll("\n\n");

        return result.toOwnedSlice();
    }

    /// Format function documentation
    pub fn docFunction(self: *Self, name: []const u8, signature: ?[]const u8, docstring: ?[]const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.print("{s}", .{name});
        if (signature) |sig| {
            try writer.print("({s})", .{sig});
        } else {
            try writer.writeAll("(...)");
        }
        try writer.writeByte('\n');

        if (docstring) |doc| {
            const indented = try self.indentText(doc);
            defer self.allocator.free(indented);
            try writer.writeAll(indented);
            try writer.writeByte('\n');
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// HTMLDoc - HTML documentation
// ============================================================================

/// HTML documentation formatter
pub const HTMLDoc = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Generate HTML page header
    pub fn pageHeader(self: *Self, title: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\<title>{s}</title>
            \\<style>
            \\body {{ font-family: sans-serif; margin: 20px; }}
            \\.module {{ background: #f0f0f0; padding: 10px; }}
            \\.function {{ margin: 10px 0; }}
            \\.docstring {{ color: #666; margin-left: 20px; }}
            \\</style>
            \\</head>
            \\<body>
            \\
        , .{title});
    }

    /// Generate HTML page footer
    pub fn pageFooter(self: *Self) ![]u8 {
        return self.allocator.dupe(u8, "</body>\n</html>\n");
    }

    /// Format module as HTML
    pub fn docModule(self: *Self, name: []const u8, synopsis: ?[]const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.print("<div class=\"module\">\n<h1>{s}</h1>\n", .{name});
        if (synopsis) |s| {
            try writer.print("<p>{s}</p>\n", .{s});
        }
        try writer.writeAll("</div>\n");

        return result.toOwnedSlice();
    }

    /// Format function as HTML
    pub fn docFunction(self: *Self, name: []const u8, signature: ?[]const u8, docstring: ?[]const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.writeAll("<div class=\"function\">\n");
        try writer.print("<code>{s}(", .{name});
        if (signature) |sig| {
            try writer.print("{s}", .{sig});
        }
        try writer.writeAll(")</code>\n");

        if (docstring) |doc| {
            try writer.print("<p class=\"docstring\">{s}</p>\n", .{doc});
        }

        try writer.writeAll("</div>\n");

        return result.toOwnedSlice();
    }

    /// Escape HTML special characters
    pub fn escape(self: *Self, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        for (text) |c| {
            switch (c) {
                '<' => try writer.writeAll("&lt;"),
                '>' => try writer.writeAll("&gt;"),
                '&' => try writer.writeAll("&amp;"),
                '"' => try writer.writeAll("&quot;"),
                else => try writer.writeByte(c),
            }
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Show help for an object
pub fn help(allocator: std.mem.Allocator, obj: anytype) !void {
    var doc = Doc.init(allocator);
    const text = try doc.document(obj, null);
    defer allocator.free(text);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(text);
}

/// Get documentation string
pub fn getdoc(obj: anytype) ?[]const u8 {
    _ = obj;
    return null;
}

/// Locate a module
pub fn locate(allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    _ = allocator;
    _ = name;
    return null;
}

/// Render documentation as text
pub fn render_doc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var text_doc = TextDoc.init(allocator);
    return text_doc.docModule(name, null);
}

/// Start the documentation server
pub fn browse(port: u16) !void {
    _ = port;
    // Would start HTTP server
    std.debug.print("Starting pydoc server...\n", .{});
}

/// Write HTML documentation to file
pub fn writedoc(allocator: std.mem.Allocator, name: []const u8, filename: []const u8) !void {
    var html_doc = HTMLDoc.init(allocator);

    const header = try html_doc.pageHeader(name);
    defer allocator.free(header);

    const body = try html_doc.docModule(name, null);
    defer allocator.free(body);

    const footer = try html_doc.pageFooter();
    defer allocator.free(footer);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    try file.writeAll(header);
    try file.writeAll(body);
    try file.writeAll(footer);
}

// ============================================================================
// Command Line Interface
// ============================================================================

/// Main entry point
pub fn main(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("pydoc - documentation browser\n\n", .{});
        std.debug.print("Usage: pydoc <name>        Show documentation\n", .{});
        std.debug.print("       pydoc -w <name>     Write HTML doc\n", .{});
        std.debug.print("       pydoc -p <port>     Start server\n", .{});
        return 0;
    }

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-w")) {
            i += 1;
            if (i < args.len) {
                const name = args[i];
                var filename_buf: [256]u8 = undefined;
                const filename = std.fmt.bufPrint(&filename_buf, "{s}.html", .{name}) catch {
                    return 1;
                };
                writedoc(allocator, name, filename) catch |err| {
                    std.debug.print("Error: {}\n", .{err});
                    return 1;
                };
                std.debug.print("Wrote {s}\n", .{filename});
            }
        } else if (std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i < args.len) {
                const port = std.fmt.parseInt(u16, args[i], 10) catch 0;
                if (port > 0) {
                    browse(port) catch |err| {
                        std.debug.print("Error: {}\n", .{err});
                        return 1;
                    };
                }
            }
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            const doc_text = render_doc(allocator, arg) catch |err| {
                std.debug.print("Error: {}\n", .{err});
                return 1;
            };
            defer allocator.free(doc_text);
            std.debug.print("{s}\n", .{doc_text});
        }
    }

    return 0;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Doc init" {
    const allocator = std.testing.allocator;
    const doc = Doc.init(allocator);
    try std.testing.expectEqual(@as(usize, 80), doc.max_width);
}

test "TextDoc wrap" {
    const allocator = std.testing.allocator;
    var doc = TextDoc.init(allocator);
    doc.max_width = 20;

    const text = try doc.wrap("This is a test of word wrapping functionality");
    defer allocator.free(text);

    try std.testing.expect(text.len > 0);
}

test "TextDoc indentText" {
    const allocator = std.testing.allocator;
    var doc = TextDoc.init(allocator);
    doc.indent = 4;

    const text = try doc.indentText("Line 1\nLine 2");
    defer allocator.free(text);

    try std.testing.expect(std.mem.startsWith(u8, text, "    "));
}

test "HTMLDoc escape" {
    const allocator = std.testing.allocator;
    var doc = HTMLDoc.init(allocator);

    const escaped = try doc.escape("<test & \"value\">");
    defer allocator.free(escaped);

    try std.testing.expectEqualStrings("&lt;test &amp; &quot;value&quot;&gt;", escaped);
}

test "HTMLDoc pageHeader" {
    const allocator = std.testing.allocator;
    var doc = HTMLDoc.init(allocator);

    const header = try doc.pageHeader("Test");
    defer allocator.free(header);

    try std.testing.expect(std.mem.indexOf(u8, header, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "<title>Test</title>") != null);
}
