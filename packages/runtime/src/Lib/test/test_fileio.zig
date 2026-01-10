//! test.test_fileio - FileIO tests
//! CPython Reference: https://docs.python.org/3.12/library/io.html#io.FileIO
//!
//! This module provides tests for raw FileIO operations, which provide
//! unbuffered access to files at the OS level in the Metal0 runtime.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// FileIO Error Types
// ============================================================================

/// Errors that can occur during FileIO operations
pub const FileIOError = error{
    /// File descriptor is invalid
    InvalidFileDescriptor,
    /// Operation not supported on this file type
    UnsupportedOperation,
    /// File is closed
    FileClosed,
    /// File is not readable
    NotReadable,
    /// File is not writable
    NotWritable,
    /// File is not seekable
    NotSeekable,
    /// I/O operation would block
    WouldBlock,
    /// I/O operation was interrupted
    Interrupted,
    /// End of file reached
    EndOfFile,
    /// Permission denied
    PermissionDenied,
    /// File not found
    FileNotFound,
    /// File already exists
    FileExists,
    /// Too many open files
    TooManyOpenFiles,
    /// Disk quota exceeded
    DiskQuotaExceeded,
    /// No space left on device
    NoSpaceLeft,
    /// Invalid argument
    InvalidArgument,
    /// File system error
    FileSystemError,
};

// ============================================================================
// FileIO Flags
// ============================================================================

/// Flags for opening files (similar to POSIX open flags)
pub const OpenFlags = struct {
    /// Read access
    read: bool = false,
    /// Write access
    write: bool = false,
    /// Create file if it doesn't exist
    create: bool = false,
    /// Truncate file on open
    truncate: bool = false,
    /// Append to file
    append: bool = false,
    /// Exclusive creation (fail if exists)
    exclusive: bool = false,
    /// Non-blocking I/O
    nonblock: bool = false,
    /// Close on exec
    cloexec: bool = true,

    /// Create flags for reading
    pub fn forRead() OpenFlags {
        return .{ .read = true };
    }

    /// Create flags for writing (create/truncate)
    pub fn forWrite() OpenFlags {
        return .{ .write = true, .create = true, .truncate = true };
    }

    /// Create flags for appending
    pub fn forAppend() OpenFlags {
        return .{ .write = true, .create = true, .append = true };
    }

    /// Create flags for read-write
    pub fn forReadWrite() OpenFlags {
        return .{ .read = true, .write = true };
    }

    /// Check if any access mode is set
    pub fn hasAccessMode(self: OpenFlags) bool {
        return self.read or self.write;
    }
};

// ============================================================================
// FileIO Structure
// ============================================================================

