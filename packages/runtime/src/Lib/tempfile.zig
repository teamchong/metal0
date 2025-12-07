//! CPython source: Lib/tempfile.py
//!
//! Provides functions for creating temporary files and directories.
//! All files/directories are created in a platform-appropriate temp directory.
//!
//! Mirrors: CPython Lib/tempfile.py

const std = @import("std");
const builtin = @import("builtin");

/// Default directory for temporary files
pub fn gettempdir() []const u8 {
    // Check environment variables in order
    if (std.posix.getenv("TMPDIR")) |dir| return dir;
    if (std.posix.getenv("TEMP")) |dir| return dir;
    if (std.posix.getenv("TMP")) |dir| return dir;

    // Platform defaults
    if (builtin.os.tag == .windows) {
        return "C:\\TEMP";
    } else {
        return "/tmp";
    }
}

/// Generate a unique temporary filename
pub fn mktemp(allocator: std.mem.Allocator, prefix: []const u8, suffix: []const u8) ![]u8 {
    const dir = gettempdir();
    const random_part = generateRandomString();
    return std.fmt.allocPrint(allocator, "{s}/{s}{s}{s}", .{ dir, prefix, random_part, suffix });
}

/// Create a temporary file and return its path
/// Caller is responsible for deleting the file
pub fn mkstemp(allocator: std.mem.Allocator, prefix: []const u8, suffix: []const u8) !struct { file: std.fs.File, path: []u8 } {
    var attempts: usize = 0;
    const max_attempts = 1000;

    while (attempts < max_attempts) : (attempts += 1) {
        const path = try mktemp(allocator, prefix, suffix);
        errdefer allocator.free(path);

        // Try to create exclusively
        if (std.fs.cwd().createFile(path, .{ .exclusive = true })) |file| {
            return .{ .file = file, .path = path };
        } else |err| {
            allocator.free(path);
            if (err != error.PathAlreadyExists) {
                return err;
            }
            // Try again with different random name
        }
    }

    return error.TooManyAttempts;
}

/// Create a temporary directory and return its path
/// Caller is responsible for deleting the directory
pub fn mkdtemp(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    var attempts: usize = 0;
    const max_attempts = 1000;

    while (attempts < max_attempts) : (attempts += 1) {
        const path = try mktemp(allocator, prefix, "");
        errdefer allocator.free(path);

        // Try to create directory
        if (std.fs.cwd().makeDir(path)) {
            return path;
        } else |err| {
            allocator.free(path);
            if (err != error.PathAlreadyExists) {
                return err;
            }
            // Try again with different random name
        }
    }

    return error.TooManyAttempts;
}

/// NamedTemporaryFile - A temporary file that is automatically deleted
pub const NamedTemporaryFile = struct {
    file: std.fs.File,
    path: []u8,
    allocator: std.mem.Allocator,
    delete_on_close: bool,

    pub fn init(allocator: std.mem.Allocator, options: struct {
        prefix: []const u8 = "tmp",
        suffix: []const u8 = "",
        delete: bool = true,
    }) !NamedTemporaryFile {
        const result = try mkstemp(allocator, options.prefix, options.suffix);
        return .{
            .file = result.file,
            .path = result.path,
            .allocator = allocator,
            .delete_on_close = options.delete,
        };
    }

    pub fn write(self: *NamedTemporaryFile, data: []const u8) !usize {
        return self.file.write(data);
    }

    pub fn read(self: *NamedTemporaryFile, buffer: []u8) !usize {
        return self.file.read(buffer);
    }

    pub fn seekTo(self: *NamedTemporaryFile, pos: u64) !void {
        try self.file.seekTo(pos);
    }

    pub fn close(self: *NamedTemporaryFile) void {
        self.file.close();
        if (self.delete_on_close) {
            std.fs.cwd().deleteFile(self.path) catch {};
        }
        self.allocator.free(self.path);
    }

    pub fn deinit(self: *NamedTemporaryFile) void {
        self.close();
    }
};

/// TemporaryDirectory - A temporary directory that is automatically deleted
pub const TemporaryDirectory = struct {
    path: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) !TemporaryDirectory {
        const path = try mkdtemp(allocator, prefix);
        return .{
            .path = path,
            .allocator = allocator,
        };
    }

    pub fn cleanup(self: *TemporaryDirectory) void {
        std.fs.cwd().deleteTree(self.path) catch {};
        self.allocator.free(self.path);
    }

    pub fn deinit(self: *TemporaryDirectory) void {
        self.cleanup();
    }
};

