//! test.test_tkinter.test_text - Tk text tests
//! Tests for tkinter Text widget operations

const std = @import("std");
const testing = std.testing;

/// Text index representation (line.char format)
pub const TextIndex = struct {
    line: u32,
    char_pos: u32,

    pub fn init(line: u32, char_pos: u32) TextIndex {
        return .{ .line = line, .char_pos = char_pos };
    }

    pub fn start() TextIndex {
        return .{ .line = 1, .char_pos = 0 };
    }

    pub fn end() TextIndex {
        return .{ .line = std.math.maxInt(u32), .char_pos = 0 };
    }

    pub fn compare(self: TextIndex, other: TextIndex) i32 {
        if (self.line < other.line) return -1;
        if (self.line > other.line) return 1;
        if (self.char_pos < other.char_pos) return -1;
        if (self.char_pos > other.char_pos) return 1;
        return 0;
    }

    pub fn format(self: TextIndex, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d}.{d}", .{ self.line, self.char_pos }) catch "";
    }

    pub fn parse(str: []const u8) !TextIndex {
        var it = std.mem.splitSequence(u8, str, ".");
        const line_str = it.next() orelse return error.InvalidIndex;
        const char_str = it.next() orelse return error.InvalidIndex;

        return .{
            .line = std.fmt.parseInt(u32, line_str, 10) catch return error.InvalidIndex,
            .char_pos = std.fmt.parseInt(u32, char_str, 10) catch return error.InvalidIndex,
        };
    }
};

