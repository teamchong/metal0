const std = @import("std");
const font_5x7 = @import("font_5x7.zig");
const api_types = @import("api_types.zig");

// 5×7 standard font for token compression
// Bit pattern: 0 = background, 1 = foreground

/// Colors for different message roles (RGB values)
pub const RoleColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn fromRole(role: api_types.Role) RoleColor {
        return switch (role) {
            .user => .{ .r = 59, .g = 130, .b = 246 }, // Blue
            .assistant => .{ .r = 34, .g = 197, .b = 94 }, // Green
            .system => .{ .r = 234, .g = 179, .b = 8 }, // Yellow
            .tool_use => .{ .r = 239, .g = 68, .b = 68 }, // Red
            .tool_result => .{ .r = 168, .g = 85, .b = 247 }, // Purple
        };
    }

    pub fn toIndex(self: RoleColor) u8 {
        // Map to PNG palette index (see png_zigimg.zig)
        // 0=white, 1=black, 2=gray, 3=blue, 4=green, 5=red, 6=orange, 7=cyan
        if (self.r == 59 and self.g == 130) return 3; // Blue - user
        if (self.r == 34 and self.g == 197) return 4; // Green - assistant
        if (self.r == 234 and self.g == 179) return 5; // Yellow/Red - system
        if (self.r == 239 and self.g == 68) return 6; // Red/Orange - tool_use
        if (self.r == 168 and self.g == 85) return 7; // Purple/Cyan - tool_result
        return 3; // Default to blue
    }
};

pub const RenderedText = struct {
    pixels: [][]u8, // Palette index per pixel
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

// Font dimensions (5x7 standard font)
const CHAR_WIDTH = 5;
const CHAR_HEIGHT = 7;
const CHAR_SPACING = 1; // Horizontal spacing between chars
const LINE_SPACING = 2; // Vertical spacing between lines
const SCALE = 1; // No scaling for max token savings

// Optimal square target size for LLM vision (research-backed)
// Claude performs best with images around 1024x1024
pub const TARGET_SQUARE_SIZE: usize = 1024;

// Max dimension for GIF (u16 limit)
const MAX_GIF_DIM: usize = 65535;

// Max image size we'll generate (split if larger)
pub const MAX_IMAGE_DIM: usize = 1024;

/// Visual whitespace indicators
fn getWhitespaceVisual(char: u8) []const u8 {
    return switch (char) {
        ' ' => "·", // Middle dot for space
        '\t' => "→", // Arrow for tab
        '\n' => "↵", // Return symbol for newline
        '\r' => "⏎", // Carriage return
        else => &[_]u8{char},
    };
}

/// Check if char needs visual indicator
fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n' or char == '\r';
}

/// Result of single line conversion with whitespace and role tracking
pub const SingleLineResult = struct {
    text: []const u8,
    is_whitespace: []const bool, // true = render in gray (#CCC)
    roles: []const api_types.Role, // role for each character (for coloring)
};

/// Convert text to single line with visual whitespace indicators
/// Also carries over the role for each character
pub fn toSingleLineWithRoles(allocator: std.mem.Allocator, text: []const u8, roles: []const api_types.Role) !SingleLineResult {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var is_ws = std.ArrayList(bool){};
    errdefer is_ws.deinit(allocator);

    var out_roles = std.ArrayList(api_types.Role){};
    errdefer out_roles.deinit(allocator);

    for (text, 0..) |c, i| {
        const role = if (i < roles.len) roles[i] else .user;

        if (c == '\n') {
            // Use '|' as newline indicator (ASCII, visible)
            try result.append(allocator, '|');
            try is_ws.append(allocator, true);
            try out_roles.append(allocator, role);
        } else if (c == '\t') {
            // Use '>' as tab indicator (ASCII, visible)
            try result.append(allocator, '>');
            try is_ws.append(allocator, true);
            try out_roles.append(allocator, role);
        } else if (c == '\r') {
            // Skip carriage returns (don't add to output)
        } else {
            try result.append(allocator, c);
            try is_ws.append(allocator, false);
            try out_roles.append(allocator, role);
        }
    }

    return SingleLineResult{
        .text = try result.toOwnedSlice(allocator),
        .is_whitespace = try is_ws.toOwnedSlice(allocator),
        .roles = try out_roles.toOwnedSlice(allocator),
    };
}

