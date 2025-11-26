const std = @import("std");
const font_3x4 = @import("font_3x4.zig");

// 3×4 nanofont for token compression (89% savings)
// Bit pattern: 0 = background, 1 = foreground

pub const RenderColor = enum(u8) {
    white = 0, // Background
    black = 1, // Normal text
    gray = 2, // Whitespace indicators
};

pub const RenderedText = struct {
    pixels: [][]u8, // Changed from u1 to u8 to support 3 colors (0=white, 1=black, 2=gray)
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RenderedText) void {
        for (self.pixels) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.pixels);
    }
};

// Font selection strategy
pub const FontType = enum {
    nano_3x4, // Smallest - 89% savings, ASCII only
    medium_4x6, // Fallback - 87% savings, better readability

    pub fn select(text: []const u8) FontType {
        // Use 3×4 nanofont for all ASCII text (most common case)
        // Use 4×6 for better readability if needed (future: could check line length)
        _ = text;
        return .nano_3x4; // Default to smallest font for maximum compression
    }

    pub fn width(self: FontType) usize {
        return switch (self) {
            .nano_3x4 => 3,
            .medium_4x6 => 4,
        };
    }

    pub fn height(self: FontType) usize {
        return switch (self) {
            .nano_3x4 => 4,
            .medium_4x6 => 6,
        };
    }
};

// Helper to check if char is whitespace
fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n' or char == '\r';
}

// Map whitespace chars to visual indicator glyphs
fn getWhitespaceGlyph(char: u8) u8 {
    return switch (char) {
        ' ' => 1, // · (middle dot)
        '\t' => 2, // → (tab arrow)
        '\n' => 3, // ↵ (return)
        '\r' => 4, // ⏎ (carriage return)
        else => char,
    };
}

pub fn renderText(allocator: std.mem.Allocator, text: []const u8) !RenderedText {
    // Select font based on text content
    const font_type = FontType.select(text);
    const char_width = font_type.width();
    const char_height = font_type.height();
    const spacing = 1; // 1 pixel spacing between characters

    // Calculate dimensions (all chars rendered, including whitespace indicators)
    const width = text.len * (char_width + spacing);
    const height = char_height;

    // Allocate pixel array
    var pixels = try allocator.alloc([]u8, height);
    errdefer allocator.free(pixels);

    for (0..height) |y| {
        pixels[y] = try allocator.alloc(u8, width);
        errdefer {
            for (0..y) |py| allocator.free(pixels[py]);
        }
        @memset(pixels[y], 0); // White background
    }

    // Render each character with color
    for (text, 0..) |char, i| {
        const color: RenderColor = if (isWhitespace(char)) .gray else .black;
        const display_char = if (isWhitespace(char)) getWhitespaceGlyph(char) else char;

        // Get glyph based on font type
        const x_offset = i * (char_width + spacing);

        switch (font_type) {
            .nano_3x4 => {
                const font = font_3x4.Font3x4{};
                const glyph = font.getGlyph(display_char);
                for (0..char_height) |y| {
                    const row = glyph[y];
                    for (0..char_width) |x| {
                        const bit = (row >> @intCast(char_width - 1 - x)) & 1;
                        if (bit == 1) {
                            pixels[y][x_offset + x] = @intFromEnum(color);
                        }
                    }
                }
            },
            .medium_4x6 => {
                const font_4x6 = @import("font_4x6.zig");
                const font = font_4x6.Font4x6{};
                const glyph = font.getGlyph(display_char);
                for (0..char_height) |y| {
                    const row = glyph[y];
                    for (0..char_width) |x| {
                        const bit = (row >> @intCast(char_width - 1 - x)) & 1;
                        if (bit == 1) {
                            pixels[y][x_offset + x] = @intFromEnum(color);
                        }
                    }
                }
            },
        }
    }

    return RenderedText{
        .pixels = pixels,
        .width = width,
        .height = height,
        .allocator = allocator,
    };
}

// Helper function to print ASCII art for debugging (3-color support)
pub fn printAsciiArt(rendered: *const RenderedText) void {
    for (rendered.pixels) |row| {
        for (row) |pixel| {
            const char: u8 = switch (pixel) {
                0 => ' ', // White (background)
                1 => '#', // Black (text)
                2 => '.', // Gray (whitespace indicators)
                else => '?',
            };
            std.debug.print("{c}", .{char});
        }
        std.debug.print("\n", .{});
    }
}
