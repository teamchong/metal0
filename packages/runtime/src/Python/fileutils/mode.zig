/// mode - File Mode Parsing
/// Mirrors cpython/Python/fileutils.c file mode parsing
///
/// This module provides Python-style mode string parsing.

const std = @import("std");
const fd_ops = @import("fd_ops.zig");
const OpenFlags = fd_ops.OpenFlags;

// ============================================================================
// File Mode Parsing
// ============================================================================

/// Parse Python-style mode string
pub fn parseMode(mode: []const u8) OpenFlags {
    var flags = OpenFlags{};

    for (mode) |c| {
        switch (c) {
            'r' => flags.read = true,
            'w' => {
                flags.write = true;
                flags.create = true;
                flags.truncate = true;
            },
            'a' => {
                flags.write = true;
                flags.append = true;
                flags.create = true;
            },
            'x' => {
                flags.write = true;
                flags.create = true;
                flags.exclusive = true;
            },
            '+' => {
                flags.read = true;
                flags.write = true;
            },
            'b' => {
                flags.binary = true;
                flags.text = false;
            },
            't' => {
                flags.text = true;
                flags.binary = false;
            },
            else => {},
        }
    }

    // Default to read if nothing specified
    if (!flags.read and !flags.write) {
        flags.read = true;
    }

    return flags;
}

/// Convert mode flags to string
pub fn modeToString(flags: OpenFlags, buf: []u8) []const u8 {
    var pos: usize = 0;

    if (flags.read and !flags.write) {
        buf[pos] = 'r';
        pos += 1;
    } else if (flags.write and !flags.read) {
        if (flags.append) {
            buf[pos] = 'a';
        } else {
            buf[pos] = 'w';
        }
        pos += 1;
    } else if (flags.read and flags.write) {
        if (flags.append) {
            buf[pos] = 'a';
            pos += 1;
            buf[pos] = '+';
            pos += 1;
        } else {
            buf[pos] = 'r';
            pos += 1;
            buf[pos] = '+';
            pos += 1;
        }
    }

    if (flags.binary) {
        buf[pos] = 'b';
        pos += 1;
    }

    return buf[0..pos];
}

// ============================================================================
// Tests
// ============================================================================

test "mode parsing" {
    const read_mode = parseMode("r");
    try std.testing.expect(read_mode.read);
    try std.testing.expect(!read_mode.write);

    const write_mode = parseMode("w");
    try std.testing.expect(write_mode.write);
    try std.testing.expect(write_mode.create);
    try std.testing.expect(write_mode.truncate);

    const append_mode = parseMode("a+b");
    try std.testing.expect(append_mode.append);
    try std.testing.expect(append_mode.read);
    try std.testing.expect(append_mode.binary);
}