/// Legacy function without roles
pub fn toSingleLine(allocator: std.mem.Allocator, text: []const u8) !SingleLineResult {
    // Create default roles array (all user)
    const default_roles = try allocator.alloc(api_types.Role, text.len);
    defer allocator.free(default_roles);
    @memset(default_roles, .user);

    return toSingleLineWithRoles(allocator, text, default_roles);
}

// Minimum width in pixels (for readability)
const MIN_WIDTH_PIXELS: usize = 200;
const MIN_WIDTH_CHARS: usize = MIN_WIDTH_PIXELS / SCALE / (CHAR_WIDTH + CHAR_SPACING);

/// Calculate optimal wrap width for square image
/// - Minimum width: 200 pixels
/// - Target: square image when text is large enough
/// - Max: stays under MAX_IMAGE_DIM (1024 pixels)
fn calculateWrapWidth(text_len: usize) usize {
    // For square image: width_pixels ≈ height_pixels
    // width_chars * (CHAR_WIDTH + CHAR_SPACING) * SCALE = num_lines * (CHAR_HEIGHT + LINE_SPACING) * SCALE
    // width_chars * num_lines ≈ text_len
    //
    // Solving for square: width_chars = sqrt(text_len * (CHAR_HEIGHT + LINE_SPACING) / (CHAR_WIDTH + CHAR_SPACING))

    const char_width_px = CHAR_WIDTH + CHAR_SPACING;
    const line_height_px = CHAR_HEIGHT + LINE_SPACING;
    _ = line_height_px; // Used in comment for documentation
    const ratio = @as(f64, @floatFromInt(CHAR_HEIGHT + LINE_SPACING)) / @as(f64, @floatFromInt(char_width_px));
    const width_chars_f = @sqrt(@as(f64, @floatFromInt(text_len)) * ratio);
    var width_chars = @as(usize, @intFromFloat(width_chars_f));

    // Minimum: 200 pixels worth of chars (~16 chars at scale 2)
    width_chars = @max(MIN_WIDTH_CHARS, width_chars);

    // Maximum: stay under MAX_IMAGE_DIM (1024 pixels)
    const max_chars_for_dim = MAX_IMAGE_DIM / SCALE / char_width_px;
    width_chars = @min(width_chars, max_chars_for_dim);

    return width_chars;
}

// Palette color indices
const COLOR_WHITE: u8 = 0; // Background
const COLOR_GRAY: u8 = 2; // Whitespace indicators (#CCC)