/// Raw file I/O class (unbuffered, binary mode)
pub const FileIO = struct {
    /// File descriptor
    fd: std.posix.fd_t = -1,
    /// File path (if opened by path)
    path: ?[]const u8 = null,
    /// Open flags
    flags: OpenFlags = .{},
    /// Whether file is closed
    closed: bool = true,
    /// Whether file is readable
    readable: bool = false,
    /// Whether file is writable
    writable: bool = false,
    /// Whether file is seekable
    seekable: bool = true,
    /// Close on dealloc
    closefd: bool = true,
    /// Allocator for path storage
    allocator: ?std.mem.Allocator = null,

    const Self = @This();

    /// Initialize FileIO from path
    pub fn initFromPath(allocator: std.mem.Allocator, path: []const u8, flags: OpenFlags) !Self {
        var self = Self{
            .allocator = allocator,
            .flags = flags,
            .readable = flags.read,
            .writable = flags.write,
        };

        // Store path
        self.path = try allocator.dupe(u8, path);

        // Open file
        try self.openFile();

        return self;
    }

    /// Initialize FileIO from existing file descriptor
    pub fn initFromFd(fd: std.posix.fd_t, closefd: bool) Self {
        return .{
            .fd = fd,
            .closed = false,
            .closefd = closefd,
            .readable = true, // Assume both for existing fd
            .writable = true,
        };
    }

    /// Open the file
    fn openFile(self: *Self) !void {
        if (self.path == null) return FileIOError.InvalidArgument;

        const zig_flags: std.fs.File.OpenFlags = .{
            .mode = if (self.flags.read and self.flags.write)
                .read_write
            else if (self.flags.write)
                .write_only
            else
                .read_only,
        };

        if (self.flags.create or self.flags.truncate) {
            const file = try std.fs.cwd().createFile(self.path.?, .{
                .read = self.flags.read,
                .truncate = self.flags.truncate,
                .exclusive = self.flags.exclusive,
            });
            self.fd = file.handle;
        } else {
            const file = try std.fs.cwd().openFile(self.path.?, zig_flags);
            self.fd = file.handle;
        }

        self.closed = false;

        // Handle append mode
        if (self.flags.append) {
            const file = std.fs.File{ .handle = self.fd };
            try file.seekFromEnd(0);
        }
    }

    /// Close the file
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.closefd and self.fd >= 0) {
            std.posix.close(self.fd);
        }

        self.fd = -1;
        self.closed = true;
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.close() catch {};

        if (self.allocator) |alloc| {
            if (self.path) |p| {
                alloc.free(p);
            }
        }
    }

    /// Read data into buffer
    pub fn read(self: *Self, buffer: []u8) !usize {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.readable) return FileIOError.NotReadable;

        const file = std.fs.File{ .handle = self.fd };
        return file.read(buffer);
    }

    /// Read all available data (up to max_size)
    pub fn readAll(self: *Self, allocator: std.mem.Allocator, max_size: usize) ![]u8 {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.readable) return FileIOError.NotReadable;

        const file = std.fs.File{ .handle = self.fd };
        return file.readToEndAlloc(allocator, max_size);
    }

    /// Read exactly n bytes
    pub fn readExact(self: *Self, buffer: []u8) !void {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.readable) return FileIOError.NotReadable;

        const file = std.fs.File{ .handle = self.fd };
        const bytes_read = try file.readAll(buffer);
        if (bytes_read != buffer.len) return FileIOError.EndOfFile;
    }

    /// Read into multiple buffers (vectored I/O)
    pub fn readv(self: *Self, iovecs: []std.posix.iovec) !usize {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.readable) return FileIOError.NotReadable;

        return std.posix.readv(self.fd, iovecs);
    }

    /// Write data from buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.writable) return FileIOError.NotWritable;

        const file = std.fs.File{ .handle = self.fd };
        try file.writeAll(data);
        return data.len;
    }

    /// Write all data
    pub fn writeAll(self: *Self, data: []const u8) !void {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.writable) return FileIOError.NotWritable;

        const file = std.fs.File{ .handle = self.fd };
        try file.writeAll(data);
    }

    /// Write from multiple buffers (vectored I/O)
    pub fn writev(self: *Self, iovecs: []const std.posix.iovec_const) !usize {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.writable) return FileIOError.NotWritable;

        return std.posix.writev(self.fd, iovecs);
    }

    /// Seek to position
    pub fn seek(self: *Self, offset: i64, whence: SeekWhence) !u64 {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.seekable) return FileIOError.NotSeekable;

        const file = std.fs.File{ .handle = self.fd };
        switch (whence) {
            .set => try file.seekTo(@intCast(offset)),
            .cur => try file.seekBy(offset),
            .end => try file.seekFromEnd(offset),
        }
        return file.getPos();
    }

    /// Get current position
    pub fn tell(self: *Self) !u64 {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.seekable) return FileIOError.NotSeekable;

        const file = std.fs.File{ .handle = self.fd };
        return file.getPos();
    }

    /// Truncate file to specified size
    pub fn truncate(self: *Self, size: u64) !void {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.writable) return FileIOError.NotWritable;

        const file = std.fs.File{ .handle = self.fd };
        try file.setEndPos(size);
    }

    /// Flush file (sync to disk)
    pub fn flush(self: *Self) !void {
        if (self.closed) return FileIOError.FileClosed;
        if (!self.writable) return;

        const file = std.fs.File{ .handle = self.fd };
        try file.sync();
    }

    /// Get file descriptor
    pub fn fileno(self: *const Self) !std.posix.fd_t {
        if (self.closed) return FileIOError.FileClosed;
        return self.fd;
    }

    /// Check if file is a TTY
    pub fn isatty(self: *const Self) bool {
        if (self.closed) return false;
        const file = std.fs.File{ .handle = self.fd };
        return file.isTty();
    }

    /// Get file mode/name (for repr)
    pub fn mode(self: *const Self) []const u8 {
        if (self.readable and self.writable) return "rb+";
        if (self.writable) return "wb";
        return "rb";
    }
};

/// Seek position reference
pub const SeekWhence = enum(u8) {
    set = 0, // SEEK_SET
    cur = 1, // SEEK_CUR
    end = 2, // SEEK_END
};

// ============================================================================
// FileIO Test Helpers
// ============================================================================

/// Create a test FileIO with temporary file
pub fn createTestFileIO(allocator: std.mem.Allocator, content: []const u8) !struct { fileio: FileIO, path: []u8 } {
    const path = try std.fmt.allocPrint(allocator, "/tmp/metal0_fileio_test_{d}", .{std.time.nanoTimestamp()});

    // Write initial content
    const file = try std.fs.cwd().createFile(path, .{});
    try file.writeAll(content);
    file.close();

    // Create FileIO
    var fileio = try FileIO.initFromPath(allocator, path, OpenFlags.forReadWrite());

    return .{ .fileio = fileio, .path = path };
}

