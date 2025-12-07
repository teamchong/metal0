//! Python '_pyrepl' module - Python REPL support
//!
//! Internal module providing REPL (Read-Eval-Print Loop) functionality.
//!
//! Mirrors: CPython Lib/_pyrepl/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const ReplError = error{
    SyntaxError,
    KeyboardInterrupt,
    EOFError,
    IoError,
    OutOfMemory,
};

// ============================================================================
// HistoryEntry
// ============================================================================

/// A single entry in command history
pub const HistoryEntry = struct {
    line: []const u8,
    timestamp: i64,
};

// ============================================================================
// History
// ============================================================================

/// Command history manager
pub const History = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    entries: std.ArrayList(HistoryEntry),
    max_size: usize = 1000,
    position: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .entries = std.ArrayList(HistoryEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.line);
        }
        self.entries.deinit();
    }

    /// Add an entry to history
    pub fn add(self: *Self, line: []const u8) !void {
        // Don't add empty lines
        if (line.len == 0) return;

        // Don't add duplicates of last entry
        if (self.entries.items.len > 0) {
            const last = self.entries.items[self.entries.items.len - 1];
            if (std.mem.eql(u8, last.line, line)) return;
        }

        // Remove oldest if at max size
        if (self.entries.items.len >= self.max_size) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.line);
        }

        try self.entries.append(.{
            .line = try self.allocator.dupe(u8, line),
            .timestamp = std.time.timestamp(),
        });

        self.position = self.entries.items.len;
    }

    /// Get previous entry (up arrow)
    pub fn previous(self: *Self) ?[]const u8 {
        if (self.position > 0) {
            self.position -= 1;
            return self.entries.items[self.position].line;
        }
        return null;
    }

    /// Get next entry (down arrow)
    pub fn next(self: *Self) ?[]const u8 {
        if (self.position < self.entries.items.len - 1) {
            self.position += 1;
            return self.entries.items[self.position].line;
        }
        self.position = self.entries.items.len;
        return null;
    }

    /// Search history backwards
    pub fn searchBackward(self: *Self, prefix: []const u8) ?[]const u8 {
        var i = self.position;
        while (i > 0) {
            i -= 1;
            if (std.mem.startsWith(u8, self.entries.items[i].line, prefix)) {
                self.position = i;
                return self.entries.items[i].line;
            }
        }
        return null;
    }

    /// Get entry count
    pub fn len(self: *const Self) usize {
        return self.entries.items.len;
    }

    /// Clear history
    pub fn clear(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.line);
        }
        self.entries.clearAndFree();
        self.position = 0;
    }
};

// ============================================================================
// LineBuffer
// ============================================================================

/// Editable line buffer
pub const LineBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    cursor: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Insert a character at cursor
    pub fn insert(self: *Self, c: u8) !void {
        try self.buffer.insert(self.cursor, c);
        self.cursor += 1;
    }

    /// Insert a string at cursor
    pub fn insertString(self: *Self, s: []const u8) !void {
        for (s) |c| {
            try self.insert(c);
        }
    }

    /// Delete character before cursor (backspace)
    pub fn backspace(self: *Self) void {
        if (self.cursor > 0) {
            _ = self.buffer.orderedRemove(self.cursor - 1);
            self.cursor -= 1;
        }
    }

    /// Delete character at cursor (delete)
    pub fn delete(self: *Self) void {
        if (self.cursor < self.buffer.items.len) {
            _ = self.buffer.orderedRemove(self.cursor);
        }
    }

    /// Move cursor left
    pub fn moveLeft(self: *Self) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Move cursor right
    pub fn moveRight(self: *Self) void {
        if (self.cursor < self.buffer.items.len) {
            self.cursor += 1;
        }
    }

    /// Move cursor to start
    pub fn moveStart(self: *Self) void {
        self.cursor = 0;
    }

    /// Move cursor to end
    pub fn moveEnd(self: *Self) void {
        self.cursor = self.buffer.items.len;
    }

    /// Clear the buffer
    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.cursor = 0;
    }

    /// Set buffer content
    pub fn set(self: *Self, content: []const u8) !void {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(content);
        self.cursor = self.buffer.items.len;
    }

    /// Get buffer content as slice
    pub fn getContent(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Kill to end of line
    pub fn killToEnd(self: *Self) []const u8 {
        const killed = self.buffer.items[self.cursor..];
        self.buffer.shrinkRetainingCapacity(self.cursor);
        return killed;
    }
};