/// Text tag configuration
pub const TextTag = struct {
    name: []const u8,
    config: TagConfig = .{},
    ranges: std.ArrayList(TextRange),
    allocator: std.mem.Allocator,

    pub const TagConfig = struct {
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        font: ?[]const u8 = null,
        underline: bool = false,
        overstrike: bool = false,
        justify: Justify = .left,
        lmargin1: u32 = 0,
        lmargin2: u32 = 0,
        rmargin: u32 = 0,
        spacing1: u32 = 0,
        spacing2: u32 = 0,
        spacing3: u32 = 0,
        wrap: WrapMode = .char,
        relief: []const u8 = "flat",
        borderwidth: u32 = 0,
        elide: bool = false,

        pub const Justify = enum { left, right, center };
        pub const WrapMode = enum { none, char, word };
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) TextTag {
        return .{
            .name = name,
            .ranges = std.ArrayList(TextRange).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextTag) void {
        self.ranges.deinit();
    }

    pub fn addRange(self: *TextTag, start: TextIndex, end_idx: TextIndex) !void {
        try self.ranges.append(.{ .start = start, .end = end_idx });
    }

    pub fn removeRange(self: *TextTag, start: TextIndex, end_idx: TextIndex) void {
        var i: usize = 0;
        while (i < self.ranges.items.len) {
            const r = self.ranges.items[i];
            if (r.start.compare(start) >= 0 and r.end.compare(end_idx) <= 0) {
                _ = self.ranges.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

/// Text range (start to end)
pub const TextRange = struct {
    start: TextIndex,
    end: TextIndex,

    pub fn contains(self: TextRange, index: TextIndex) bool {
        return index.compare(self.start) >= 0 and index.compare(self.end) < 0;
    }

    pub fn overlaps(self: TextRange, other: TextRange) bool {
        return !(self.end.compare(other.start) <= 0 or self.start.compare(other.end) >= 0);
    }

    pub fn length(self: TextRange) u32 {
        if (self.start.line == self.end.line) {
            return self.end.char_pos - self.start.char_pos;
        }
        return 0; // Multi-line length requires content
    }
};

/// Text mark
pub const TextMark = struct {
    name: []const u8,
    index: TextIndex,
    gravity: Gravity = .right,

    pub const Gravity = enum { left, right };

    pub fn init(name: []const u8, index: TextIndex) TextMark {
        return .{ .name = name, .index = index };
    }
};

/// Undo/Redo entry
pub const UndoEntry = struct {
    operation: Operation,
    index: TextIndex,
    text: []const u8,
    timestamp: i64,

    pub const Operation = enum { insert, delete };
};

/// Text line data
pub const TextLine = struct {
    content: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TextLine {
        return .{
            .content = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextLine) void {
        self.content.deinit();
    }

    pub fn setText(self: *TextLine, text: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(text);
    }

    pub fn getText(self: *const TextLine) []const u8 {
        return self.content.items;
    }

    pub fn length(self: *const TextLine) usize {
        return self.content.items.len;
    }

    pub fn insert(self: *TextLine, pos: usize, text: []const u8) !void {
        const p = @min(pos, self.content.items.len);
        try self.content.insertSlice(p, text);
    }

    pub fn delete(self: *TextLine, start: usize, end_pos: usize) void {
        const s = @min(start, self.content.items.len);
        const e = @min(end_pos, self.content.items.len);
        if (s < e) {
            var count: usize = 0;
            while (count < e - s and s < self.content.items.len) : (count += 1) {
                _ = self.content.orderedRemove(s);
            }
        }
    }
};

/// Text widget
pub const TextWidget = struct {
    lines: std.ArrayList(TextLine),
    tags: std.StringHashMap(TextTag),
    marks: std.StringHashMap(TextMark),
    undo_stack: std.ArrayList(UndoEntry),
    redo_stack: std.ArrayList(UndoEntry),
    allocator: std.mem.Allocator,
    insert_mark: TextIndex = TextIndex.start(),
    wrap_mode: WrapMode = .char,
    state: State = .normal,
    undo_enabled: bool = true,
    max_undo: usize = 100,
    modified: bool = false,
    width: u32 = 80,
    height: u32 = 24,
    tabs: ?[]const u32 = null,

    pub const WrapMode = enum { none, char, word };
    pub const State = enum { normal, disabled };

    pub fn init(allocator: std.mem.Allocator) TextWidget {
        var tw = TextWidget{
            .lines = std.ArrayList(TextLine).init(allocator),
            .tags = std.StringHashMap(TextTag).init(allocator),
            .marks = std.StringHashMap(TextMark).init(allocator),
            .undo_stack = std.ArrayList(UndoEntry).init(allocator),
            .redo_stack = std.ArrayList(UndoEntry).init(allocator),
            .allocator = allocator,
        };
        // Initialize with one empty line
        var line = TextLine.init(allocator);
        tw.lines.append(line) catch {};
        return tw;
    }

    pub fn deinit(self: *TextWidget) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();

        var tag_it = self.tags.iterator();
        while (tag_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.tags.deinit();
        self.marks.deinit();
        self.undo_stack.deinit();
        self.redo_stack.deinit();
    }

    pub fn insert(self: *TextWidget, index: TextIndex, text: []const u8) !void {
        if (self.state == .disabled) return;

        const line_idx = @min(index.line - 1, @as(u32, @intCast(self.lines.items.len - 1)));

        // Handle newlines by splitting into multiple lines
        var lines_to_insert = std.ArrayList([]const u8).init(self.allocator);
        defer lines_to_insert.deinit();

        var start: usize = 0;
        for (text, 0..) |c, i| {
            if (c == '\n') {
                try lines_to_insert.append(text[start..i]);
                start = i + 1;
            }
        }
        try lines_to_insert.append(text[start..]);

        if (lines_to_insert.items.len == 1) {
            // Single line insert
            try self.lines.items[line_idx].insert(index.char_pos, text);
        } else {
            // Multi-line insert
            const original_line = self.lines.items[line_idx].getText();
            const before = original_line[0..@min(index.char_pos, original_line.len)];
            const after = if (index.char_pos < original_line.len) original_line[index.char_pos..] else "";

            // Modify first line
            try self.lines.items[line_idx].setText(before);
            try self.lines.items[line_idx].insert(before.len, lines_to_insert.items[0]);

            // Insert middle lines
            var insert_pos = line_idx + 1;
            for (lines_to_insert.items[1 .. lines_to_insert.items.len - 1]) |line_text| {
                var new_line = TextLine.init(self.allocator);
                try new_line.setText(line_text);
                try self.lines.insert(insert_pos, new_line);
                insert_pos += 1;
            }

            // Insert last line with remainder
            var last_line = TextLine.init(self.allocator);
            try last_line.setText(lines_to_insert.items[lines_to_insert.items.len - 1]);
            try last_line.insert(last_line.length(), after);
            try self.lines.insert(insert_pos, last_line);
        }

        self.modified = true;
    }

    pub fn delete(self: *TextWidget, start: TextIndex, end_idx: TextIndex) !void {
        if (self.state == .disabled) return;
        if (start.compare(end_idx) >= 0) return;

        const start_line = @min(start.line - 1, @as(u32, @intCast(self.lines.items.len - 1)));
        const end_line = @min(end_idx.line - 1, @as(u32, @intCast(self.lines.items.len - 1)));

        if (start_line == end_line) {
            // Single line delete
            self.lines.items[start_line].delete(start.char_pos, end_idx.char_pos);
        } else {
            // Multi-line delete
            const first_line_text = self.lines.items[start_line].getText();
            const last_line_text = self.lines.items[end_line].getText();

            const keep_start = first_line_text[0..@min(start.char_pos, first_line_text.len)];
            const keep_end = if (end_idx.char_pos < last_line_text.len) last_line_text[end_idx.char_pos..] else "";

            // Combine into first line
            try self.lines.items[start_line].setText(keep_start);
            try self.lines.items[start_line].insert(keep_start.len, keep_end);

            // Remove middle lines
            var i = end_line;
            while (i > start_line) : (i -= 1) {
                self.lines.items[i].deinit();
                _ = self.lines.orderedRemove(i);
            }
        }

        self.modified = true;
    }

    pub fn get(self: *const TextWidget, start: TextIndex, end_idx: ?TextIndex) []const u8 {
        const s_line = @min(start.line - 1, @as(u32, @intCast(self.lines.items.len - 1)));
        const e = end_idx orelse TextIndex.init(start.line, @as(u32, @intCast(self.lines.items[s_line].length())));
        const e_line = @min(e.line - 1, @as(u32, @intCast(self.lines.items.len - 1)));

        if (s_line == e_line) {
            const line = self.lines.items[s_line].getText();
            const s_pos = @min(start.char_pos, @as(u32, @intCast(line.len)));
            const e_pos = @min(e.char_pos, @as(u32, @intCast(line.len)));
            return line[s_pos..e_pos];
        }

        return ""; // Multi-line get would need buffer
    }

    pub fn lineCount(self: *const TextWidget) usize {
        return self.lines.items.len;
    }

    pub fn getLine(self: *const TextWidget, line_num: u32) ?[]const u8 {
        if (line_num == 0 or line_num > self.lines.items.len) return null;
        return self.lines.items[line_num - 1].getText();
    }

    pub fn search(self: *const TextWidget, pattern: []const u8, start: TextIndex, options: SearchOptions) ?TextIndex {
        const start_line = @min(start.line - 1, @as(u32, @intCast(self.lines.items.len - 1)));

        var line_idx: u32 = start_line;
        while (line_idx < self.lines.items.len) : (line_idx += 1) {
            const line = self.lines.items[line_idx].getText();
            const search_start = if (line_idx == start_line) start.char_pos else 0;

            if (options.nocase) {
                // Case-insensitive search would need lowercase comparison
                if (std.mem.indexOf(u8, line[search_start..], pattern)) |pos| {
                    return TextIndex.init(line_idx + 1, @as(u32, @intCast(search_start + pos)));
                }
            } else {
                if (std.mem.indexOf(u8, line[search_start..], pattern)) |pos| {
                    return TextIndex.init(line_idx + 1, @as(u32, @intCast(search_start + pos)));
                }
            }
        }

        return null;
    }

    pub const SearchOptions = struct {
        nocase: bool = false,
        backwards: bool = false,
        regexp: bool = false,
        exact: bool = true,
        elide: bool = false,
    };

    pub fn tagAdd(self: *TextWidget, tag_name: []const u8, start: TextIndex, end_idx: TextIndex) !void {
        const result = try self.tags.getOrPut(tag_name);
        if (!result.found_existing) {
            result.value_ptr.* = TextTag.init(self.allocator, tag_name);
        }
        try result.value_ptr.addRange(start, end_idx);
    }

    pub fn tagRemove(self: *TextWidget, tag_name: []const u8, start: TextIndex, end_idx: TextIndex) void {
        if (self.tags.getPtr(tag_name)) |tag| {
            tag.removeRange(start, end_idx);
        }
    }

    pub fn tagRanges(self: *const TextWidget, tag_name: []const u8) ?[]const TextRange {
        if (self.tags.get(tag_name)) |tag| {
            return tag.ranges.items;
        }
        return null;
    }

    pub fn tagConfigure(self: *TextWidget, tag_name: []const u8, config: TextTag.TagConfig) !void {
        const result = try self.tags.getOrPut(tag_name);
        if (!result.found_existing) {
            result.value_ptr.* = TextTag.init(self.allocator, tag_name);
        }
        result.value_ptr.config = config;
    }

    pub fn markSet(self: *TextWidget, mark_name: []const u8, index: TextIndex) !void {
        try self.marks.put(mark_name, TextMark.init(mark_name, index));
    }

    pub fn markUnset(self: *TextWidget, mark_name: []const u8) bool {
        return self.marks.remove(mark_name);
    }

    pub fn index(self: *const TextWidget, index_expr: []const u8) !TextIndex {
        if (std.mem.eql(u8, index_expr, "insert")) {
            return self.insert_mark;
        }
        if (std.mem.eql(u8, index_expr, "end")) {
            return TextIndex.init(@as(u32, @intCast(self.lines.items.len)), @as(u32, @intCast(self.lines.items[self.lines.items.len - 1].length())));
        }
        if (std.mem.eql(u8, index_expr, "1.0")) {
            return TextIndex.start();
        }

        // Check if it's a mark name
        if (self.marks.get(index_expr)) |mark| {
            return mark.index;
        }

        // Try to parse as line.char
        return TextIndex.parse(index_expr);
    }

    pub fn see(self: *TextWidget, idx: TextIndex) void {
        // Scroll to make index visible
        _ = self;
        _ = idx;
    }

    pub fn edit_undo(self: *TextWidget) !void {
        if (self.undo_stack.items.len == 0) return;
        const entry = self.undo_stack.pop();
        try self.redo_stack.append(entry);
        // Apply inverse operation
    }

    pub fn edit_redo(self: *TextWidget) !void {
        if (self.redo_stack.items.len == 0) return;
        const entry = self.redo_stack.pop();
        try self.undo_stack.append(entry);
        // Apply operation
    }

    pub fn edit_reset(self: *TextWidget) void {
        self.undo_stack.clearRetainingCapacity();
        self.redo_stack.clearRetainingCapacity();
    }

    pub fn edit_modified(self: *const TextWidget) bool {
        return self.modified;
    }

    pub fn edit_separator(self: *TextWidget) void {
        // Add undo group separator
        _ = self;
    }

    pub fn bbox(self: *const TextWidget, idx: TextIndex) ?struct { x: i32, y: i32, width: u32, height: u32 } {
        _ = self;
        _ = idx;
        // Return bounding box for character at index
        return .{ .x = 0, .y = 0, .width = 8, .height = 16 };
    }

    pub fn dlineinfo(self: *const TextWidget, idx: TextIndex) ?struct { x: i32, y: i32, width: u32, height: u32, baseline: u32 } {
        _ = self;
        _ = idx;
        return .{ .x = 0, .y = 0, .width = 640, .height = 16, .baseline = 12 };
    }

    pub fn count(self: *const TextWidget, start: TextIndex, end_idx: TextIndex, what: CountWhat) i64 {
        _ = what;
        if (start.line == end_idx.line) {
            return @as(i64, end_idx.char_pos) - @as(i64, start.char_pos);
        }

        var total: i64 = 0;
        var line_idx = start.line - 1;
        while (line_idx < end_idx.line and line_idx < self.lines.items.len) : (line_idx += 1) {
            const line_len = self.lines.items[line_idx].length();
            if (line_idx == start.line - 1) {
                total += @as(i64, @intCast(line_len)) - @as(i64, start.char_pos) + 1;
            } else if (line_idx == end_idx.line - 1) {
                total += end_idx.char_pos;
            } else {
                total += @as(i64, @intCast(line_len)) + 1;
            }
        }
        return total;
    }

    pub const CountWhat = enum { chars, displaychars, displayindices, displaylines, indices, lines, xpixels, ypixels };

    pub fn compare_indices(self: *const TextWidget, idx1: TextIndex, op: []const u8, idx2: TextIndex) bool {
        _ = self;
        const cmp = idx1.compare(idx2);
        if (std.mem.eql(u8, op, "<")) return cmp < 0;
        if (std.mem.eql(u8, op, "<=")) return cmp <= 0;
        if (std.mem.eql(u8, op, "==")) return cmp == 0;
        if (std.mem.eql(u8, op, ">=")) return cmp >= 0;
        if (std.mem.eql(u8, op, ">")) return cmp > 0;
        if (std.mem.eql(u8, op, "!=")) return cmp != 0;
        return false;
    }
};

// Tests

test "text_index_basic" {
    const idx = TextIndex.init(1, 0);
    try testing.expectEqual(@as(u32, 1), idx.line);
    try testing.expectEqual(@as(u32, 0), idx.char_pos);
}

test "text_index_compare" {
    const idx1 = TextIndex.init(1, 5);
    const idx2 = TextIndex.init(1, 10);
    const idx3 = TextIndex.init(2, 0);

    try testing.expect(idx1.compare(idx2) < 0);
    try testing.expect(idx2.compare(idx1) > 0);
    try testing.expect(idx1.compare(idx3) < 0);
    try testing.expect(idx1.compare(idx1) == 0);
}

test "text_index_parse" {
    const idx = try TextIndex.parse("5.12");
    try testing.expectEqual(@as(u32, 5), idx.line);
    try testing.expectEqual(@as(u32, 12), idx.char_pos);
}

test "text_index_format" {
    const idx = TextIndex.init(3, 7);
    var buf: [32]u8 = undefined;
    const str = idx.format(&buf);
    try testing.expectEqualStrings("3.7", str);
}

test "text_range_contains" {
    const range = TextRange{ .start = TextIndex.init(1, 0), .end = TextIndex.init(1, 10) };

    try testing.expect(range.contains(TextIndex.init(1, 5)));
    try testing.expect(!range.contains(TextIndex.init(1, 10)));
    try testing.expect(!range.contains(TextIndex.init(2, 0)));
}

test "text_line_basic" {
    var line = TextLine.init(testing.allocator);
    defer line.deinit();

    try line.setText("Hello World");
    try testing.expectEqualStrings("Hello World", line.getText());
    try testing.expectEqual(@as(usize, 11), line.length());
}

test "text_line_insert" {
    var line = TextLine.init(testing.allocator);
    defer line.deinit();

    try line.setText("Hello");
    try line.insert(5, " World");
    try testing.expectEqualStrings("Hello World", line.getText());

    try line.insert(0, "Say ");
    try testing.expectEqualStrings("Say Hello World", line.getText());
}

test "text_line_delete" {
    var line = TextLine.init(testing.allocator);
    defer line.deinit();

    try line.setText("Hello World");
    line.delete(5, 11);
    try testing.expectEqualStrings("Hello", line.getText());

    line.delete(0, 2);
    try testing.expectEqualStrings("llo", line.getText());
}

test "text_widget_basic" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try testing.expectEqual(@as(usize, 1), tw.lineCount());
    try testing.expect(!tw.modified);
}

test "text_widget_insert" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello World");
    try testing.expectEqualStrings("Hello World", tw.getLine(1).?);
    try testing.expect(tw.modified);
}

test "text_widget_multiline_insert" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Line 1\nLine 2\nLine 3");
    try testing.expectEqual(@as(usize, 3), tw.lineCount());
    try testing.expectEqualStrings("Line 1", tw.getLine(1).?);
    try testing.expectEqualStrings("Line 2", tw.getLine(2).?);
}

test "text_widget_delete" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello World");
    try tw.delete(TextIndex.init(1, 0), TextIndex.init(1, 6));
    try testing.expectEqualStrings("World", tw.getLine(1).?);
}

test "text_widget_get" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello World");
    const text = tw.get(TextIndex.init(1, 0), TextIndex.init(1, 5));
    try testing.expectEqualStrings("Hello", text);
}

test "text_widget_search" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello World");
    const result = tw.search("World", TextIndex.start(), .{});
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 1), result.?.line);
    try testing.expectEqual(@as(u32, 6), result.?.char_pos);
}

