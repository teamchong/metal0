//! test.test_pydoc.test_html - Tests for HTML documentation output
//! Tests HTML generation for pydoc web interface.

const std = @import("std");
const testing = std.testing;

/// HTML rendering configuration
pub const HtmlConfig = struct {
    title: []const u8 = "Python Documentation",
    css_path: ?[]const u8 = null,
    inline_styles: bool = true,
    syntax_highlight: bool = true,
    link_modules: bool = true,
    include_nav: bool = true,
    include_toc: bool = true,

    pub const default = HtmlConfig{};
};

/// CSS styles for HTML output
pub const HtmlStyles = struct {
    // Color scheme
    bg_color: []const u8 = "#ffffff",
    text_color: []const u8 = "#000000",
    heading_color: []const u8 = "#003366",
    link_color: []const u8 = "#0066cc",
    code_bg: []const u8 = "#f4f4f4",
    keyword_color: []const u8 = "#0000ff",
    string_color: []const u8 = "#008000",
    comment_color: []const u8 = "#808080",

    pub fn toCss(self: HtmlStyles, allocator: std.mem.Allocator) ![]const u8 {
        var css = std.ArrayList(u8).init(allocator);
        const writer = css.writer();

        try writer.print(
            \\body {{ background: {s}; color: {s}; font-family: sans-serif; }}
            \\h1, h2, h3 {{ color: {s}; }}
            \\a {{ color: {s}; }}
            \\pre, code {{ background: {s}; padding: 2px 5px; }}
            \\.keyword {{ color: {s}; font-weight: bold; }}
            \\.string {{ color: {s}; }}
            \\.comment {{ color: {s}; font-style: italic; }}
            \\
        , .{
            self.bg_color,
            self.text_color,
            self.heading_color,
            self.link_color,
            self.code_bg,
            self.keyword_color,
            self.string_color,
            self.comment_color,
        });

        return css.toOwnedSlice();
    }

    pub const light = HtmlStyles{};

    pub const dark = HtmlStyles{
        .bg_color = "#1e1e1e",
        .text_color = "#d4d4d4",
        .heading_color = "#569cd6",
        .link_color = "#4ec9b0",
        .code_bg = "#2d2d2d",
        .keyword_color = "#c586c0",
        .string_color = "#ce9178",
        .comment_color = "#6a9955",
    };
};

