const std = @import("std");

// 5×7 bitmap font for ASCII characters
// Each character is represented as 7 rows of 5 bits (stored as u8)
// Bit pattern: 0 = background, 1 = foreground

pub const RenderColor = enum(u8) {
    white = 0, // Background
    black = 1, // Normal text
    gray = 2, // Whitespace indicators
};

const Font5x7 = struct {
    width: usize = 5,
    height: usize = 7,

    fn getGlyph(self: Font5x7, char: u8) [7]u8 {
        _ = self;
        return switch (char) {
            ' ' => .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 },
            'A' => .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
            'B' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 },
            'C' => .{ 0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110 },
            'D' => .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 },
            'E' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 },
            'F' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 },
            'G' => .{ 0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111 },
            'H' => .{ 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
            'I' => .{ 0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
            'J' => .{ 0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100 },
            'K' => .{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 },
            'L' => .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 },
            'M' => .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 },
            'N' => .{ 0b10001, 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001 },
            'O' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
            'P' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000 },
            'Q' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101 },
            'R' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 },
            'S' => .{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 },
            'T' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
            'U' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
            'V' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
            'W' => .{ 0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001 },
            'X' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001 },
            'Y' => .{ 0b10001, 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100 },
            'Z' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111 },
            'a' => .{ 0b00000, 0b00000, 0b01110, 0b00001, 0b01111, 0b10001, 0b01111 },
            'b' => .{ 0b10000, 0b10000, 0b10110, 0b11001, 0b10001, 0b10001, 0b11110 },
            'c' => .{ 0b00000, 0b00000, 0b01110, 0b10000, 0b10000, 0b10001, 0b01110 },
            'd' => .{ 0b00001, 0b00001, 0b01101, 0b10011, 0b10001, 0b10001, 0b01111 },
            'e' => .{ 0b00000, 0b00000, 0b01110, 0b10001, 0b11111, 0b10000, 0b01110 },
            'f' => .{ 0b00110, 0b01001, 0b01000, 0b11110, 0b01000, 0b01000, 0b01000 },
            'g' => .{ 0b00000, 0b01111, 0b10001, 0b10001, 0b01111, 0b00001, 0b01110 },
            'h' => .{ 0b10000, 0b10000, 0b10110, 0b11001, 0b10001, 0b10001, 0b10001 },
            'i' => .{ 0b00100, 0b00000, 0b01100, 0b00100, 0b00100, 0b00100, 0b01110 },
            'j' => .{ 0b00010, 0b00000, 0b00110, 0b00010, 0b00010, 0b10010, 0b01100 },
            'k' => .{ 0b10000, 0b10000, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010 },
            'l' => .{ 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
            'm' => .{ 0b00000, 0b00000, 0b11010, 0b10101, 0b10101, 0b10101, 0b10001 },
            'n' => .{ 0b00000, 0b00000, 0b10110, 0b11001, 0b10001, 0b10001, 0b10001 },
            'o' => .{ 0b00000, 0b00000, 0b01110, 0b10001, 0b10001, 0b10001, 0b01110 },
            'p' => .{ 0b00000, 0b00000, 0b11110, 0b10001, 0b11110, 0b10000, 0b10000 },
            'q' => .{ 0b00000, 0b00000, 0b01101, 0b10011, 0b01111, 0b00001, 0b00001 },
            'r' => .{ 0b00000, 0b00000, 0b10110, 0b11001, 0b10000, 0b10000, 0b10000 },
            's' => .{ 0b00000, 0b00000, 0b01110, 0b10000, 0b01110, 0b00001, 0b11110 },
            't' => .{ 0b01000, 0b01000, 0b11110, 0b01000, 0b01000, 0b01001, 0b00110 },
            'u' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10001, 0b10011, 0b01101 },
            'v' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
            'w' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10101, 0b10101, 0b01010 },
            'x' => .{ 0b00000, 0b00000, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001 },
            'y' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b01111, 0b00001, 0b01110 },
            'z' => .{ 0b00000, 0b00000, 0b11111, 0b00010, 0b00100, 0b01000, 0b11111 },
            '0' => .{ 0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110 },
            '1' => .{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
            '2' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 },
            '3' => .{ 0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110 },
            '4' => .{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
            '5' => .{ 0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110 },
            '6' => .{ 0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
            '7' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
            '8' => .{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
            '9' => .{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100 },
            '!' => .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00000, 0b00100 },
            '?' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100 },
            '.' => .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100 },
            ',' => .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b01000 },
            ':' => .{ 0b00000, 0b00000, 0b00100, 0b00000, 0b00000, 0b00100, 0b00000 },
            ';' => .{ 0b00000, 0b00000, 0b00100, 0b00000, 0b00000, 0b00100, 0b01000 },
            '-' => .{ 0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000 },
            '+' => .{ 0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000 },
            '=' => .{ 0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000 },
            '*' => .{ 0b00000, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0b00000 },
            '/' => .{ 0b00000, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000 },
            '\\' => .{ 0b00000, 0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b00000 },
            '(' => .{ 0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010 },
            ')' => .{ 0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000 },
            '[' => .{ 0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110 },
            ']' => .{ 0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110 },
            '{' => .{ 0b00110, 0b01000, 0b01000, 0b11000, 0b01000, 0b01000, 0b00110 },
            '}' => .{ 0b01100, 0b00010, 0b00010, 0b00011, 0b00010, 0b00010, 0b01100 },
            '<' => .{ 0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010 },
            '>' => .{ 0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000 },
            '_' => .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111 },
            '"' => .{ 0b01010, 0b01010, 0b01010, 0b00000, 0b00000, 0b00000, 0b00000 },
            '\'' => .{ 0b00100, 0b00100, 0b00100, 0b00000, 0b00000, 0b00000, 0b00000 },
            '&' => .{ 0b01100, 0b10010, 0b10100, 0b01000, 0b10101, 0b10010, 0b01101 },
            '#' => .{ 0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010 },
            '$' => .{ 0b00100, 0b01111, 0b10100, 0b01110, 0b00101, 0b11110, 0b00100 },
            '%' => .{ 0b11000, 0b11001, 0b00010, 0b00100, 0b01000, 0b10011, 0b00011 },
            '@' => .{ 0b01110, 0b10001, 0b00001, 0b01101, 0b10101, 0b10101, 0b01110 },
            // Whitespace indicators (VSCode-style)
            1 => .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00000 }, // · (middle dot for space)
            2 => .{ 0b10000, 0b11000, 0b10100, 0b10010, 0b11111, 0b00010, 0b00010 }, // → (arrow for tab)
            3 => .{ 0b00001, 0b00011, 0b00101, 0b01001, 0b11111, 0b01000, 0b01000 }, // ↵ (return symbol for newline)
            4 => .{ 0b00000, 0b00100, 0b01010, 0b10001, 0b01010, 0b00100, 0b11111 }, // ⏎ (carriage return)
            else => .{ 0b11111, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11111 }, // Unknown char box
        };
    }
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
    const font = Font5x7{};
    const char_width = font.width;
    const char_height = font.height;
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
        const glyph = font.getGlyph(display_char);
        const x_offset = i * (char_width + spacing);

        for (0..char_height) |y| {
            const row = glyph[y];
            for (0..char_width) |x| {
                const bit = (row >> @intCast(4 - x)) & 1;
                if (bit == 1) {
                    pixels[y][x_offset + x] = @intFromEnum(color);
                }
            }
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
