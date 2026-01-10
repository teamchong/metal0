//! test.test_file - File tests
//! CPython Reference: https://docs.python.org/3.12/library/io.html
//!
//! This module provides tests for file operations including opening, reading,
//! writing, seeking, and various file modes in the Metal0 runtime.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// File Mode Types
// ============================================================================

/// File open modes (matches Python's open() mode parameter)
pub const FileMode = enum {
    /// Read-only (default)
    read,
    /// Write-only (truncate)
    write,
    /// Append (write at end)
    append,
    /// Read and write
    read_write,
    /// Read and write (truncate)
    write_read,
    /// Read and append
    read_append,
    /// Exclusive creation (fail if exists)
    exclusive,
    /// Exclusive creation with read
    exclusive_read,

    /// Convert to Zig file open flags
    pub fn toZigFlags(self: FileMode) std.fs.File.OpenFlags {
        return switch (self) {
            .read => .{},
            .write => .{ .mode = .write_only },
            .append => .{ .mode = .write_only },
            .read_write => .{ .mode = .read_write },
            .write_read => .{ .mode = .read_write },
            .read_append => .{ .mode = .read_write },
            .exclusive => .{ .mode = .write_only },
            .exclusive_read => .{ .mode = .read_write },
        };
    }

    /// Parse mode string (e.g., "r", "w", "a", "r+", "w+", "a+", "x", "x+")
    pub fn fromString(mode: []const u8) ?FileMode {
        if (std.mem.eql(u8, mode, "r")) return .read;
        if (std.mem.eql(u8, mode, "w")) return .write;
        if (std.mem.eql(u8, mode, "a")) return .append;
        if (std.mem.eql(u8, mode, "r+") or std.mem.eql(u8, mode, "r+b")) return .read_write;
        if (std.mem.eql(u8, mode, "w+") or std.mem.eql(u8, mode, "w+b")) return .write_read;
        if (std.mem.eql(u8, mode, "a+") or std.mem.eql(u8, mode, "a+b")) return .read_append;
        if (std.mem.eql(u8, mode, "x") or std.mem.eql(u8, mode, "xb")) return .exclusive;
        if (std.mem.eql(u8, mode, "x+") or std.mem.eql(u8, mode, "x+b")) return .exclusive_read;
        return null;
    }

    /// Check if mode allows reading
    pub fn canRead(self: FileMode) bool {
        return switch (self) {
            .read, .read_write, .write_read, .read_append, .exclusive_read => true,
            .write, .append, .exclusive => false,
        };
    }

    /// Check if mode allows writing
    pub fn canWrite(self: FileMode) bool {
        return switch (self) {
            .write, .append, .read_write, .write_read, .read_append, .exclusive, .exclusive_read => true,
            .read => false,
        };
    }

    /// Check if mode truncates file
    pub fn truncates(self: FileMode) bool {
        return self == .write or self == .write_read;
    }

    /// Check if mode appends to file
    pub fn appends(self: FileMode) bool {
        return self == .append or self == .read_append;
    }
};

/// File type (text vs binary)
pub const FileType = enum {
    text,
    binary,
};

// ============================================================================
// File Wrapper
// ============================================================================