// ============================================================================
// Reader
// ============================================================================

/// REPL input reader
pub const Reader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    history: History,
    buffer: LineBuffer,
    prompt: []const u8 = ">>> ",
    continuation_prompt: []const u8 = "... ",

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .history = History.init(allocator),
            .buffer = LineBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.history.deinit();
        self.buffer.deinit();
    }

    /// Read a line of input
    pub fn readline(self: *Self) ![]u8 {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        try stdout.writeAll(self.prompt);

        self.buffer.clear();

        while (true) {
            const byte = stdin.readByte() catch |err| {
                if (err == error.EndOfStream) return error.EOFError;
                return error.IoError;
            };

            switch (byte) {
                '\n', '\r' => {
                    try stdout.writeByte('\n');
                    const content = self.buffer.getContent();
                    try self.history.add(content);
                    return try self.allocator.dupe(u8, content);
                },
                127, '\x08' => { // Backspace
                    if (self.buffer.cursor > 0) {
                        self.buffer.backspace();
                        try stdout.writeAll("\x08 \x08");
                    }
                },
                '\x03' => { // Ctrl+C
                    return error.KeyboardInterrupt;
                },
                '\x04' => { // Ctrl+D
                    if (self.buffer.buffer.items.len == 0) {
                        return error.EOFError;
                    }
                },
                else => {
                    if (byte >= 32 and byte < 127) {
                        try self.buffer.insert(byte);
                        try stdout.writeByte(byte);
                    }
                },
            }
        }
    }
};

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

test "History add and previous" {
    const allocator = std.testing.allocator;
    var history = History.init(allocator);
    defer history.deinit();

    try history.add("first");
    try history.add("second");
    try history.add("third");

    try std.testing.expectEqual(@as(usize, 3), history.len());

    const prev = history.previous();
    try std.testing.expectEqualStrings("third", prev.?);
}

test "History skip duplicates" {
    const allocator = std.testing.allocator;
    var history = History.init(allocator);
    defer history.deinit();

    try history.add("command");
    try history.add("command");
    try history.add("command");

    try std.testing.expectEqual(@as(usize, 1), history.len());
}

test "History skip empty" {
    const allocator = std.testing.allocator;
    var history = History.init(allocator);
    defer history.deinit();

    try history.add("");
    try std.testing.expectEqual(@as(usize, 0), history.len());
}

test "LineBuffer insert" {
    const allocator = std.testing.allocator;
    var buf = LineBuffer.init(allocator);
    defer buf.deinit();

    try buf.insertString("hello");
    try std.testing.expectEqualStrings("hello", buf.getContent());
    try std.testing.expectEqual(@as(usize, 5), buf.cursor);
}

test "LineBuffer backspace" {
    const allocator = std.testing.allocator;
    var buf = LineBuffer.init(allocator);
    defer buf.deinit();

    try buf.insertString("hello");
    buf.backspace();
    try std.testing.expectEqualStrings("hell", buf.getContent());
}

test "LineBuffer cursor movement" {
    const allocator = std.testing.allocator;
    var buf = LineBuffer.init(allocator);
    defer buf.deinit();

    try buf.insertString("hello");
    buf.moveStart();
    try std.testing.expectEqual(@as(usize, 0), buf.cursor);

    buf.moveEnd();
    try std.testing.expectEqual(@as(usize, 5), buf.cursor);

    buf.moveLeft();
    try std.testing.expectEqual(@as(usize, 4), buf.cursor);
}

test "Reader init" {
    const allocator = std.testing.allocator;
    var reader = Reader.init(allocator);
    defer reader.deinit();

    try std.testing.expectEqualStrings(">>> ", reader.prompt);
}
