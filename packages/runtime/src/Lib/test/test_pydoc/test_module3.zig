//! test.test_pydoc.test_render - Tests for text rendering
//! Tests the plain text documentation rendering system.

const std = @import("std");
const testing = std.testing;

/// Text rendering configuration
pub const RenderConfig = struct {
    max_width: u32 = 80,
    indent_width: u32 = 4,
    heading_style: HeadingStyle = .underlined,
    list_style: ListStyle = .dash,
    word_wrap: bool = true,
    preserve_whitespace: bool = false,

    pub const HeadingStyle = enum {
        underlined,
        bold,
        caps,
        plain,
    };

    pub const ListStyle = enum {
        dash,
        asterisk,
        number,
        bullet,
    };

    pub const default = RenderConfig{};
};

/// Text block with formatting
pub const TextBlock = struct {
    content: []const u8,
    indent_level: u32 = 0,
    block_type: BlockType = .paragraph,

    pub const BlockType = enum {
        paragraph,
        heading,
        code,
        list,
        definition,
        note,
        warning,
    };

    pub fn init(content: []const u8) TextBlock {
        return .{ .content = content };
    }

    pub fn asHeading(self: TextBlock) TextBlock {
        var result = self;
        result.block_type = .heading;
        return result;
    }

    pub fn asCode(self: TextBlock) TextBlock {
        var result = self;
        result.block_type = .code;
        return result;
    }

    pub fn withIndent(self: TextBlock, level: u32) TextBlock {
        var result = self;
        result.indent_level = level;
        return result;
    }
};

/// Document structure for rendering
pub const Document = struct {
    title: []const u8,
    blocks: std.ArrayList(TextBlock),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, title: []const u8) Document {
        return .{
            .title = title,
            .blocks = std.ArrayList(TextBlock).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Document) void {
        self.blocks.deinit();
    }

    pub fn addBlock(self: *Document, block: TextBlock) !void {
        try self.blocks.append(block);
    }

    pub fn addParagraph(self: *Document, text: []const u8) !void {
        try self.blocks.append(TextBlock.init(text));
    }

    pub fn addHeading(self: *Document, text: []const u8) !void {
        try self.blocks.append(TextBlock.init(text).asHeading());
    }

    pub fn addCode(self: *Document, code: []const u8) !void {
        try self.blocks.append(TextBlock.init(code).asCode());
    }

    pub fn blockCount(self: Document) usize {
        return self.blocks.items.len;
    }
};

/// Text renderer for plain text output
pub const TextRenderer = struct {
    config: RenderConfig,
    output: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    current_column: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, config: RenderConfig) TextRenderer {
        return .{
            .config = config,
            .output = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextRenderer) void {
        self.output.deinit();
    }

    pub fn render(self: *TextRenderer, doc: Document) ![]const u8 {
        self.output.clearRetainingCapacity();
        const writer = self.output.writer();

        // Title
        try self.renderHeading(writer, doc.title, 1);
        try writer.writeByte('\n');

        // Blocks
        for (doc.blocks.items) |block| {
            try self.renderBlock(writer, block);
            try writer.writeByte('\n');
        }

        return self.output.items;
    }

    fn renderHeading(self: *TextRenderer, writer: anytype, text: []const u8, level: u8) !void {
        _ = level;
        switch (self.config.heading_style) {
            .underlined => {
                try writer.print("{s}\n", .{text});
                for (0..text.len) |_| {
                    try writer.writeByte('=');
                }
                try writer.writeByte('\n');
            },
            .bold => {
                try writer.print("**{s}**\n", .{text});
            },
            .caps => {
                for (text) |c| {
                    try writer.writeByte(std.ascii.toUpper(c));
                }
                try writer.writeByte('\n');
            },
            .plain => {
                try writer.print("{s}\n", .{text});
            },
        }
    }

    fn renderBlock(self: *TextRenderer, writer: anytype, block: TextBlock) !void {
        const indent = block.indent_level * self.config.indent_width;

        for (0..indent) |_| {
            try writer.writeByte(' ');
        }

        switch (block.block_type) {
            .heading => {
                try self.renderHeading(writer, block.content, 2);
            },
            .code => {
                try writer.writeAll("    ");
                for (block.content) |c| {
                    try writer.writeByte(c);
                    if (c == '\n') {
                        try writer.writeAll("    ");
                    }
                }
                try writer.writeByte('\n');
            },
            .paragraph, .list, .definition, .note, .warning => {
                if (self.config.word_wrap) {
                    try self.writeWrapped(writer, block.content, indent);
                } else {
                    try writer.print("{s}\n", .{block.content});
                }
            },
        }
    }

    fn writeWrapped(self: *TextRenderer, writer: anytype, text: []const u8, base_indent: u32) !void {
        var col: u32 = base_indent;
        var words = std.mem.tokenizeScalar(u8, text, ' ');

        while (words.next()) |word| {
            const word_len: u32 = @intCast(word.len);
            if (col + word_len + 1 > self.config.max_width and col > base_indent) {
                try writer.writeByte('\n');
                for (0..base_indent) |_| {
                    try writer.writeByte(' ');
                }
                col = base_indent;
            } else if (col > base_indent) {
                try writer.writeByte(' ');
                col += 1;
            }
            try writer.writeAll(word);
            col += word_len;
        }
        try writer.writeByte('\n');
    }

    pub fn getOutput(self: TextRenderer) []const u8 {
        return self.output.items;
    }
};

