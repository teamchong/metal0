/// _pyio - Python I/O Implementation
/// Mirrors cpython/Lib/_pyio.py
///
/// Pure Zig implementation of Python's buffered I/O classes.
/// Provides the underlying implementation for io module.

const std = @import("std");
const Allocator = std.mem.Allocator;

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
// Base I/O Interface
// ============================================================================

/// IOBase - abstract base for I/O classes
pub const IOBase = struct {
    const Self = @This();

    /// Whether the stream is closed
    closed: bool = false,
    /// Readable flag
    readable: bool = false,
    /// Writable flag
    writable: bool = false,
    /// Seekable flag
    seekable: bool = false,

    /// Close the stream
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Check if readable
    pub fn isReadable(self: *const Self) bool {
        return self.readable and !self.closed;
    }

    /// Check if writable
    pub fn isWritable(self: *const Self) bool {
        return self.writable and !self.closed;
    }

    /// Check if seekable
    pub fn isSeekable(self: *const Self) bool {
        return self.seekable and !self.closed;
    }

    /// Flush (no-op for base)
    pub fn flush(self: *Self) !void {
        if (self.closed) return error.Closed;
    }
};

// ============================================================================
// Raw I/O
// ============================================================================

/// FileIO - raw file I/O
pub const FileIO = struct {
    const Self = @This();

    base: IOBase,
    file: ?std.fs.File = null,
    name: []const u8 = "",
    mode: IOMode = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .base = IOBase{},
        };
    }

    pub fn open(self: *Self, path: []const u8, mode_str: []const u8) !void {
        const mode = try IOMode.parse(mode_str);
        self.mode = mode;
        self.name = path;

        var flags = std.fs.File.OpenFlags{};
        if (mode.read and !mode.write) {
            flags.mode = .read_only;
        } else if (mode.write and !mode.read) {
            flags.mode = .write_only;
        } else {
            flags.mode = .read_write;
        }

        const dir = std.fs.cwd();
        if (mode.create) {
            self.file = dir.createFile(path, .{
                .truncate = mode.truncate,
                .exclusive = mode.exclusive,
            }) catch |err| return mapError(err);
        } else {
            self.file = dir.openFile(path, flags) catch |err| return mapError(err);
        }

        self.base.readable = mode.read;
        self.base.writable = mode.write or mode.append;
        self.base.seekable = true;
    }

    pub fn close(self: *Self) void {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }
        self.base.close();
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        if (!self.base.isReadable()) return error.NotReadable;
        if (self.file) |f| {
            return f.read(buffer);
        }
        return error.Closed;
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        if (!self.base.isWritable()) return error.NotWritable;
        if (self.file) |f| {
            return f.write(data);
        }
        return error.Closed;
    }

    pub fn seek(self: *Self, offset: i64, whence: SeekWhence) !u64 {
        if (!self.base.isSeekable()) return error.NotSeekable;
        if (self.file) |f| {
            const std_whence: std.fs.File.SeekableStream.SeekFrom = switch (whence) {
                .set => .start,
                .cur => .{ .relative = offset },
                .end => .{ .end_offset = offset },
            };
            if (whence == .set) {
                f.seekTo(@intCast(offset)) catch return error.NotSeekable;
            } else {
                f.seekableStream().seekTo(@intCast(offset)) catch return error.NotSeekable;
            }
            return f.getPos() catch return error.NotSeekable;
        }
        return error.Closed;
    }

    pub fn tell(self: *Self) !u64 {
        if (self.file) |f| {
            return f.getPos() catch return error.NotSeekable;
        }
        return error.Closed;
    }

    fn mapError(err: anyerror) IOError {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.PermissionDenied,
            error.PathAlreadyExists => error.FileExists,
            else => error.PermissionDenied,
        };
    }
};

// ============================================================================
// Buffered I/O
// ============================================================================

/// Default buffer size (same as Python)
pub const DEFAULT_BUFFER_SIZE: usize = 8192;

/// BufferedReader
pub const BufferedReader = struct {
    const Self = @This();

    base: IOBase,
    raw: *FileIO,
    buffer: []u8,
    buf_start: usize = 0,
    buf_end: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, raw: *FileIO, buffer_size: usize) !Self {
        const buffer = try allocator.alloc(u8, buffer_size);
        return Self{
            .allocator = allocator,
            .raw = raw,
            .buffer = buffer,
            .base = IOBase{
                .readable = true,
                .seekable = raw.base.seekable,
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
        var result = std.ArrayList(u8).init(allocator);
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
            try result.append(c);

            if (c == '\n') break;
        }

        return result.toOwnedSlice();
    }
};

