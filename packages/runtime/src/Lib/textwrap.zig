//! CPython source: Lib/textwrap.py
//!
//! Provides text formatting utilities for wrapping and filling text.
//!
//! Mirrors: CPython Lib/textwrap.py

const std = @import("std");

/// Default width for wrapping
pub const DEFAULT_WIDTH = 70;

/// Wrap a single paragraph of text
pub fn wrap(allocator: std.mem.Allocator, text: []const u8, options: WrapOptions) ![][]const u8 {
    var wrapper = TextWrapper.init(allocator, options);
    return wrapper.wrap(text);
}

/// Wrap and join with newlines
pub fn fill(allocator: std.mem.Allocator, text: []const u8, options: WrapOptions) ![]u8 {
    const lines = try wrap(allocator, text, options);
    defer {
        for (lines) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }

    return joinLines(allocator, lines);
}

/// Shorten text to fit in given width with placeholder
pub fn shorten(allocator: std.mem.Allocator, text: []const u8, width: usize, placeholder: []const u8) ![]u8 {
    if (text.len <= width) {
        return allocator.dupe(u8, text);
    }

    if (width <= placeholder.len) {
        return allocator.dupe(u8, placeholder[0..width]);
    }

    const content_width = width - placeholder.len;

    // Find last space before content_width
    var end = content_width;
    while (end > 0 and text[end - 1] != ' ') {
        end -= 1;
    }

    // If no space found, just truncate
    if (end == 0) {
        end = content_width;
    } else {
        // Remove trailing space
        while (end > 0 and text[end - 1] == ' ') {
            end -= 1;
        }
    }

    var result = try allocator.alloc(u8, end + placeholder.len);
    @memcpy(result[0..end], text[0..end]);
    @memcpy(result[end..], placeholder);

    return result;
}

/// Remove leading whitespace from every line
pub fn dedent(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (text.len == 0) return allocator.dupe(u8, "");

    // Find minimum indentation (ignoring blank lines)
    var min_indent: ?usize = null;
    var line_start: usize = 0;

    for (text, 0..) |c, i| {
        if (c == '\n') {
            if (line_start < i) {
                const line_indent = countIndent(text[line_start..i]);
                if (line_indent < i - line_start) { // Not a blank line
                    if (min_indent) |mi| {
                        min_indent = @min(mi, line_indent);
                    } else {
                        min_indent = line_indent;
                    }
                }
            }
            line_start = i + 1;
        }
    }

    // Handle last line
    if (line_start < text.len) {
        const line_indent = countIndent(text[line_start..]);
        if (line_indent < text.len - line_start) {
            if (min_indent) |mi| {
                min_indent = @min(mi, line_indent);
            } else {
                min_indent = line_indent;
            }
        }
    }

    const remove = min_indent orelse 0;
    if (remove == 0) return allocator.dupe(u8, text);

    // Build result with dedented lines
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    line_start = 0;
    for (text, 0..) |c, i| {
        if (c == '\n') {
            const line = text[line_start..i];
            const skip = @min(countIndent(line), remove);
            try result.appendSlice(allocator, line[skip..]);
            try result.append(allocator, '\n');
            line_start = i + 1;
        }
    }

    // Handle last line
    if (line_start < text.len) {
        const line = text[line_start..];
        const skip = @min(countIndent(line), remove);
        try result.appendSlice(allocator, line[skip..]);
    }

    return result.toOwnedSlice(allocator);
}

/// Add prefix to beginning of every line
pub fn indent(allocator: std.mem.Allocator, text: []const u8, prefix: []const u8) ![]u8 {
    return indentWithPredicate(allocator, text, prefix, null);
}

/// Add prefix to lines matching predicate
pub fn indentWithPredicate(
    allocator: std.mem.Allocator,
    text: []const u8,
    prefix: []const u8,
    predicate: ?*const fn ([]const u8) bool,
) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var line_start: usize = 0;
    for (text, 0..) |c, i| {
        if (c == '\n') {
            const line = text[line_start..i];
            if (shouldIndent(line, predicate)) {
                try result.appendSlice(allocator, prefix);
            }
            try result.appendSlice(allocator, line);
            try result.append(allocator, '\n');
            line_start = i + 1;
        }
    }

    // Handle last line
    if (line_start < text.len) {
        const line = text[line_start..];
        if (shouldIndent(line, predicate)) {
            try result.appendSlice(allocator, prefix);
        }
        try result.appendSlice(allocator, line);
    }

    return result.toOwnedSlice(allocator);
}

fn shouldIndent(line: []const u8, predicate: ?*const fn ([]const u8) bool) bool {
    if (predicate) |p| {
        return p(line);
    }
    // Default: indent non-whitespace lines
    for (line) |c| {
        if (c != ' ' and c != '\t') return true;
    }
    return false;
}

fn countIndent(line: []const u8) usize {
    var count: usize = 0;
    for (line) |c| {
        if (c == ' ') {
            count += 1;
        } else if (c == '\t') {
            count += 8; // Tab = 8 spaces
        } else {
            break;
        }
    }
    return count;
}

fn joinLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]u8 {
    if (lines.len == 0) return allocator.dupe(u8, "");

    var total_len: usize = 0;
    for (lines) |line| {
        total_len += line.len + 1;
    }
    total_len -= 1; // No newline after last line

    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (lines, 0..) |line, i| {
        @memcpy(result[pos..][0..line.len], line);
        pos += line.len;
        if (i < lines.len - 1) {
            result[pos] = '\n';
            pos += 1;
        }
    }

    return result;
}