/// Render text with role-based coloring
/// Returns a square-ish image optimized for LLM vision
pub fn renderTextWithRole(
    allocator: std.mem.Allocator,
    text: []const u8,
    role: api_types.Role,
) !RenderedText {
    const color = RoleColor.fromRole(role);
    const color_idx = color.toIndex();

    // Convert to single line with visual whitespace tracking
    const single_line = try toSingleLine(allocator, text);
    defer allocator.free(single_line.text);
    defer allocator.free(single_line.is_whitespace);

    // Calculate wrap width for square image
    const wrap_width = calculateWrapWidth(single_line.text.len);

    // Split into wrapped lines with whitespace tracking
    const LineInfo = struct {
        text: []const u8,
        is_ws: []const bool,
    };
    var lines = std.ArrayList(LineInfo){};
    defer lines.deinit(allocator);

    var pos: usize = 0;
    while (pos < single_line.text.len) {
        const line_len = @min(single_line.text.len - pos, wrap_width);
        try lines.append(allocator, .{
            .text = single_line.text[pos .. pos + line_len],
            .is_ws = single_line.is_whitespace[pos .. pos + line_len],
        });
        pos += line_len;
    }

    if (lines.items.len == 0) {
        try lines.append(allocator, .{ .text = "", .is_ws = &[_]bool{} });
    }

    // Calculate dimensions
    var max_line_len: usize = 0;
    for (lines.items) |line| {
        if (line.text.len > max_line_len) max_line_len = line.text.len;
    }

    const width = max_line_len * (CHAR_WIDTH + CHAR_SPACING);
    const height = lines.items.len * (CHAR_HEIGHT + LINE_SPACING);

    if (width == 0 or height == 0) {
        // Return 1x1 white pixel for empty text
        var pixels = try allocator.alloc([]u8, 1);
        pixels[0] = try allocator.alloc(u8, 1);
        pixels[0][0] = COLOR_WHITE;
        return RenderedText{
            .pixels = pixels,
            .width = 1,
            .height = 1,
            .allocator = allocator,
        };
    }

    // Allocate pixel array
    var pixels = try allocator.alloc([]u8, height);
    errdefer allocator.free(pixels);

    for (0..height) |y| {
        pixels[y] = try allocator.alloc(u8, width);
        @memset(pixels[y], COLOR_WHITE); // White background
    }

    // Render each line
    const font = font_5x7.Font5x7{};
    for (lines.items, 0..) |line, line_idx| {
        const y_offset = line_idx * (CHAR_HEIGHT + LINE_SPACING);

        for (line.text, 0..) |char, char_idx| {
            const x_offset = char_idx * (CHAR_WIDTH + CHAR_SPACING);

            // Determine color: gray for whitespace indicators, role color otherwise
            const char_color = if (char_idx < line.is_ws.len and line.is_ws[char_idx])
                COLOR_GRAY
            else
                color_idx;

            // Skip non-ASCII or render as box
            const display_char = if (char < 128) char else '?';

            // 5x7 font is column-major
            const glyph = font.getGlyph(display_char);
            for (0..CHAR_WIDTH) |col| {
                const col_data = glyph[col];
                for (0..CHAR_HEIGHT) |row| {
                    const bit = (col_data >> @intCast(row)) & 1;
                    if (bit == 1) {
                        pixels[y_offset + row][x_offset + col] = char_color;
                    }
                }
            }
        }
    }

    // Scale up for readability
    const scaled_width = width * SCALE;
    const scaled_height = height * SCALE;

    var scaled_pixels = try allocator.alloc([]u8, scaled_height);
    errdefer allocator.free(scaled_pixels);

    for (0..scaled_height) |sy| {
        scaled_pixels[sy] = try allocator.alloc(u8, scaled_width);

        const src_y = sy / SCALE;
        for (0..scaled_width) |sx| {
            const src_x = sx / SCALE;
            scaled_pixels[sy][sx] = pixels[src_y][src_x];
        }
    }

    // Free original unscaled pixels
    for (pixels) |row| {
        allocator.free(row);
    }
    allocator.free(pixels);

    return RenderedText{
        .pixels = scaled_pixels,
        .width = scaled_width,
        .height = scaled_height,
        .allocator = allocator,
    };
}