/// SpooledTemporaryFile - A file that starts in memory and spills to disk
pub const SpooledTemporaryFile = struct {
    buffer: std.ArrayList(u8),
    file: ?std.fs.File,
    file_path: ?[]u8,
    allocator: std.mem.Allocator,
    max_size: usize,
    position: usize,

    pub fn init(allocator: std.mem.Allocator, max_size: usize) SpooledTemporaryFile {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .file = null,
            .file_path = null,
            .allocator = allocator,
            .max_size = max_size,
            .position = 0,
        };
    }

    pub fn write(self: *SpooledTemporaryFile, data: []const u8) !usize {
        if (self.file != null) {
            return self.file.?.write(data);
        }

        // Check if we need to spill to disk
        if (self.buffer.items.len + data.len > self.max_size) {
            try self.rollover();
            return self.file.?.write(data);
        }

        try self.buffer.appendSlice(data);
        return data.len;
    }

    pub fn read(self: *SpooledTemporaryFile, buffer: []u8) !usize {
        if (self.file != null) {
            return self.file.?.read(buffer);
        }

        const available = self.buffer.items.len - self.position;
        const to_read = @min(buffer.len, available);
        @memcpy(buffer[0..to_read], self.buffer.items[self.position..][0..to_read]);
        self.position += to_read;
        return to_read;
    }

    fn rollover(self: *SpooledTemporaryFile) !void {
        const result = try mkstemp(self.allocator, "spooled", "");
        self.file = result.file;
        self.file_path = result.path;

        // Write buffered data to file
        if (self.buffer.items.len > 0) {
            _ = try self.file.?.write(self.buffer.items);
        }
        self.buffer.deinit();
    }

    pub fn deinit(self: *SpooledTemporaryFile) void {
        if (self.file) |*f| {
            f.close();
            if (self.file_path) |path| {
                std.fs.cwd().deleteFile(path) catch {};
                self.allocator.free(path);
            }
        } else {
            self.buffer.deinit();
        }
    }
};

// Generate random string for temp names
fn generateRandomString() [8]u8 {
    var buf: [8]u8 = undefined;
    const chars = "abcdefghijklmnopqrstuvwxyz0123456789";

    // Use nanoseconds as simple randomness source
    const seed: u64 = @bitCast(std.time.nanoTimestamp());
    var rng = std.Random.DefaultPrng.init(seed);
    const random = rng.random();

    for (&buf) |*c| {
        c.* = chars[random.intRangeAtMost(usize, 0, chars.len - 1)];
    }

    return buf;
}

// ============================================================================
// Tests
// ============================================================================

test "gettempdir" {
    const dir = gettempdir();
    try std.testing.expect(dir.len > 0);
}

test "mktemp" {
    const allocator = std.testing.allocator;
    const path = try mktemp(allocator, "test_", ".txt");
    defer allocator.free(path);

    try std.testing.expect(std.mem.indexOf(u8, path, "test_") != null);
    try std.testing.expect(std.mem.endsWith(u8, path, ".txt"));
}

test "mkstemp" {
    const allocator = std.testing.allocator;
    var result = try mkstemp(allocator, "test_", ".txt");
    defer {
        result.file.close();
        std.fs.cwd().deleteFile(result.path) catch {};
        allocator.free(result.path);
    }

    // Write to file
    _ = try result.file.write("test content");

    // Verify file exists
    const stat = try std.fs.cwd().statFile(result.path);
    try std.testing.expect(stat.kind == .file);
}

test "mkdtemp" {
    const allocator = std.testing.allocator;
    const path = try mkdtemp(allocator, "testdir_");
    defer {
        std.fs.cwd().deleteTree(path) catch {};
        allocator.free(path);
    }

    // Verify directory exists
    var dir = try std.fs.cwd().openDir(path, .{});
    dir.close();
}

test "NamedTemporaryFile" {
    const allocator = std.testing.allocator;
    var tmp = try NamedTemporaryFile.init(allocator, .{
        .prefix = "named_",
        .suffix = ".tmp",
    });
    defer tmp.deinit();

    _ = try tmp.write("hello world");
    try tmp.seekTo(0);

    var buf: [11]u8 = undefined;
    const n = try tmp.read(&buf);
    try std.testing.expectEqual(@as(usize, 11), n);
    try std.testing.expectEqualStrings("hello world", buf[0..n]);
}

test "TemporaryDirectory" {
    const allocator = std.testing.allocator;
    var tmp = try TemporaryDirectory.init(allocator, "tmpdir_");
    defer tmp.deinit();

    // Create a file in the temp directory
    const file_path = try std.fs.path.join(allocator, &.{ tmp.path, "test.txt" });
    defer allocator.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{});
    file.close();
}