// ============================================================================
// TextWrapper
// ============================================================================

pub const WrapOptions = struct {
    width: usize = DEFAULT_WIDTH,
    initial_indent: []const u8 = "",
    subsequent_indent: []const u8 = "",
    expand_tabs: bool = true,
    tab_size: usize = 8,
    replace_whitespace: bool = true,
    drop_whitespace: bool = true,
    break_long_words: bool = true,
    break_on_hyphens: bool = true,
};

pub const TextWrapper = struct {
    allocator: std.mem.Allocator,
    options: WrapOptions,

    pub fn init(allocator: std.mem.Allocator, options: WrapOptions) TextWrapper {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn wrap(self: *TextWrapper, text: []const u8) ![][]const u8 {
        var lines: std.ArrayList([]const u8) = .{};
        errdefer {
            for (lines.items) |line| {
                self.allocator.free(line);
            }
            lines.deinit(self.allocator);
        }

        // Preprocess text
        var processed: std.ArrayList(u8) = .{};
        defer processed.deinit(self.allocator);

        for (text) |c| {
            if (self.options.expand_tabs and c == '\t') {
                for (0..self.options.tab_size) |_| {
                    try processed.append(self.allocator, ' ');
                }
            } else if (self.options.replace_whitespace and (c == '\n' or c == '\r')) {
                try processed.append(self.allocator, ' ');
            } else {
                try processed.append(self.allocator, c);
            }
        }

        const processed_text = processed.items;

        // Split into words
        var words: std.ArrayList([]const u8) = .{};
        defer words.deinit(self.allocator);

        var word_start: ?usize = null;
        for (processed_text, 0..) |c, i| {
            if (c == ' ') {
                if (word_start) |start| {
                    try words.append(self.allocator, processed_text[start..i]);
                    word_start = null;
                }
            } else {
                if (word_start == null) {
                    word_start = i;
                }
            }
        }
        if (word_start) |start| {
            try words.append(self.allocator, processed_text[start..]);
        }

        // Build lines
        var current_line: std.ArrayList(u8) = .{};
        defer current_line.deinit(self.allocator);

        const initial_indent = self.options.initial_indent;
        const subsequent_indent = self.options.subsequent_indent;
        var is_first_line = true;

        for (words.items) |word| {
            const current_indent = if (is_first_line) initial_indent else subsequent_indent;
            const space_needed: usize = if (current_line.items.len == 0) 0 else 1;

            if (current_line.items.len + space_needed + word.len + current_indent.len <= self.options.width or current_line.items.len == 0) {
                if (current_line.items.len > 0) {
                    try current_line.append(self.allocator, ' ');
                }
                try current_line.appendSlice(self.allocator, word);
            } else {
                // Finish current line
                var line = try self.allocator.alloc(u8, current_indent.len + current_line.items.len);
                @memcpy(line[0..current_indent.len], current_indent);
                @memcpy(line[current_indent.len..], current_line.items);
                try lines.append(self.allocator, line);

                is_first_line = false;
                current_line.clearRetainingCapacity();
                try current_line.appendSlice(self.allocator, word);
            }
        }

        // Add final line
        if (current_line.items.len > 0) {
            const current_indent = if (is_first_line) initial_indent else subsequent_indent;
            var line = try self.allocator.alloc(u8, current_indent.len + current_line.items.len);
            @memcpy(line[0..current_indent.len], current_indent);
            @memcpy(line[current_indent.len..], current_line.items);
            try lines.append(self.allocator, line);
        }

        return lines.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "wrap basic" {
    const allocator = std.testing.allocator;
    const text = "Hello world this is a test";

    const lines = try wrap(allocator, text, .{ .width = 10 });
    defer {
        for (lines) |line| allocator.free(line);
        allocator.free(lines);
    }

    try std.testing.expectEqual(@as(usize, 4), lines.len);
}

test "fill basic" {
    const allocator = std.testing.allocator;
    const text = "Hello world";

    const result = try fill(allocator, text, .{ .width = 5 });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello\nworld", result);
}

test "shorten" {
    const allocator = std.testing.allocator;

    const result = try shorten(allocator, "Hello beautiful world!", 15, "...");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello...", result);
}

test "shorten short text" {
    const allocator = std.testing.allocator;

    const result = try shorten(allocator, "Hello", 10, "...");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello", result);
}

test "dedent" {
    const allocator = std.testing.allocator;

    const text =
        \\    Hello
        \\    World
    ;

    const result = try dedent(allocator, text);
    defer allocator.free(result);

    const expected =
        \\Hello
        \\World
    ;

    try std.testing.expectEqualStrings(expected, result);
}

test "indent" {
    const allocator = std.testing.allocator;

    const text =
        \\Hello
        \\World
    ;

    const result = try indent(allocator, text, "  ");
    defer allocator.free(result);

    const expected =
        \\  Hello
        \\  World
    ;

    try std.testing.expectEqualStrings(expected, result);
}

test "wrap with indent" {
    const allocator = std.testing.allocator;
    const text = "Hello world this is a test";

    const lines = try wrap(allocator, text, .{
        .width = 15,
        .initial_indent = "* ",
        .subsequent_indent = "  ",
    });
    defer {
        for (lines) |line| allocator.free(line);
        allocator.free(lines);
    }

    try std.testing.expect(lines.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, lines[0], "* "));
    if (lines.len > 1) {
        try std.testing.expect(std.mem.startsWith(u8, lines[1], "  "));
    }
}
