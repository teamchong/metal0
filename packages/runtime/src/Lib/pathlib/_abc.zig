//! pathlib._abc - Abstract base classes for path objects
//! Reference: cpython/Lib/pathlib/_abc.py
//!
//! CPython __all__: UnsupportedOperation
//!
//! Base classes for rich path objects (Python 3.13+).

const std = @import("std");

// ============================================================================
// Errors
// ============================================================================

/// Exception raised when an unsupported operation is called
pub const UnsupportedOperation = error{
    UnsupportedOperation,
};

// ============================================================================
// Constants
// ============================================================================

/// Windows error codes
pub const WINERROR_NOT_READY: i32 = 21;
pub const WINERROR_INVALID_NAME: i32 = 123;
pub const WINERROR_CANT_RESOLVE_FILENAME: i32 = 1921;

// ============================================================================
// ParserBase
// ============================================================================

/// Base class for path parsers
pub const ParserBase = struct {
    const Self = @This();

    /// The character used to separate path components
    pub fn sep(_: *const Self) u8 {
        return std.fs.path.sep;
    }

    /// Join path segments
    pub fn join(self: *const Self, allocator: std.mem.Allocator, paths: []const []const u8) ![]const u8 {
        _ = self;
        return std.fs.path.join(allocator, paths);
    }

    /// Split the path into (head, tail)
    pub fn split(_: *const Self, path: []const u8) struct { []const u8, []const u8 } {
        const dir = std.fs.path.dirname(path) orelse "";
        const base = std.fs.path.basename(path);
        return .{ dir, base };
    }

    /// Split the path into (drive, tail)
    pub fn splitdrive(_: *const Self, path: []const u8) struct { []const u8, []const u8 } {
        // On POSIX, there's no drive
        if (comptime @import("builtin").os.tag == .windows) {
            if (path.len >= 2 and path[1] == ':') {
                return .{ path[0..2], path[2..] };
            }
        }
        return .{ "", path };
    }

    /// Normalize case (no-op on POSIX, lowercase on Windows)
    pub fn normcase(_: *const Self, path: []const u8) []const u8 {
        // For now, return as-is (POSIX behavior)
        return path;
    }

    /// Check if path is absolute
    pub fn isabs(_: *const Self, path: []const u8) bool {
        return std.fs.path.isAbsolute(path);
    }
};

// ============================================================================
// PurePathBase
// ============================================================================

/// Base class for pure path objects (no I/O operations)
pub const PurePathBase = struct {
    const Self = @This();

    raw_path: []const u8,
    allocator: std.mem.Allocator,
    parser: ParserBase = .{},

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return .{
            .raw_path = try allocator.dupe(u8, path),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.raw_path);
    }

    /// String representation
    pub fn toString(self: *const Self) []const u8 {
        return self.raw_path;
    }

    /// Return path with forward slashes
    pub fn as_posix(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        if (comptime @import("builtin").os.tag == .windows) {
            const result = try allocator.dupe(u8, self.raw_path);
            for (result) |*c| {
                if (c.* == '\\') c.* = '/';
            }
            return result;
        }
        return self.raw_path;
    }

    /// The drive prefix, if any
    pub fn drive(self: *const Self) []const u8 {
        return self.parser.splitdrive(self.raw_path)[0];
    }

    /// The root of the path, if any
    pub fn root(self: *const Self) []const u8 {
        const tail = self.parser.splitdrive(self.raw_path)[1];
        if (tail.len > 0 and tail[0] == std.fs.path.sep) {
            return tail[0..1];
        }
        return "";
    }

    /// The final path component
    pub fn name(self: *const Self) []const u8 {
        return std.fs.path.basename(self.raw_path);
    }

    /// The file extension
    pub fn suffix(self: *const Self) []const u8 {
        const n = self.name();
        if (std.mem.lastIndexOf(u8, n, ".")) |i| {
            if (i > 0 and i < n.len - 1) return n[i..];
        }
        return "";
    }

    /// The stem (name without suffix)
    pub fn stem(self: *const Self) []const u8 {
        const n = self.name();
        if (std.mem.lastIndexOf(u8, n, ".")) |i| {
            if (i > 0 and i < n.len - 1) return n[0..i];
        }
        return n;
    }

    /// Check if path is absolute
    pub fn is_absolute(self: *const Self) bool {
        return self.parser.isabs(self.raw_path);
    }
};

// ============================================================================
// PathBase
// ============================================================================

/// Base class for concrete path objects (with I/O operations)
pub const PathBase = struct {
    const Self = @This();

    pure: PurePathBase,
    max_symlinks: u32 = 40,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return .{
            .pure = try PurePathBase.init(allocator, path),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pure.deinit();
    }

    /// stat() - get file status
    pub fn stat(self: *const Self) !std.fs.File.Stat {
        return std.fs.cwd().statFile(self.pure.raw_path);
    }

    /// Check if path exists
    pub fn exists(self: *const Self) bool {
        std.fs.cwd().access(self.pure.raw_path, .{}) catch return false;
        return true;
    }

    /// Check if path is a directory
    pub fn is_dir(self: *const Self) bool {
        var dir = std.fs.cwd().openDir(self.pure.raw_path, .{}) catch return false;
        dir.close();
        return true;
    }

    /// Check if path is a file
    pub fn is_file(self: *const Self) bool {
        const s = self.stat() catch return false;
        return s.kind == .file;
    }

    /// Check if path is a symlink
    pub fn is_symlink(self: *const Self) bool {
        const s = std.fs.cwd().statFile(self.pure.raw_path) catch return false;
        return s.kind == .sym_link;
    }

    /// Read file contents
    pub fn read_bytes(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        const file = try std.fs.cwd().openFile(self.pure.raw_path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }

    /// Read file as text
    pub fn read_text(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return self.read_bytes(allocator);
    }

    /// Write bytes to file
    pub fn write_bytes(self: *const Self, data: []const u8) !void {
        const file = try std.fs.cwd().createFile(self.pure.raw_path, .{});
        defer file.close();
        try file.writeAll(data);
    }

    /// Write text to file
    pub fn write_text(self: *const Self, data: []const u8) !void {
        return self.write_bytes(data);
    }

    /// Create directory
    pub fn mkdir(self: *const Self) !void {
        try std.fs.cwd().makeDir(self.pure.raw_path);
    }

    /// Remove file
    pub fn unlink(self: *const Self) !void {
        try std.fs.cwd().deleteFile(self.pure.raw_path);
    }

    /// Remove directory
    pub fn rmdir(self: *const Self) !void {
        try std.fs.cwd().deleteDir(self.pure.raw_path);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PurePathBase basic" {
    const allocator = std.testing.allocator;
    var p = try PurePathBase.init(allocator, "/tmp/test.txt");
    defer p.deinit();

    try std.testing.expectEqualStrings("/tmp/test.txt", p.toString());
    try std.testing.expectEqualStrings("test.txt", p.name());
    try std.testing.expectEqualStrings("test", p.stem());
    try std.testing.expectEqualStrings(".txt", p.suffix());
    try std.testing.expect(p.is_absolute());
}

test "PathBase exists" {
    const allocator = std.testing.allocator;
    var p = try PathBase.init(allocator, "/tmp");
    defer p.deinit();

    try std.testing.expect(p.exists());
    try std.testing.expect(p.is_dir());
}
