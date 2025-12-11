/// _pyio.text - Text I/O wrapper
/// TextIOWrapper for encoding/decoding text streams

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const base = @import("base.zig");
const buffered = @import("buffered.zig");

// ============================================================================
// Text I/O
// ============================================================================

/// TextIOWrapper
pub const TextIOWrapper = struct {
    const Self = @This();

    base: base.IOBase,
    buffer: *buffered.BufferedReader,
    encoding: []const u8 = "utf-8",
    newline: types.TextNewline = .universal,
    line_buffering: bool = false,
    allocator: Allocator,

    pub fn init(allocator: Allocator, buffer_reader: *buffered.BufferedReader) Self {
        return Self{
            .allocator = allocator,
            .buffer = buffer_reader,
            .base = base.IOBase{
                .readable = buffer_reader.base.readable,
                .writable = buffer_reader.base.writable,
                .seekable = buffer_reader.base.seekable,
            },
        };
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        return self.buffer.read(dest);
    }

    pub fn readline(self: *Self, limit: ?usize) ![]u8 {
        return self.buffer.readline(self.allocator, limit);
    }
};