/// Column formatter for tabular data
pub const ColumnFormatter = struct {
    columns: []const Column,
    separator: []const u8 = "  ",
    allocator: std.mem.Allocator,

    pub const Column = struct {
        header: []const u8,
        width: u32,
        alignment: Alignment = .left,

        pub const Alignment = enum { left, right, center };
    };

    pub fn init(allocator: std.mem.Allocator, columns: []const Column) ColumnFormatter {
        return .{
            .allocator = allocator,
            .columns = columns,
        };
    }

    pub fn formatRow(self: ColumnFormatter, values: []const []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        for (self.columns, 0..) |col, i| {
            if (i > 0) try writer.writeAll(self.separator);

            const value = if (i < values.len) values[i] else "";
            const padding = if (col.width > value.len) col.width - @as(u32, @intCast(value.len)) else 0;

            switch (col.alignment) {
                .left => {
                    try writer.writeAll(value);
                    for (0..padding) |_| try writer.writeByte(' ');
                },
                .right => {
                    for (0..padding) |_| try writer.writeByte(' ');
                    try writer.writeAll(value);
                },
                .center => {
                    const left_pad = padding / 2;
                    const right_pad = padding - left_pad;
                    for (0..left_pad) |_| try writer.writeByte(' ');
                    try writer.writeAll(value);
                    for (0..right_pad) |_| try writer.writeByte(' ');
                },
            }
        }

        return result.toOwnedSlice();
    }
};

// Tests
test "render_config_defaults" {
    const config = RenderConfig.default;
    try testing.expectEqual(@as(u32, 80), config.max_width);
    try testing.expectEqual(@as(u32, 4), config.indent_width);
    try testing.expect(config.word_wrap);
}

test "text_block_init" {
    const block = TextBlock.init("Hello world");
    try testing.expectEqualStrings("Hello world", block.content);
    try testing.expectEqual(TextBlock.BlockType.paragraph, block.block_type);
}

test "text_block_as_heading" {
    const block = TextBlock.init("Title").asHeading();
    try testing.expectEqual(TextBlock.BlockType.heading, block.block_type);
}

test "text_block_as_code" {
    const block = TextBlock.init("x = 1").asCode();
    try testing.expectEqual(TextBlock.BlockType.code, block.block_type);
}

test "text_block_with_indent" {
    const block = TextBlock.init("Indented").withIndent(2);
    try testing.expectEqual(@as(u32, 2), block.indent_level);
}

test "document_init" {
    var doc = Document.init(testing.allocator, "Test Doc");
    defer doc.deinit();
    try testing.expectEqualStrings("Test Doc", doc.title);
    try testing.expectEqual(@as(usize, 0), doc.blockCount());
}

test "document_add_paragraph" {
    var doc = Document.init(testing.allocator, "Test");
    defer doc.deinit();
    try doc.addParagraph("First paragraph.");
    try testing.expectEqual(@as(usize, 1), doc.blockCount());
}

test "document_add_heading" {
    var doc = Document.init(testing.allocator, "Test");
    defer doc.deinit();
    try doc.addHeading("Section 1");
    try testing.expectEqual(@as(usize, 1), doc.blockCount());
    try testing.expectEqual(TextBlock.BlockType.heading, doc.blocks.items[0].block_type);
}

test "document_add_code" {
    var doc = Document.init(testing.allocator, "Test");
    defer doc.deinit();
    try doc.addCode("print('hello')");
    try testing.expectEqual(TextBlock.BlockType.code, doc.blocks.items[0].block_type);
}

test "text_renderer_init" {
    var renderer = TextRenderer.init(testing.allocator, RenderConfig.default);
    defer renderer.deinit();
    try testing.expectEqual(@as(usize, 0), renderer.output.items.len);
}

test "text_renderer_render_simple" {
    var renderer = TextRenderer.init(testing.allocator, RenderConfig.default);
    defer renderer.deinit();

    var doc = Document.init(testing.allocator, "My Module");
    defer doc.deinit();
    try doc.addParagraph("This is a test module.");

    const output = try renderer.render(doc);
    try testing.expect(std.mem.indexOf(u8, output, "My Module") != null);
}

test "column_formatter_init" {
    const columns = &[_]ColumnFormatter.Column{
        .{ .header = "Name", .width = 20 },
        .{ .header = "Type", .width = 10 },
    };
    const formatter = ColumnFormatter.init(testing.allocator, columns);
    try testing.expectEqual(@as(usize, 2), formatter.columns.len);
}