/// HTML element builder
pub const HtmlElement = struct {
    tag: []const u8,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(HtmlNode),
    allocator: std.mem.Allocator,

    pub const Attribute = struct {
        name: []const u8,
        value: []const u8,
    };

    pub const HtmlNode = union(enum) {
        element: *HtmlElement,
        text: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, tag: []const u8) HtmlElement {
        return .{
            .tag = tag,
            .attributes = std.ArrayList(Attribute).init(allocator),
            .children = std.ArrayList(HtmlNode).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HtmlElement) void {
        self.attributes.deinit();
        self.children.deinit();
    }

    pub fn attr(self: *HtmlElement, name: []const u8, value: []const u8) !*HtmlElement {
        try self.attributes.append(.{ .name = name, .value = value });
        return self;
    }

    pub fn text(self: *HtmlElement, content: []const u8) !*HtmlElement {
        try self.children.append(.{ .text = content });
        return self;
    }

    pub fn child(self: *HtmlElement, elem: *HtmlElement) !*HtmlElement {
        try self.children.append(.{ .element = elem });
        return self;
    }

    pub fn render(self: HtmlElement, writer: anytype) !void {
        try writer.print("<{s}", .{self.tag});
        for (self.attributes.items) |a| {
            try writer.print(" {s}=\"{s}\"", .{ a.name, a.value });
        }
        try writer.writeByte('>');

        for (self.children.items) |node| {
            switch (node) {
                .element => |elem| try elem.render(writer),
                .text => |t| try writer.writeAll(t),
            }
        }

        try writer.print("</{s}>", .{self.tag});
    }
};

/// HTML document builder
pub const HtmlDocument = struct {
    config: HtmlConfig,
    styles: HtmlStyles,
    body_content: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: HtmlConfig) HtmlDocument {
        return .{
            .config = config,
            .styles = HtmlStyles.light,
            .body_content = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HtmlDocument) void {
        self.body_content.deinit();
    }

    pub fn withStyles(self: *HtmlDocument, styles: HtmlStyles) *HtmlDocument {
        self.styles = styles;
        return self;
    }

    pub fn addHeading(self: *HtmlDocument, level: u8, text: []const u8) !void {
        const writer = self.body_content.writer();
        try writer.print("<h{d}>{s}</h{d}>\n", .{ level, text, level });
    }

    pub fn addParagraph(self: *HtmlDocument, text: []const u8) !void {
        const writer = self.body_content.writer();
        try writer.print("<p>{s}</p>\n", .{text});
    }

    pub fn addCode(self: *HtmlDocument, code: []const u8) !void {
        const writer = self.body_content.writer();
        try writer.print("<pre><code>{s}</code></pre>\n", .{code});
    }

    pub fn addLink(self: *HtmlDocument, href: []const u8, text: []const u8) !void {
        const writer = self.body_content.writer();
        try writer.print("<a href=\"{s}\">{s}</a>", .{ href, text });
    }

    pub fn addList(self: *HtmlDocument, items: []const []const u8) !void {
        const writer = self.body_content.writer();
        try writer.writeAll("<ul>\n");
        for (items) |item| {
            try writer.print("  <li>{s}</li>\n", .{item});
        }
        try writer.writeAll("</ul>\n");
    }

    pub fn render(self: *HtmlDocument) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        const writer = output.writer();

        try writer.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
        try writer.print("  <title>{s}</title>\n", .{self.config.title});

        if (self.config.inline_styles) {
            const css = try self.styles.toCss(self.allocator);
            defer self.allocator.free(css);
            try writer.print("  <style>\n{s}  </style>\n", .{css});
        }

        try writer.writeAll("</head>\n<body>\n");
        try writer.writeAll(self.body_content.items);
        try writer.writeAll("</body>\n</html>\n");

        return output.toOwnedSlice();
    }
};

/// Syntax highlighter for Python code
pub const SyntaxHighlighter = struct {
    keywords: []const []const u8,
    builtins: []const []const u8,

    pub const python = SyntaxHighlighter{
        .keywords = &.{
            "and",    "as",       "assert", "async",  "await",    "break",
            "class",  "continue", "def",    "del",    "elif",     "else",
            "except", "finally",  "for",    "from",   "global",   "if",
            "import", "in",       "is",     "lambda", "nonlocal", "not",
            "or",     "pass",     "raise",  "return", "try",      "while",
            "with",   "yield",
        },
        .builtins = &.{
            "True",   "False",  "None",   "print",  "len",     "range",
            "type",   "str",    "int",    "float",  "list",    "dict",
            "tuple",  "set",    "bool",   "bytes",  "open",    "input",
            "sorted", "map",    "filter", "zip",    "enumerate",
        },
    };

    pub fn isKeyword(self: SyntaxHighlighter, word: []const u8) bool {
        for (self.keywords) |kw| {
            if (std.mem.eql(u8, kw, word)) return true;
        }
        return false;
    }

    pub fn isBuiltin(self: SyntaxHighlighter, word: []const u8) bool {
        for (self.builtins) |b| {
            if (std.mem.eql(u8, b, word)) return true;
        }
        return false;
    }

    pub fn highlight(self: SyntaxHighlighter, allocator: std.mem.Allocator, code: []const u8) ![]const u8 {
        _ = self;
        // Simplified: just escape HTML entities
        var result = std.ArrayList(u8).init(allocator);
        for (code) |c| {
            switch (c) {
                '<' => try result.appendSlice("&lt;"),
                '>' => try result.appendSlice("&gt;"),
                '&' => try result.appendSlice("&amp;"),
                '"' => try result.appendSlice("&quot;"),
                else => try result.append(c),
            }
        }
        return result.toOwnedSlice();
    }
};