/// Wrapper around file operations with Python-like interface
pub const FileWrapper = struct {
    /// Underlying file handle
    handle: ?std.fs.File = null,
    /// File path
    path: []const u8,
    /// Open mode
    mode: FileMode,
    /// File type (text/binary)
    file_type: FileType = .binary,
    /// Whether file is closed
    closed: bool = true,
    /// Current position (for text mode line tracking)
    line_number: u64 = 1,
    /// Encoding for text mode
    encoding: []const u8 = "utf-8",
    /// Newline translation mode
    newline: NewlineMode = .universal,
    /// Allocator
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Newline translation modes
    pub const NewlineMode = enum {
        /// Universal newlines (translate all to \n on read)
        universal,
        /// No translation
        none,
        /// Platform-specific (\r\n on Windows, \n on Unix)
        native,
    };

    /// Initialize file wrapper (does not open file)
    pub fn init(allocator: std.mem.Allocator, path: []const u8, mode: FileMode) Self {
        return .{
            .path = path,
            .mode = mode,
            .allocator = allocator,
        };
    }

    /// Open the file
    pub fn open(self: *Self) !void {
        if (!self.closed) return error.FileAlreadyOpen;

        const flags = self.mode.toZigFlags();

        if (self.mode == .exclusive or self.mode == .exclusive_read) {
            // Exclusive creation
            self.handle = try std.fs.cwd().createFile(self.path, .{
                .read = self.mode.canRead(),
                .exclusive = true,
            });
        } else if (self.mode.truncates()) {
            // Write mode (truncate)
            self.handle = try std.fs.cwd().createFile(self.path, .{
                .read = self.mode.canRead(),
            });
        } else if (self.mode == .append or self.mode == .read_append) {
            // Append mode
            self.handle = try std.fs.cwd().openFile(self.path, flags);
            try self.handle.?.seekFromEnd(0);
        } else {
            // Read mode
            self.handle = try std.fs.cwd().openFile(self.path, flags);
        }

        self.closed = false;
    }

    /// Close the file
    pub fn close(self: *Self) void {
        if (self.handle) |h| {
            h.close();
            self.handle = null;
        }
        self.closed = true;
    }

    /// Read entire file contents
    pub fn readAll(self: *Self) ![]u8 {
        if (self.closed) return error.FileClosed;
        if (!self.mode.canRead()) return error.FileNotReadable;

        if (self.handle) |h| {
            return h.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        }
        return error.FileNotOpen;
    }

    /// Read up to n bytes
    pub fn read(self: *Self, buffer: []u8) !usize {
        if (self.closed) return error.FileClosed;
        if (!self.mode.canRead()) return error.FileNotReadable;

        if (self.handle) |h| {
            return h.read(buffer);
        }
        return error.FileNotOpen;
    }

    /// Read a single line
    pub fn readline(self: *Self) !?[]u8 {
        if (self.closed) return error.FileClosed;
        if (!self.mode.canRead()) return error.FileNotReadable;

        if (self.handle) |h| {
            var line = std.ArrayList(u8).init(self.allocator);
            errdefer line.deinit();

            var buf: [1]u8 = undefined;
            while (true) {
                const bytes_read = try h.read(&buf);
                if (bytes_read == 0) {
                    if (line.items.len == 0) return null;
                    break;
                }

                try line.append(buf[0]);
                if (buf[0] == '\n') {
                    self.line_number += 1;
                    break;
                }
            }

            return line.toOwnedSlice();
        }
        return error.FileNotOpen;
    }

    /// Write data to file
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.closed) return error.FileClosed;
        if (!self.mode.canWrite()) return error.FileNotWritable;

        if (self.handle) |h| {
            try h.writeAll(data);
            return data.len;
        }
        return error.FileNotOpen;
    }

    /// Write data and add newline
    pub fn writeline(self: *Self, data: []const u8) !void {
        _ = try self.write(data);
        _ = try self.write("\n");
    }

    /// Seek to position
    pub fn seek(self: *Self, offset: i64, whence: Whence) !void {
        if (self.closed) return error.FileClosed;

        if (self.handle) |h| {
            switch (whence) {
                .set => try h.seekTo(@intCast(offset)),
                .cur => try h.seekBy(offset),
                .end => try h.seekFromEnd(offset),
            }
        } else {
            return error.FileNotOpen;
        }
    }

    /// Get current position
    pub fn tell(self: *Self) !u64 {
        if (self.closed) return error.FileClosed;

        if (self.handle) |h| {
            return h.getPos();
        }
        return error.FileNotOpen;
    }

    /// Flush buffered data
    pub fn flush(self: *Self) !void {
        if (self.closed) return error.FileClosed;

        if (self.handle) |h| {
            try h.sync();
        }
    }

    /// Truncate file to specified size
    pub fn truncate(self: *Self, size: ?u64) !void {
        if (self.closed) return error.FileClosed;
        if (!self.mode.canWrite()) return error.FileNotWritable;

        if (self.handle) |h| {
            const target_size = size orelse try h.getPos();
            try h.setEndPos(target_size);
        }
    }

    /// Get file size
    pub fn size(self: *Self) !u64 {
        if (self.closed) return error.FileClosed;

        if (self.handle) |h| {
            const stat = try h.stat();
            return stat.size;
        }
        return error.FileNotOpen;
    }

    /// Check if file is a TTY
    pub fn isatty(self: *Self) bool {
        if (self.handle) |h| {
            return h.isTty();
        }
        return false;
    }

    /// Get file descriptor number
    pub fn fileno(self: *Self) ?std.posix.fd_t {
        if (self.handle) |h| {
            return h.handle;
        }
        return null;
    }
};

/// Seek whence values
pub const Whence = enum(u8) {
    /// Seek from beginning
    set = 0,
    /// Seek from current position
    cur = 1,
    /// Seek from end
    end = 2,
};

// ============================================================================
// File Statistics
// ============================================================================

