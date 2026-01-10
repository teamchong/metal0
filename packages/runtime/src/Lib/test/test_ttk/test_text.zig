//! test.test_ttk.test_text - Tk text widget tests
const std = @import("std");

/// Text index position
pub const TextIndex = struct {
    line: u32,
    column: u32,

    pub fn init(line: u32, column: u32) TextIndex {
        return .{ .line = line, .column = column };
    }

    pub fn compare(self: TextIndex, other: TextIndex) std.math.Order {
        if (self.line < other.line) return .lt;
        if (self.line > other.line) return .gt;
        if (self.column < other.column) return .lt;
        if (self.column > other.column) return .gt;
        return .eq;
    }

    pub fn format(self: TextIndex, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{d}.{d}", .{ self.line, self.column });
    }
};

/// Text range
pub const TextRange = struct {
    start: TextIndex,
    end: TextIndex,

    pub fn init(start: TextIndex, end: TextIndex) TextRange {
        return .{ .start = start, .end = end };
    }

    pub fn contains(self: TextRange, index: TextIndex) bool {
        return self.start.compare(index) != .gt and
            self.end.compare(index) != .lt;
    }
};

/// Text tag for styling
pub const TextTag = struct {
    name: []const u8,
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    font: ?[]const u8 = null,
    underline: bool = false,
    overstrike: bool = false,
    justify: Justify = .left,

    pub const Justify = enum { left, center, right };

    pub fn init(name: []const u8) TextTag {
        return .{ .name = name };
    }

    pub fn withForeground(self: TextTag, color: []const u8) TextTag {
        var copy = self;
        copy.foreground = color;
        return copy;
    }

    pub fn withBackground(self: TextTag, color: []const u8) TextTag {
        var copy = self;
        copy.background = color;
        return copy;
    }
};

/// Text widget buffer
pub const TextBuffer = struct {
    lines: std.ArrayList([]u8),
    allocator: std.mem.Allocator,
    modified: bool = false,

    pub fn init(allocator: std.mem.Allocator) TextBuffer {
        return .{
            .lines = std.ArrayList([]u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextBuffer) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit();
    }

    pub fn lineCount(self: *const TextBuffer) usize {
        return self.lines.items.len;
    }

    pub fn getLine(self: *const TextBuffer, index: usize) ?[]const u8 {
        if (index < self.lines.items.len) {
            return self.lines.items[index];
        }
        return null;
    }

    pub fn insert(self: *TextBuffer, pos: TextIndex, text: []const u8) !void {
        _ = pos;
        const copy = try self.allocator.dupe(u8, text);
        try self.lines.append(copy);
        self.modified = true;
    }

    pub fn delete(self: *TextBuffer, start: TextIndex, end: TextIndex) !void {
        _ = start;
        _ = end;
        self.modified = true;
    }

    pub fn getText(self: *TextBuffer, start: TextIndex, end: TextIndex) ![]u8 {
        _ = start;
        _ = end;
        return try self.allocator.dupe(u8, "");
    }
};

/// Search options for text
pub const SearchOptions = struct {
    pattern: []const u8,
    regexp: bool = false,
    nocase: bool = false,
    forwards: bool = true,
    backwards: bool = false,
    exact: bool = false,
};

/// Text undo/redo manager
pub const UndoManager = struct {
    undo_stack: std.ArrayList(Action),
    redo_stack: std.ArrayList(Action),
    allocator: std.mem.Allocator,

    const Action = struct {
        kind: enum { insert, delete },
        start: TextIndex,
        end: TextIndex,
        text: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) UndoManager {
        return .{
            .undo_stack = std.ArrayList(Action).init(allocator),
            .redo_stack = std.ArrayList(Action).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UndoManager) void {
        self.undo_stack.deinit();
        self.redo_stack.deinit();
    }

    pub fn canUndo(self: *const UndoManager) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn canRedo(self: *const UndoManager) bool {
        return self.redo_stack.items.len > 0;
    }
};

test "TextIndex creation" {
    const idx = TextIndex.init(1, 0);
    try std.testing.expectEqual(@as(u32, 1), idx.line);
    try std.testing.expectEqual(@as(u32, 0), idx.column);
}

test "TextIndex comparison" {
    const idx1 = TextIndex.init(1, 5);
    const idx2 = TextIndex.init(1, 10);
    const idx3 = TextIndex.init(2, 0);

    try std.testing.expectEqual(std.math.Order.lt, idx1.compare(idx2));
    try std.testing.expectEqual(std.math.Order.lt, idx1.compare(idx3));
    try std.testing.expectEqual(std.math.Order.eq, idx1.compare(idx1));
}

test "TextRange contains" {
    const range = TextRange.init(
        TextIndex.init(1, 0),
        TextIndex.init(1, 10),
    );

    try std.testing.expect(range.contains(TextIndex.init(1, 5)));
    try std.testing.expect(!range.contains(TextIndex.init(2, 0)));
}

test "TextTag creation" {
    const tag = TextTag.init("highlight")
        .withForeground("red")
        .withBackground("yellow");

    try std.testing.expectEqualStrings("highlight", tag.name);
    try std.testing.expectEqualStrings("red", tag.foreground.?);
    try std.testing.expectEqualStrings("yellow", tag.background.?);
}

test "TextBuffer basic" {
    const allocator = std.testing.allocator;
    var buf = TextBuffer.init(allocator);
    defer buf.deinit();

    try buf.insert(TextIndex.init(0, 0), "Hello");
    try std.testing.expectEqual(@as(usize, 1), buf.lineCount());
    try std.testing.expect(buf.modified);
}

test "UndoManager" {
    const allocator = std.testing.allocator;
    var undo = UndoManager.init(allocator);
    defer undo.deinit();

    try std.testing.expect(!undo.canUndo());
    try std.testing.expect(!undo.canRedo());
}
