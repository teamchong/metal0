/// _pyio.types - Core types and constants for Python I/O
/// Defines IOMode, SeekWhence, IOError, and buffer constants

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default buffer size (same as Python)
pub const DEFAULT_BUFFER_SIZE: usize = 8192;

// ============================================================================
// I/O Mode
// ============================================================================

/// File open mode
pub const IOMode = struct {
    read: bool = false,
    write: bool = false,
    append: bool = false,
    create: bool = false,
    exclusive: bool = false,
    truncate: bool = false,
    binary: bool = false,
    text: bool = true,
    update: bool = false,

    /// Parse Python mode string
    pub fn parse(mode: []const u8) !IOMode {
        var result = IOMode{};

        for (mode) |c| {
            switch (c) {
                'r' => result.read = true,
                'w' => {
                    result.write = true;
                    result.create = true;
                    result.truncate = true;
                },
                'a' => {
                    result.append = true;
                    result.create = true;
                },
                'x' => {
                    result.write = true;
                    result.create = true;
                    result.exclusive = true;
                },
                'b' => {
                    result.binary = true;
                    result.text = false;
                },
                't' => result.text = true,
                '+' => result.update = true,
                else => return error.InvalidMode,
            }
        }

        // Default to read if no mode specified
        if (!result.read and !result.write and !result.append) {
            result.read = true;
        }

        // Update mode adds read capability
        if (result.update) {
            result.read = true;
            if (!result.write and !result.append) {
                result.write = true;
            }
        }

        return result;
    }
};

// ============================================================================
// Seek Whence
// ============================================================================

/// Seek origin
pub const SeekWhence = enum(u8) {
    set = 0, // SEEK_SET - beginning of file
    cur = 1, // SEEK_CUR - current position
    end = 2, // SEEK_END - end of file

    pub fn fromInt(n: u8) ?SeekWhence {
        return switch (n) {
            0 => .set,
            1 => .cur,
            2 => .end,
            else => null,
        };
    }
};

// ============================================================================
// I/O Errors
// ============================================================================

/// I/O error types
pub const IOError = error{
    FileNotFound,
    PermissionDenied,
    FileExists,
    NotReadable,
    NotWritable,
    NotSeekable,
    Closed,
    InvalidMode,
    BufferOverflow,
    EndOfFile,
};

// ============================================================================
// Text I/O Types
// ============================================================================

/// Text wrapping mode
pub const TextNewline = enum {
    universal, // Translate all newlines to \n on read
    native, // Use native line endings
    lf, // Unix style \n
    crlf, // Windows style \r\n
    cr, // Old Mac style \r
};

// ============================================================================
// Tests
// ============================================================================

test "parse mode" {
    const r = try IOMode.parse("r");
    try std.testing.expect(r.read);
    try std.testing.expect(!r.write);
    try std.testing.expect(r.text);

    const wb = try IOMode.parse("wb");
    try std.testing.expect(wb.write);
    try std.testing.expect(wb.binary);
    try std.testing.expect(!wb.text);

    const rp = try IOMode.parse("r+");
    try std.testing.expect(rp.read);
    try std.testing.expect(rp.write);
    try std.testing.expect(rp.update);
}

test "seek whence" {
    try std.testing.expectEqual(SeekWhence.set, SeekWhence.fromInt(0).?);
    try std.testing.expectEqual(SeekWhence.cur, SeekWhence.fromInt(1).?);
    try std.testing.expectEqual(SeekWhence.end, SeekWhence.fromInt(2).?);
    try std.testing.expect(SeekWhence.fromInt(3) == null);
}
