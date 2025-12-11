/// _pyio.raw - Raw file I/O implementation
/// Unbuffered file operations

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const base = @import("base.zig");

// ============================================================================
// Raw I/O
// ============================================================================

/// FileIO - raw file I/O
pub const FileIO = struct {
    const Self = @This();

    base: base.IOBase,
    file: ?std.fs.File = null,
    name: []const u8 = "",
    mode: types.IOMode = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .base = base.IOBase{},
        };
    }

    pub fn open(self: *Self, path: []const u8, mode_str: []const u8) !void {
        const mode = try types.IOMode.parse(mode_str);
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

    pub fn seek(self: *Self, offset: i64, whence: types.SeekWhence) !u64 {
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

    fn mapError(err: anyerror) types.IOError {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.PermissionDenied,
            error.PathAlreadyExists => error.FileExists,
            else => error.PermissionDenied,
        };
    }
};