/// Render text with per-character role coloring
/// Each character uses the color of its corresponding role
pub fn renderTextWithRoles(
    allocator: std.mem.Allocator,
    text: []const u8,
    roles: []const api_types.Role,
) !RenderedText {
    // Convert to single line with visual whitespace and role tracking
    const single_line = try toSingleLineWithRoles(allocator, text, roles);
    defer allocator.free(single_line.text);
    defer allocator.free(single_line.is_whitespace);
    defer allocator.free(single_line.roles);

    // Calculate wrap width for square image
    const wrap_width = calculateWrapWidth(single_line.text.len);

    // Split into wrapped lines with whitespace and role tracking
    const LineInfo = struct {
        text: []const u8,
        is_ws: []const bool,
        roles: []const api_types.Role,
    };
    var lines = std.ArrayList(LineInfo){};
    defer lines.deinit(allocator);

    var pos: usize = 0;
    while (pos < single_line.text.len) {
        const line_len = @min(single_line.text.len - pos, wrap_width);
        try lines.append(allocator, .{
            .text = single_line.text[pos .. pos + line_len],
            .is_ws = single_line.is_whitespace[pos .. pos + line_len],
            .roles = single_line.roles[pos .. pos + line_len],
        });
        pos += line_len;
    }

    if (lines.items.len == 0) {
        try lines.append(allocator, .{ .text = "", .is_ws = &[_]bool{}, .roles = &[_]api_types.Role{} });
    }

    // Calculate dimensions
    var max_line_len: usize = 0;
    for (lines.items) |line| {
        if (line.text.len > max_line_len) max_line_len = line.text.len;
    }

    const width = max_line_len * (CHAR_WIDTH + CHAR_SPACING);
    const height = lines.items.len * (CHAR_HEIGHT + LINE_SPACING);

    if (width == 0 or height == 0) {
        // Return 1x1 white pixel for empty text
        var pixels = try allocator.alloc([]u8, 1);
        pixels[0] = try allocator.alloc(u8, 1);
        pixels[0][0] = COLOR_WHITE;
        return RenderedText{
            .pixels = pixels,
            .width = 1,
            .height = 1,
            .allocator = allocator,
        };
    }

    // Allocate pixel array
    var pixels = try allocator.alloc([]u8, height);
    errdefer allocator.free(pixels);

    for (0..height) |y| {
        pixels[y] = try allocator.alloc(u8, width);
        @memset(pixels[y], COLOR_WHITE); // White background
    }

    // Render each line
    const font = font_5x7.Font5x7{};
    for (lines.items, 0..) |line, line_idx| {
        const y_offset = line_idx * (CHAR_HEIGHT + LINE_SPACING);

        for (line.text, 0..) |char, char_idx| {
            const x_offset = char_idx * (CHAR_WIDTH + CHAR_SPACING);

            // Determine color: gray for whitespace indicators, otherwise role color
            const char_color = if (char_idx < line.is_ws.len and line.is_ws[char_idx])
                COLOR_GRAY
            else if (char_idx < line.roles.len)
                RoleColor.fromRole(line.roles[char_idx]).toIndex()
            else
                RoleColor.fromRole(.user).toIndex();

            // Skip non-ASCII or render as box
            const display_char = if (char < 128) char else '?';

            // 5x7 font is column-major
            const glyph = font.getGlyph(display_char);
            for (0..CHAR_WIDTH) |col| {
                const col_data = glyph[col];
                for (0..CHAR_HEIGHT) |row| {
                    const bit = (col_data >> @intCast(row)) & 1;
                    if (bit == 1) {
                        pixels[y_offset + row][x_offset + col] = char_color;
                    }
                }
            }
        }
    }

    // Scale up for readability
    const scaled_width = width * SCALE;
    const scaled_height = height * SCALE;

    var scaled_pixels = try allocator.alloc([]u8, scaled_height);
    errdefer allocator.free(scaled_pixels);

    for (0..scaled_height) |sy| {
        scaled_pixels[sy] = try allocator.alloc(u8, scaled_width);

        const src_y = sy / SCALE;
        for (0..scaled_width) |sx| {
            const src_x = sx / SCALE;
            scaled_pixels[sy][sx] = pixels[src_y][src_x];
        }
    }

    // Free original unscaled pixels
    for (pixels) |row| {
        allocator.free(row);
    }
    allocator.free(pixels);

    return RenderedText{
        .pixels = scaled_pixels,
        .width = scaled_width,
        .height = scaled_height,
        .allocator = allocator,
    };
}

/// Legacy function for backward compatibility
pub fn renderText(allocator: std.mem.Allocator, text: []const u8) !RenderedText {
    return renderTextWithRole(allocator, text, .user);
}

/// Helper function to print ASCII art for debugging
pub fn printAsciiArt(rendered: *const RenderedText) void {
    const chars = " #BGYRPxx"; // Palette: white, blue, green, yellow, red, purple
    for (rendered.pixels) |row| {
        for (row) |pixel| {
            const idx = @min(pixel, chars.len - 1);
            std.debug.print("{c}", .{chars[idx]});
        }
        std.debug.print("\n", .{});
    }
}

test "single line conversion" {
    const allocator = std.testing.allocator;
    const result = try toSingleLine(allocator, "Hello\nWorld\tTest");
    defer allocator.free(result.text);
    defer allocator.free(result.is_whitespace);
    defer allocator.free(result.roles);

    // Should contain visual indicators
    try std.testing.expect(result.text.len > 0);
}

test "render with role" {
    const allocator = std.testing.allocator;
    var rendered = try renderTextWithRole(allocator, "Hello", .user);
    defer rendered.deinit();

    try std.testing.expect(rendered.width > 0);
    try std.testing.expect(rendered.height > 0);
}