/// Clean up test FileIO
pub fn cleanupTestFileIO(result: anytype) void {
    result.fileio.deinit();
    std.fs.cwd().deleteFile(result.path) catch {};
    if (result.fileio.allocator) |alloc| {
        _ = alloc;
        // Path is already freed in deinit
    }
}

// ============================================================================
// Performance Metrics
// ============================================================================

/// I/O performance metrics
pub const IOMetrics = struct {
    /// Total bytes read
    bytes_read: u64 = 0,
    /// Total bytes written
    bytes_written: u64 = 0,
    /// Number of read operations
    read_ops: u64 = 0,
    /// Number of write operations
    write_ops: u64 = 0,
    /// Number of seek operations
    seek_ops: u64 = 0,
    /// Total time spent in I/O (nanoseconds)
    io_time_ns: u64 = 0,

    /// Calculate read throughput (bytes/second)
    pub fn readThroughput(self: *const IOMetrics) f64 {
        if (self.io_time_ns == 0) return 0;
        const seconds = @as(f64, @floatFromInt(self.io_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.bytes_read)) / seconds;
    }

    /// Calculate write throughput (bytes/second)
    pub fn writeThroughput(self: *const IOMetrics) f64 {
        if (self.io_time_ns == 0) return 0;
        const seconds = @as(f64, @floatFromInt(self.io_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.bytes_written)) / seconds;
    }

    /// Calculate average bytes per read operation
    pub fn avgBytesPerRead(self: *const IOMetrics) f64 {
        if (self.read_ops == 0) return 0;
        return @as(f64, @floatFromInt(self.bytes_read)) / @as(f64, @floatFromInt(self.read_ops));
    }

    /// Calculate average bytes per write operation
    pub fn avgBytesPerWrite(self: *const IOMetrics) f64 {
        if (self.write_ops == 0) return 0;
        return @as(f64, @floatFromInt(self.bytes_written)) / @as(f64, @floatFromInt(self.write_ops));
    }
};

// ============================================================================
// Test Cases
// ============================================================================

/// Test case structure for FileIO operations
pub const FileIOTestCase = struct {
    name: []const u8,
    flags: OpenFlags,
    initial_content: []const u8,
    operations: []const Operation,
    expected_result: ExpectedResult,

    pub const Operation = union(enum) {
        read: usize,
        write: []const u8,
        seek: struct { offset: i64, whence: SeekWhence },
        truncate: u64,
        flush: void,
        tell: void,
    };

    pub const ExpectedResult = struct {
        success: bool = true,
        final_content: ?[]const u8 = null,
        final_position: ?u64 = null,
        read_data: ?[]const u8 = null,
    };
};

/// Standard test cases
pub const standard_test_cases = [_]FileIOTestCase{
    .{
        .name = "read_only",
        .flags = OpenFlags.forRead(),
        .initial_content = "Test content",
        .operations = &[_]FileIOTestCase.Operation{.{ .read = 12 }},
        .expected_result = .{ .read_data = "Test content" },
    },
    .{
        .name = "write_and_read",
        .flags = OpenFlags.forReadWrite(),
        .initial_content = "",
        .operations = &[_]FileIOTestCase.Operation{
            .{ .write = "Hello" },
            .{ .seek = .{ .offset = 0, .whence = .set } },
            .{ .read = 5 },
        },
        .expected_result = .{ .read_data = "Hello" },
    },
    .{
        .name = "seek_and_tell",
        .flags = OpenFlags.forRead(),
        .initial_content = "0123456789",
        .operations = &[_]FileIOTestCase.Operation{
            .{ .seek = .{ .offset = 5, .whence = .set } },
            .{ .tell = {} },
        },
        .expected_result = .{ .final_position = 5 },
    },
    .{
        .name = "truncate",
        .flags = OpenFlags.forReadWrite(),
        .initial_content = "Hello, World!",
        .operations = &[_]FileIOTestCase.Operation{
            .{ .truncate = 5 },
        },
        .expected_result = .{ .final_content = "Hello" },
    },
};

// ============================================================================
// Unit Tests
// ============================================================================

test "OpenFlags defaults" {
    const flags = OpenFlags{};
    try std.testing.expect(!flags.read);
    try std.testing.expect(!flags.write);
    try std.testing.expect(!flags.create);
    try std.testing.expect(flags.cloexec);
}

test "OpenFlags forRead" {
    const flags = OpenFlags.forRead();
    try std.testing.expect(flags.read);
    try std.testing.expect(!flags.write);
}

test "OpenFlags forWrite" {
    const flags = OpenFlags.forWrite();
    try std.testing.expect(!flags.read);
    try std.testing.expect(flags.write);
    try std.testing.expect(flags.create);
    try std.testing.expect(flags.truncate);
}

test "OpenFlags forAppend" {
    const flags = OpenFlags.forAppend();
    try std.testing.expect(!flags.read);
    try std.testing.expect(flags.write);
    try std.testing.expect(flags.create);
    try std.testing.expect(flags.append);
}