// Tests
test "html_config_defaults" {
    const config = HtmlConfig.default;
    try testing.expectEqualStrings("Python Documentation", config.title);
    try testing.expect(config.inline_styles);
    try testing.expect(config.syntax_highlight);
}

test "html_styles_light" {
    const styles = HtmlStyles.light;
    try testing.expectEqualStrings("#ffffff", styles.bg_color);
    try testing.expectEqualStrings("#000000", styles.text_color);
}

test "html_styles_dark" {
    const styles = HtmlStyles.dark;
    try testing.expectEqualStrings("#1e1e1e", styles.bg_color);
    try testing.expectEqualStrings("#d4d4d4", styles.text_color);
}

test "html_styles_to_css" {
    const styles = HtmlStyles.light;
    const css = try styles.toCss(testing.allocator);
    defer testing.allocator.free(css);
    try testing.expect(std.mem.indexOf(u8, css, "body") != null);
    try testing.expect(std.mem.indexOf(u8, css, "#ffffff") != null);
}

test "html_element_init" {
    var elem = HtmlElement.init(testing.allocator, "div");
    defer elem.deinit();
    try testing.expectEqualStrings("div", elem.tag);
}

test "html_element_attributes" {
    var elem = HtmlElement.init(testing.allocator, "a");
    defer elem.deinit();
    _ = try elem.attr("href", "#top");
    try testing.expectEqual(@as(usize, 1), elem.attributes.items.len);
}

test "html_document_init" {
    var doc = HtmlDocument.init(testing.allocator, HtmlConfig.default);
    defer doc.deinit();
    try testing.expectEqualStrings("Python Documentation", doc.config.title);
}

test "html_document_add_heading" {
    var doc = HtmlDocument.init(testing.allocator, HtmlConfig.default);
    defer doc.deinit();
    try doc.addHeading(1, "Test Module");
    try testing.expect(std.mem.indexOf(u8, doc.body_content.items, "<h1>") != null);
}

test "html_document_add_paragraph" {
    var doc = HtmlDocument.init(testing.allocator, HtmlConfig.default);
    defer doc.deinit();
    try doc.addParagraph("This is a test.");
    try testing.expect(std.mem.indexOf(u8, doc.body_content.items, "<p>") != null);
}

test "html_document_add_code" {
    var doc = HtmlDocument.init(testing.allocator, HtmlConfig.default);
    defer doc.deinit();
    try doc.addCode("x = 1");
    try testing.expect(std.mem.indexOf(u8, doc.body_content.items, "<pre>") != null);
}

test "html_document_render" {
    var doc = HtmlDocument.init(testing.allocator, HtmlConfig.default);
    defer doc.deinit();
    try doc.addHeading(1, "Module");
    const html = try doc.render();
    defer testing.allocator.free(html);
    try testing.expect(std.mem.indexOf(u8, html, "<!DOCTYPE html>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "</html>") != null);
}

test "syntax_highlighter_keywords" {
    const hl = SyntaxHighlighter.python;
    try testing.expect(hl.isKeyword("def"));
    try testing.expect(hl.isKeyword("class"));
    try testing.expect(!hl.isKeyword("foo"));
}

test "syntax_highlighter_builtins" {
    const hl = SyntaxHighlighter.python;
    try testing.expect(hl.isBuiltin("print"));
    try testing.expect(hl.isBuiltin("len"));
    try testing.expect(!hl.isBuiltin("myfunction"));
}

test "syntax_highlighter_escape" {
    const hl = SyntaxHighlighter.python;
    const result = try hl.highlight(testing.allocator, "<script>");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("&lt;script&gt;", result);
}