/// BufferedWriter
pub const BufferedWriter = struct {
    const Self = @This();

    base: IOBase,
    raw: *FileIO,
    buffer: []u8,
    buf_pos: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, raw: *FileIO, buffer_size: usize) !Self {
        const buffer = try allocator.alloc(u8, buffer_size);
        return Self{
            .allocator = allocator,
            .raw = raw,
            .buffer = buffer,
            .base = IOBase{
                .writable = true,
                .seekable = raw.base.seekable,
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

// ============================================================================
// Text I/O
// ============================================================================

/// Text wrapping mode
pub const TextNewline = enum {
    universal, // Translate all newlines to \n on read
    native, // Use native line endings
    lf, // Unix style \n
    crlf, // Windows style \r\n
    cr, // Old Mac style \r
};

/// TextIOWrapper
pub const TextIOWrapper = struct {
    const Self = @This();

    base: IOBase,
    buffer: *BufferedReader,
    encoding: []const u8 = "utf-8",
    newline: TextNewline = .universal,
    line_buffering: bool = false,
    allocator: Allocator,

    pub fn init(allocator: Allocator, buffer: *BufferedReader) Self {
        return Self{
            .allocator = allocator,
            .buffer = buffer,
            .base = IOBase{
                .readable = buffer.base.readable,
                .writable = buffer.base.writable,
                .seekable = buffer.base.seekable,
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

// ============================================================================
// String I/O
// ============================================================================

/// StringIO - in-memory text stream
pub const StringIO = struct {
    const Self = @This();

    base: IOBase,
    buffer: std.ArrayList(u8),
    pos: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, initial: ?[]const u8) !Self {
        var buffer = std.ArrayList(u8).init(allocator);
        if (initial) |data| {
            try buffer.appendSlice(data);
        }
        return Self{
            .allocator = allocator,
            .buffer = buffer,
            .base = IOBase{
                .readable = true,
                .writable = true,
                .seekable = true,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn getvalue(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    pub fn read(self: *Self, size: ?usize) []const u8 {
        const max_size = size orelse (self.buffer.items.len - self.pos);
        const end = @min(self.pos + max_size, self.buffer.items.len);
        const result = self.buffer.items[self.pos..end];
        self.pos = end;
        return result;
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        // Extend buffer if needed
        if (self.pos + data.len > self.buffer.items.len) {
            try self.buffer.resize(self.pos + data.len);
        }
        @memcpy(self.buffer.items[self.pos..][0..data.len], data);
        self.pos += data.len;
        return data.len;
    }

    pub fn seek(self: *Self, offset: i64, whence: SeekWhence) !u64 {
        const new_pos: i64 = switch (whence) {
            .set => offset,
            .cur => @as(i64, @intCast(self.pos)) + offset,
            .end => @as(i64, @intCast(self.buffer.items.len)) + offset,
        };
        if (new_pos < 0) return error.InvalidMode;
        self.pos = @intCast(new_pos);
        return self.pos;
    }

    pub fn tell(self: *const Self) u64 {
        return self.pos;
    }

    pub fn truncate(self: *Self, size: ?usize) !void {
        const new_size = size orelse self.pos;
        try self.buffer.resize(new_size);
        if (self.pos > new_size) {
            self.pos = new_size;
        }
    }
};

/// BytesIO - in-memory binary stream
pub const BytesIO = StringIO; // Same implementation for binary

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _pyio module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

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

test "io base" {
    var base = IOBase{ .readable = true, .writable = true };
    try std.testing.expect(base.isReadable());
    try std.testing.expect(base.isWritable());

    base.close();
    try std.testing.expect(!base.isReadable());
    try std.testing.expect(!base.isWritable());
}

test "string io" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.init(allocator, "hello");
    defer sio.deinit();

    try std.testing.expectEqualStrings("hello", sio.getvalue());

    const data = sio.read(3);
    try std.testing.expectEqualStrings("hel", data);
    try std.testing.expectEqual(@as(u64, 3), sio.tell());

    _ = try sio.write(" world");
    try std.testing.expectEqualStrings("hel world", sio.getvalue());
}

test "string io seek" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.init(allocator, "hello");
    defer sio.deinit();

    _ = try sio.seek(2, .set);
    try std.testing.expectEqual(@as(u64, 2), sio.tell());

    _ = try sio.seek(1, .cur);
    try std.testing.expectEqual(@as(u64, 3), sio.tell());

    _ = try sio.seek(-1, .end);
    try std.testing.expectEqual(@as(u64, 4), sio.tell());
}