test "OpenFlags forReadWrite" {
    const flags = OpenFlags.forReadWrite();
    try std.testing.expect(flags.read);
    try std.testing.expect(flags.write);
}

test "OpenFlags hasAccessMode" {
    try std.testing.expect(!OpenFlags{}.hasAccessMode());
    try std.testing.expect(OpenFlags.forRead().hasAccessMode());
    try std.testing.expect(OpenFlags.forWrite().hasAccessMode());
}

test "FileIO initFromFd" {
    // Use stdout as a known valid fd
    const fileio = FileIO.initFromFd(1, false);
    try std.testing.expect(!fileio.closed);
    try std.testing.expect(!fileio.closefd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 1), fileio.fd);
}

test "FileIO mode string" {
    var read_only = FileIO{ .readable = true, .writable = false };
    try std.testing.expectEqualStrings("rb", read_only.mode());

    var write_only = FileIO{ .readable = false, .writable = true };
    try std.testing.expectEqualStrings("wb", write_only.mode());

    var read_write = FileIO{ .readable = true, .writable = true };
    try std.testing.expectEqualStrings("rb+", read_write.mode());
}

test "SeekWhence values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SeekWhence.set));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SeekWhence.cur));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(SeekWhence.end));
}

test "IOMetrics throughput calculations" {
    var metrics = IOMetrics{
        .bytes_read = 1024 * 1024, // 1 MB
        .bytes_written = 512 * 1024, // 512 KB
        .io_time_ns = 1_000_000_000, // 1 second
    };

    const read_tp = metrics.readThroughput();
    try std.testing.expectApproxEqAbs(@as(f64, 1024 * 1024), read_tp, 1.0);

    const write_tp = metrics.writeThroughput();
    try std.testing.expectApproxEqAbs(@as(f64, 512 * 1024), write_tp, 1.0);
}

test "IOMetrics avgBytesPerOp" {
    var metrics = IOMetrics{
        .bytes_read = 1000,
        .bytes_written = 500,
        .read_ops = 10,
        .write_ops = 5,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 100.0), metrics.avgBytesPerRead(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), metrics.avgBytesPerWrite(), 0.001);
}

test "FileIO read and write operations" {
    const allocator = std.testing.allocator;

    // Create temp file
    const path = try std.fmt.allocPrint(allocator, "/tmp/metal0_fileio_test_{d}", .{std.time.nanoTimestamp()});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Write some data
    {
        var fileio = try FileIO.initFromPath(allocator, path, OpenFlags.forWrite());
        defer fileio.deinit();

        _ = try fileio.write("Hello, FileIO!");
    }

    // Read it back
    {
        var fileio = try FileIO.initFromPath(allocator, path, OpenFlags.forRead());
        defer fileio.deinit();

        var buf: [20]u8 = undefined;
        const bytes_read = try fileio.read(&buf);

        try std.testing.expectEqualStrings("Hello, FileIO!", buf[0..bytes_read]);
    }
}

test "FileIO seek operations" {
    const allocator = std.testing.allocator;

    // Create temp file with content
    const path = try std.fmt.allocPrint(allocator, "/tmp/metal0_fileio_seek_test_{d}", .{std.time.nanoTimestamp()});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Write content
    {
        const file = try std.fs.cwd().createFile(path, .{});
        try file.writeAll("0123456789");
        file.close();
    }

    // Test seeking
    {
        var fileio = try FileIO.initFromPath(allocator, path, OpenFlags.forRead());
        defer fileio.deinit();

        // Seek to position 5
        _ = try fileio.seek(5, .set);
        try std.testing.expectEqual(@as(u64, 5), try fileio.tell());

        // Read remaining
        var buf: [10]u8 = undefined;
        const bytes_read = try fileio.read(&buf);
        try std.testing.expectEqualStrings("56789", buf[0..bytes_read]);
    }
}

test "FileIO truncate" {
    const allocator = std.testing.allocator;

    const path = try std.fmt.allocPrint(allocator, "/tmp/metal0_fileio_trunc_test_{d}", .{std.time.nanoTimestamp()});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Create file with content
    {
        const file = try std.fs.cwd().createFile(path, .{});
        try file.writeAll("Hello, World!");
        file.close();
    }

    // Truncate
    {
        var fileio = try FileIO.initFromPath(allocator, path, .{ .read = true, .write = true });
        defer fileio.deinit();

        try fileio.truncate(5);
    }

    // Verify
    {
        var fileio = try FileIO.initFromPath(allocator, path, OpenFlags.forRead());
        defer fileio.deinit();

        const content = try fileio.readAll(allocator, 100);
        defer allocator.free(content);

        try std.testing.expectEqualStrings("Hello", content);
    }
}
