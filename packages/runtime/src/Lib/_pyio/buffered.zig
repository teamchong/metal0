/// _pyio.buffered - Buffered I/O implementation
/// BufferedReader and BufferedWriter for efficient I/O

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const base = @import("base.zig");
const raw = @import("raw.zig");

// ============================================================================
// Buffered I/O
// ============================================================================

/// BufferedReader
pub const BufferedReader = struct {
    const Self = @This();

    base: base.IOBase,
    raw: *raw.FileIO,
    buffer: []u8,
    buf_start: usize = 0,
    buf_end: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, raw_io: *raw.FileIO, buffer_size: usize) !Self {
        const buffer = try allocator.alloc(u8, buffer_size);
        return Self{
            .allocator = allocator,
            .raw = raw_io,
            .buffer = buffer,
            .base = base.IOBase{
                .readable = true,
                .seekable = raw_io.base.seekable,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        var total: usize = 0;
        var remaining = dest;

        // Read from buffer first
        while (remaining.len > 0 and self.buf_start < self.buf_end) {
            remaining[0] = self.buffer[self.buf_start];
            self.buf_start += 1;
            remaining = remaining[1..];
            total += 1;
        }

        // Read directly for large requests
        if (remaining.len >= self.buffer.len) {
            total += try self.raw.read(remaining);
            return total;
        }

        // Fill buffer
        if (remaining.len > 0) {
            self.buf_start = 0;
            self.buf_end = try self.raw.read(self.buffer);

            while (remaining.len > 0 and self.buf_start < self.buf_end) {
                remaining[0] = self.buffer[self.buf_start];
                self.buf_start += 1;
                remaining = remaining[1..];
                total += 1;
            }
        }

        return total;
    }

    pub fn readline(self: *Self, allocator: Allocator, limit: ?usize) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        const max = limit orelse std.math.maxInt(usize);

        while (result.items.len < max) {
            // Ensure buffer has data
            if (self.buf_start >= self.buf_end) {
                self.buf_start = 0;
                self.buf_end = try self.raw.read(self.buffer);
                if (self.buf_end == 0) break; // EOF
            }

            const c = self.buffer[self.buf_start];
            self.buf_start += 1;
            try result.append(allocator, c);

            if (c == '\n') break;
        }

        return result.toOwnedSlice(allocator);
    }
};

/// BufferedWriter
pub const BufferedWriter = struct {
    const Self = @This();

    base: base.IOBase,
    raw: *raw.FileIO,
    buffer: []u8,
    buf_pos: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, raw_io: *raw.FileIO, buffer_size: usize) !Self {
        const buffer = try allocator.alloc(u8, buffer_size);
        return Self{
            .allocator = allocator,
            .raw = raw_io,
            .buffer = buffer,
            .base = base.IOBase{
                .writable = true,
                .seekable = raw_io.base.seekable,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        var total: usize = 0;
        var remaining = data;

        // Flush if buffer would overflow
        if (self.buf_pos + data.len > self.buffer.len) {
            try self.flush();
        }

        // Write directly for large data
        if (remaining.len >= self.buffer.len) {
            return try self.raw.write(remaining);
        }

        // Buffer the data
        while (remaining.len > 0 and self.buf_pos < self.buffer.len) {
            self.buffer[self.buf_pos] = remaining[0];
            self.buf_pos += 1;
            remaining = remaining[1..];
            total += 1;
        }

        return total;
    }

    pub fn flush(self: *Self) !void {
        if (self.buf_pos > 0) {
            _ = try self.raw.write(self.buffer[0..self.buf_pos]);
            self.buf_pos = 0;
        }
    }
};