/// File statistics structure (similar to os.stat result)
pub const FileStat = struct {
    /// File size in bytes
    size: u64,
    /// Access time (nanoseconds since epoch)
    atime_ns: i128,
    /// Modification time (nanoseconds since epoch)
    mtime_ns: i128,
    /// Creation time (nanoseconds since epoch, if available)
    ctime_ns: i128,
    /// File mode/permissions
    mode: u32,
    /// Inode number
    inode: u64,
    /// Device ID
    dev: u64,
    /// Number of hard links
    nlink: u64,
    /// User ID of owner
    uid: u32,
    /// Group ID of owner
    gid: u32,

    /// Check if it's a regular file
    pub fn isFile(self: *const FileStat) bool {
        return (self.mode & 0o170000) == 0o100000;
    }

    /// Check if it's a directory
    pub fn isDir(self: *const FileStat) bool {
        return (self.mode & 0o170000) == 0o040000;
    }

    /// Check if it's a symbolic link
    pub fn isLink(self: *const FileStat) bool {
        return (self.mode & 0o170000) == 0o120000;
    }

    /// Get permissions portion of mode
    pub fn permissions(self: *const FileStat) u12 {
        return @truncate(self.mode);
    }
};

/// Get file statistics
pub fn stat(path: []const u8) !FileStat {
    const s = try std.fs.cwd().statFile(path);
    return .{
        .size = s.size,
        .atime_ns = s.atime,
        .mtime_ns = s.mtime,
        .ctime_ns = s.ctime,
        .mode = s.mode,
        .inode = s.inode,
        .dev = s.dev,
        .nlink = s.nlink,
        .uid = s.uid,
        .gid = s.gid,
    };
}

// ============================================================================
// File Test Helpers
// ============================================================================

/// Create a temporary test file
pub fn createTempFile(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(allocator, "/tmp/metal0_test_{d}", .{std.time.nanoTimestamp()});

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);

    return path;
}

/// Remove a test file
pub fn removeTempFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch {};
}

/// Create a temporary directory
pub fn createTempDir(allocator: std.mem.Allocator) ![]u8 {
    const path = try std.fmt.allocPrint(allocator, "/tmp/metal0_test_dir_{d}", .{std.time.nanoTimestamp()});
    try std.fs.cwd().makeDir(path);
    return path;
}

/// Remove a temporary directory
pub fn removeTempDir(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch {};
}

// ============================================================================
// Test Cases
// ============================================================================

/// Test case for file operations
pub const FileTestCase = struct {
    name: []const u8,
    mode: FileMode,
    initial_content: []const u8,
    operations: []const Operation,
    expected_final_content: []const u8,

    pub const Operation = union(enum) {
        read: usize,
        write: []const u8,
        seek: struct { offset: i64, whence: Whence },
        truncate: ?u64,
        readline: void,
    };
};

/// Standard test cases
pub const standard_test_cases = [_]FileTestCase{
    .{
        .name = "read_entire_file",
        .mode = .read,
        .initial_content = "Hello, World!",
        .operations = &[_]FileTestCase.Operation{.{ .read = 100 }},
        .expected_final_content = "Hello, World!",
    },
    .{
        .name = "write_new_content",
        .mode = .write,
        .initial_content = "Old content",
        .operations = &[_]FileTestCase.Operation{.{ .write = "New content" }},
        .expected_final_content = "New content",
    },
    .{
        .name = "append_to_file",
        .mode = .append,
        .initial_content = "Line1\n",
        .operations = &[_]FileTestCase.Operation{.{ .write = "Line2\n" }},
        .expected_final_content = "Line1\nLine2\n",
    },
    .{
        .name = "seek_and_read",
        .mode = .read,
        .initial_content = "0123456789",
        .operations = &[_]FileTestCase.Operation{
            .{ .seek = .{ .offset = 5, .whence = .set } },
            .{ .read = 5 },
        },
        .expected_final_content = "0123456789",
    },
    .{
        .name = "truncate_file",
        .mode = .write_read,
        .initial_content = "Hello, World!",
        .operations = &[_]FileTestCase.Operation{
            .{ .truncate = 5 },
        },
        .expected_final_content = "Hello",
    },
};

// ============================================================================
// Unit Tests
// ============================================================================

test "FileMode fromString" {
    try std.testing.expectEqual(FileMode.read, FileMode.fromString("r").?);
    try std.testing.expectEqual(FileMode.write, FileMode.fromString("w").?);
    try std.testing.expectEqual(FileMode.append, FileMode.fromString("a").?);
    try std.testing.expectEqual(FileMode.read_write, FileMode.fromString("r+").?);
    try std.testing.expectEqual(FileMode.write_read, FileMode.fromString("w+").?);
    try std.testing.expectEqual(FileMode.read_append, FileMode.fromString("a+").?);
    try std.testing.expectEqual(FileMode.exclusive, FileMode.fromString("x").?);
    try std.testing.expect(FileMode.fromString("invalid") == null);
}

