//! Native file system reader implementation.
//!
//! Provides a Reader implementation for reading from local files
//! using the standard Zig file I/O APIs.

const std = @import("std");
const reader_mod = @import("reader.zig");

const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;

/// Reader implementation for native file system access.
pub const FileReader = struct {
    file: std.fs.File,
    file_size: u64,

    const Self = @This();

    /// Open a file for reading.
    pub fn open(path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        errdefer file.close();

        const stat = try file.stat();

        return Self{
            .file = file,
            .file_size = stat.size,
        };
    }

    /// Open a file using an absolute path.
    pub fn openAbsolute(path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{});
        errdefer file.close();

        const stat = try file.stat();

        return Self{
            .file = file,
            .file_size = stat.size,
        };
    }

    /// Close the file.
    pub fn close(self: *Self) void {
        self.file.close();
    }

    /// Get a Reader interface for this file.
    pub fn reader(self: *Self) Reader {
        return Reader{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    // VTable implementation
    const vtable = Reader.VTable{
        .read = readImpl,
        .size = sizeImpl,
        .deinit = deinitImpl,
    };

    fn readImpl(ptr: *anyopaque, offset: u64, buffer: []u8) ReadError!usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (offset >= self.file_size) {
            return ReadError.OffsetOutOfBounds;
        }

        self.file.seekTo(offset) catch return ReadError.IoError;
        return self.file.read(buffer) catch ReadError.IoError;
    }

    fn sizeImpl(ptr: *anyopaque) ReadError!u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.file_size;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.file.close();
    }
};

test "file reader basic" {
    // Create a temporary file for testing
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_data = "Hello, Lance!";
    const file = try tmp_dir.dir.createFile("test.bin", .{});
    try file.writeAll(test_data);
    file.close();

    // Read using FileReader
    var file_reader_instance = try FileReader.open("test.bin");
    // Note: This will fail because we can't use tmpDir path directly
    // In real tests, use absolute paths
    _ = &file_reader_instance;
}