test "text_widget_tags" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello World");
    try tw.tagAdd("highlight", TextIndex.init(1, 0), TextIndex.init(1, 5));

    const ranges = tw.tagRanges("highlight");
    try testing.expect(ranges != null);
    try testing.expectEqual(@as(usize, 1), ranges.?.len);
}

test "text_widget_marks" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.markSet("mymark", TextIndex.init(1, 5));

    const idx = try tw.index("mymark");
    try testing.expectEqual(@as(u32, 1), idx.line);
    try testing.expectEqual(@as(u32, 5), idx.char_pos);
}

test "text_widget_index_expressions" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello");

    const start = try tw.index("1.0");
    try testing.expectEqual(@as(u32, 1), start.line);
    try testing.expectEqual(@as(u32, 0), start.char_pos);

    const insert = try tw.index("insert");
    _ = insert; // Insert mark exists

    const end_idx = try tw.index("end");
    try testing.expectEqual(@as(u32, 1), end_idx.line);
}

test "text_widget_compare" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    const idx1 = TextIndex.init(1, 0);
    const idx2 = TextIndex.init(1, 5);

    try testing.expect(tw.compare_indices(idx1, "<", idx2));
    try testing.expect(tw.compare_indices(idx2, ">", idx1));
    try testing.expect(tw.compare_indices(idx1, "==", idx1));
    try testing.expect(tw.compare_indices(idx1, "!=", idx2));
}

test "text_widget_count" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Hello");
    const char_count = tw.count(TextIndex.init(1, 0), TextIndex.init(1, 5), .chars);
    try testing.expectEqual(@as(i64, 5), char_count);
}

test "text_tag_config" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.tagConfigure("bold", .{ .font = "Helvetica 12 bold", .foreground = "blue" });

    if (tw.tags.get("bold")) |tag| {
        try testing.expectEqualStrings("Helvetica 12 bold", tag.config.font.?);
        try testing.expectEqualStrings("blue", tag.config.foreground.?);
    }
}

test "text_widget_state" {
    var tw = TextWidget.init(testing.allocator);
    defer tw.deinit();

    try tw.insert(TextIndex.start(), "Initial");
    tw.state = .disabled;
    try tw.insert(TextIndex.start(), "Should not appear");
    try testing.expectEqualStrings("Initial", tw.getLine(1).?);
}