test "FileMode canRead" {
    try std.testing.expect(FileMode.read.canRead());
    try std.testing.expect(FileMode.read_write.canRead());
    try std.testing.expect(!FileMode.write.canRead());
    try std.testing.expect(!FileMode.append.canRead());
}

test "FileMode canWrite" {
    try std.testing.expect(FileMode.write.canWrite());
    try std.testing.expect(FileMode.append.canWrite());
    try std.testing.expect(FileMode.read_write.canWrite());
    try std.testing.expect(!FileMode.read.canWrite());
}

test "FileMode truncates" {
    try std.testing.expect(FileMode.write.truncates());
    try std.testing.expect(FileMode.write_read.truncates());
    try std.testing.expect(!FileMode.read.truncates());
    try std.testing.expect(!FileMode.append.truncates());
}

test "FileMode appends" {
    try std.testing.expect(FileMode.append.appends());
    try std.testing.expect(FileMode.read_append.appends());
    try std.testing.expect(!FileMode.write.appends());
    try std.testing.expect(!FileMode.read.appends());
}

test "FileWrapper init" {
    const allocator = std.testing.allocator;
    const wrapper = FileWrapper.init(allocator, "/tmp/test.txt", .read);

    try std.testing.expectEqualStrings("/tmp/test.txt", wrapper.path);
    try std.testing.expectEqual(FileMode.read, wrapper.mode);
    try std.testing.expect(wrapper.closed);
}

test "createTempFile and removeTempFile" {
    const allocator = std.testing.allocator;
    const content = "Test content";

    const path = try createTempFile(allocator, content);
    defer allocator.free(path);
    defer removeTempFile(path);

    // Verify file exists and has correct content
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf: [100]u8 = undefined;
    const read_size = try file.readAll(&buf);
    try std.testing.expectEqualStrings(content, buf[0..read_size]);
}

test "FileStat type checks" {
    const file_stat = FileStat{
        .size = 100,
        .atime_ns = 0,
        .mtime_ns = 0,
        .ctime_ns = 0,
        .mode = 0o100644, // Regular file
        .inode = 0,
        .dev = 0,
        .nlink = 1,
        .uid = 0,
        .gid = 0,
    };

    try std.testing.expect(file_stat.isFile());
    try std.testing.expect(!file_stat.isDir());
    try std.testing.expect(!file_stat.isLink());
}

test "FileStat directory check" {
    const dir_stat = FileStat{
        .size = 0,
        .atime_ns = 0,
        .mtime_ns = 0,
        .ctime_ns = 0,
        .mode = 0o040755, // Directory
        .inode = 0,
        .dev = 0,
        .nlink = 1,
        .uid = 0,
        .gid = 0,
    };

    try std.testing.expect(!dir_stat.isFile());
    try std.testing.expect(dir_stat.isDir());
}

test "FileStat permissions" {
    const stat_info = FileStat{
        .size = 0,
        .atime_ns = 0,
        .mtime_ns = 0,
        .ctime_ns = 0,
        .mode = 0o100755,
        .inode = 0,
        .dev = 0,
        .nlink = 1,
        .uid = 0,
        .gid = 0,
    };

    try std.testing.expectEqual(@as(u12, 0o755), stat_info.permissions());
}

test "Whence values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Whence.set));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Whence.cur));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Whence.end));
}

test "FileWrapper read and write operations" {
    const allocator = std.testing.allocator;

    // Create temp file with initial content
    const path = try createTempFile(allocator, "Initial content");
    defer allocator.free(path);
    defer removeTempFile(path);

    // Test write mode
    var write_wrapper = FileWrapper.init(allocator, path, .write);
    try write_wrapper.open();
    _ = try write_wrapper.write("New content");
    write_wrapper.close();

    // Verify write
    var read_wrapper = FileWrapper.init(allocator, path, .read);
    try read_wrapper.open();
    const content = try read_wrapper.readAll();
    defer allocator.free(content);
    read_wrapper.close();

    try std.testing.expectEqualStrings("New content", content);
}

test "FileWrapper seek and tell" {
    const allocator = std.testing.allocator;

    const path = try createTempFile(allocator, "0123456789");
    defer allocator.free(path);
    defer removeTempFile(path);

    var wrapper = FileWrapper.init(allocator, path, .read);
    try wrapper.open();
    defer wrapper.close();

    try wrapper.seek(5, .set);
    try std.testing.expectEqual(@as(u64, 5), try wrapper.tell());

    try wrapper.seek(3, .cur);
    try std.testing.expectEqual(@as(u64, 8), try wrapper.tell());

    try wrapper.seek(-2, .end);
    try std.testing.expectEqual(@as(u64, 8), try wrapper.tell());
}
