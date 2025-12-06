/// fileutils - File Utilities
/// Mirrors cpython/Python/fileutils.c
///
/// This module provides low-level file system utilities used by the Python runtime:
/// - File descriptor operations (open, close, read, write)
/// - Path manipulation and validation
/// - Encoding detection and conversion
/// - File mode handling (text/binary)
/// - Cross-platform file system operations

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Error Handling
// ============================================================================

/// Error handler modes for file operations
pub const ErrorHandler = enum {
    strict, // Raise exception on error
    surrogateescape, // Use surrogate escapes for invalid bytes
    surrogatepass, // Allow surrogates in UTF-16
    ignore, // Ignore errors
    replace, // Replace invalid bytes with replacement char
    backslashreplace, // Use backslash escapes
    xmlcharrefreplace, // Use XML character references
    namereplace, // Use named references
};

/// File operation errors
pub const FileError = error{
    FileNotFound,
    AccessDenied,
    InvalidPath,
    IsDirectory,
    NotDirectory,
    Exists,
    NoSpace,
    InvalidEncoding,
    TooManyOpenFiles,
    BrokenPipe,
    IOError,
    Interrupted,
    Timeout,
    OutOfMemory,
};

// ============================================================================
// File Descriptor Operations
// ============================================================================

/// Open flags matching CPython's os module
pub const OpenFlags = packed struct {
    read: bool = false,
    write: bool = false,
    append: bool = false,
    create: bool = false,
    exclusive: bool = false,
    truncate: bool = false,
    binary: bool = false,
    text: bool = true,
    cloexec: bool = true, // Close on exec by default
    nonblock: bool = false,
    directory: bool = false,
    sync: bool = false,
    _padding: u4 = 0,
};

/// Open a file with the given flags
pub fn open(path: []const u8, flags: OpenFlags) FileError!std.fs.File {
    var std_flags: std.fs.File.OpenFlags = .{};

    if (flags.read and flags.write) {
        std_flags.mode = .read_write;
    } else if (flags.write) {
        std_flags.mode = .write_only;
    } else {
        std_flags.mode = .read_only;
    }

    // Use cwd() for relative paths
    const file = std.fs.cwd().openFile(path, std_flags) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            error.IsDir => FileError.IsDirectory,
            else => FileError.IOError,
        };
    };

    return file;
}

/// Create a file
pub fn create(path: []const u8, mode: u9) FileError!std.fs.File {
    _ = mode;
    return std.fs.cwd().createFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.InvalidPath,
            error.AccessDenied => FileError.AccessDenied,
            error.PathAlreadyExists => FileError.Exists,
            else => FileError.IOError,
        };
    };
}

/// Close a file descriptor
pub fn close(file: std.fs.File) void {
    file.close();
}

/// Read from file descriptor
pub fn read(file: std.fs.File, buffer: []u8) FileError!usize {
    return file.read(buffer) catch FileError.IOError;
}

/// Write to file descriptor
pub fn write(file: std.fs.File, data: []const u8) FileError!usize {
    return file.write(data) catch |err| {
        return switch (err) {
            error.BrokenPipe => FileError.BrokenPipe,
            else => FileError.IOError,
        };
    };
}

/// Seek in file
pub fn seek(file: std.fs.File, offset: i64, whence: std.fs.File.SeekableStream.SeekOrigin) FileError!u64 {
    _ = file.seekTo(@intCast(offset)) catch return FileError.IOError;
    return file.getPos() catch return FileError.IOError;
}

/// Get current position
pub fn tell(file: std.fs.File) FileError!u64 {
    return file.getPos() catch FileError.IOError;
}

/// Check if file descriptor is a TTY
pub fn isatty(file: std.fs.File) bool {
    return std.posix.isatty(file.handle);
}

// ============================================================================
// Path Operations
// ============================================================================

/// Path separator for current platform
pub const SEP: u8 = if (builtin.os.tag == .windows) '\\' else '/';

/// Alternative separator (Windows has both)
pub const ALTSEP: ?u8 = if (builtin.os.tag == .windows) '/' else null;

/// Extension separator
pub const EXTSEP: u8 = '.';

/// Path list separator (e.g., in PATH environment variable)
pub const PATHSEP: u8 = if (builtin.os.tag == .windows) ';' else ':';

/// Join path components
pub fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    if (parts.len == 0) return "";

    var size: usize = 0;
    for (parts) |part| {
        if (part.len > 0) {
            size += part.len + 1; // +1 for separator
        }
    }

    var result = try allocator.alloc(u8, size);
    var pos: usize = 0;

    for (parts) |part| {
        if (part.len == 0) continue;

        // Skip leading separator if not first
        var start: usize = 0;
        if (pos > 0 and part[0] == SEP) {
            start = 1;
        }

        // Add separator if needed
        if (pos > 0 and result[pos - 1] != SEP) {
            result[pos] = SEP;
            pos += 1;
        }

        // Copy part
        @memcpy(result[pos .. pos + part.len - start], part[start..]);
        pos += part.len - start;
    }

    return result[0..pos];
}

/// Get directory name from path
pub fn dirname(path: []const u8) []const u8 {
    if (path.len == 0) return ".";

    // Find last separator
    var i = path.len;
    while (i > 0) : (i -= 1) {
        if (path[i - 1] == SEP) {
            if (i == 1) return "/";
            return path[0 .. i - 1];
        }
    }
    return ".";
}

/// Get base name from path
pub fn basename(path: []const u8) []const u8 {
    if (path.len == 0) return "";

    // Find last separator
    var i = path.len;
    while (i > 0) : (i -= 1) {
        if (path[i - 1] == SEP) {
            return path[i..];
        }
    }
    return path;
}

/// Get file extension
pub fn extension(path: []const u8) []const u8 {
    const base = basename(path);
    if (base.len == 0) return "";

    // Find last dot (not at start)
    var i = base.len;
    while (i > 0) : (i -= 1) {
        if (base[i - 1] == EXTSEP) {
            if (i == 1) return ""; // Hidden file, not extension
            return base[i - 1 ..];
        }
    }
    return "";
}

/// Split path into directory and basename
pub fn splitPath(path: []const u8) struct { []const u8, []const u8 } {
    return .{ dirname(path), basename(path) };
}

/// Split extension from path
pub fn splitExt(path: []const u8) struct { []const u8, []const u8 } {
    const ext = extension(path);
    if (ext.len == 0) return .{ path, "" };
    return .{ path[0 .. path.len - ext.len], ext };
}

/// Normalize path (remove redundant separators and ..)
pub fn normpath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (path.len == 0) return ".";

    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    const is_absolute = path[0] == SEP;

    // Split by separator
    var iter = std.mem.splitSequence(u8, path, &[_]u8{SEP});
    while (iter.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) {
            continue;
        }
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
            } else if (!is_absolute) {
                try parts.append("..");
            }
        } else {
            try parts.append(part);
        }
    }

    // Rebuild path
    if (parts.items.len == 0) {
        return if (is_absolute) "/" else ".";
    }

    return joinPath(allocator, parts.items);
}

/// Check if path is absolute
pub fn isabs(path: []const u8) bool {
    if (path.len == 0) return false;
    if (builtin.os.tag == .windows) {
        // Windows: C:\ or \\server or /
        if (path.len >= 3 and path[1] == ':' and (path[2] == '\\' or path[2] == '/')) {
            return true;
        }
        if (path.len >= 2 and path[0] == '\\' and path[1] == '\\') {
            return true;
        }
    }
    return path[0] == SEP;
}

/// Get absolute path
pub fn abspath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (isabs(path)) {
        return normpath(allocator, path);
    }

    var cwd_buf: [4096]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch return FileError.IOError;

    const parts = [_][]const u8{ cwd, path };
    const joined = try joinPath(allocator, &parts);
    defer allocator.free(joined);

    return normpath(allocator, joined);
}

/// Check if path exists
pub fn exists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    _ = stat;
    return true;
}

/// Check if path is a file
pub fn isfile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Check if path is a directory
pub fn isdir(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

/// Check if path is a symbolic link
pub fn islink(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .sym_link;
}

// ============================================================================
// Encoding Detection
// ============================================================================

/// Get the device encoding for a file descriptor
pub fn deviceEncoding(file: std.fs.File) []const u8 {
    if (!isatty(file)) {
        return "utf-8"; // Default for non-TTY
    }

    // On most modern systems, terminals use UTF-8
    if (builtin.os.tag == .windows) {
        // Windows console uses system code page
        return "utf-8"; // Simplified
    }

    return "utf-8";
}

/// Get the filesystem encoding
pub fn filesystemEncoding() []const u8 {
    if (builtin.os.tag == .windows) {
        return "utf-8"; // Windows uses UTF-8 with proper APIs
    }
    // Unix systems typically use UTF-8
    return "utf-8";
}

/// Get locale encoding
pub fn localeEncoding() []const u8 {
    // Simplified - in reality would check LC_CTYPE
    return "utf-8";
}

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
// File Statistics
// ============================================================================

/// File stat result
pub const StatResult = struct {
    mode: u32,
    size: u64,
    atime: i128,
    mtime: i128,
    ctime: i128,
    is_dir: bool,
    is_file: bool,
    is_link: bool,
};

/// Get file statistics
pub fn stat(path: []const u8) FileError!StatResult {
    const s = std.fs.cwd().statFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };

    return StatResult{
        .mode = s.mode,
        .size = s.size,
        .atime = s.atime,
        .mtime = s.mtime,
        .ctime = s.ctime,
        .is_dir = s.kind == .directory,
        .is_file = s.kind == .file,
        .is_link = s.kind == .sym_link,
    };
}

/// Get file size
pub fn getsize(path: []const u8) FileError!u64 {
    const s = try stat(path);
    return s.size;
}

/// Get modification time
pub fn getmtime(path: []const u8) FileError!i128 {
    const s = try stat(path);
    return s.mtime;
}

// ============================================================================
// Directory Operations
// ============================================================================

/// Read directory contents
pub fn listdir(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        return FileError.IOError;
    };
    defer dir.close();

    var names = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit();
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        try names.append(name);
    }

    return names.toOwnedSlice();
}

/// Create directory
pub fn mkdir(path: []const u8) FileError!void {
    std.fs.cwd().makeDir(path) catch |err| {
        return switch (err) {
            error.PathAlreadyExists => FileError.Exists,
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };
}

/// Create directory recursively
pub fn makedirs(path: []const u8) FileError!void {
    std.fs.cwd().makePath(path) catch |err| {
        return switch (err) {
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };
}

/// Remove directory
pub fn rmdir(path: []const u8) FileError!void {
    std.fs.cwd().deleteDir(path) catch |err| {
        return switch (err) {
            error.DirNotEmpty => FileError.IOError,
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };
}

// ============================================================================
// File Operations
// ============================================================================

/// Remove file
pub fn unlink(path: []const u8) FileError!void {
    std.fs.cwd().deleteFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            error.IsDir => FileError.IsDirectory,
            else => FileError.IOError,
        };
    };
}

/// Rename file or directory
pub fn rename(old_path: []const u8, new_path: []const u8) FileError!void {
    std.fs.cwd().rename(old_path, new_path) catch {
        return FileError.IOError;
    };
}

/// Copy file
pub fn copy(src: []const u8, dst: []const u8) FileError!void {
    std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{}) catch {
        return FileError.IOError;
    };
}

// ============================================================================
// Current Working Directory
// ============================================================================

/// Get current working directory
pub fn getcwd(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [4096]u8 = undefined;
    const path = std.fs.cwd().realpath(".", &buf) catch return FileError.IOError;
    return allocator.dupe(u8, path);
}

/// Change current working directory
pub fn chdir(path: []const u8) FileError!void {
    std.posix.chdir(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            error.NotDir => FileError.NotDirectory,
            else => FileError.IOError,
        };
    };
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize file utilities
pub fn init() void {
    // No initialization needed for Zig stdlib
}

// ============================================================================
// Tests
// ============================================================================

test "path operations" {
    try std.testing.expectEqualStrings(".", dirname("foo"));
    try std.testing.expectEqualStrings("/usr", dirname("/usr/bin"));
    try std.testing.expectEqualStrings("foo", basename("foo"));
    try std.testing.expectEqualStrings("bar", basename("/foo/bar"));
    try std.testing.expectEqualStrings(".txt", extension("file.txt"));
    try std.testing.expectEqualStrings("", extension("file"));
}

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

test "isabs" {
    try std.testing.expect(isabs("/foo/bar"));
    try std.testing.expect(!isabs("foo/bar"));
    try std.testing.expect(!isabs(""));
}

test "split operations" {
    const split1 = splitPath("/foo/bar");
    try std.testing.expectEqualStrings("/foo", split1[0]);
    try std.testing.expectEqualStrings("bar", split1[1]);

    const split2 = splitExt("file.txt");
    try std.testing.expectEqualStrings("file", split2[0]);
    try std.testing.expectEqualStrings(".txt", split2[1]);
}

test "join path" {
    const allocator = std.testing.allocator;
    const parts = [_][]const u8{ "foo", "bar", "baz" };
    const joined = try joinPath(allocator, &parts);
    defer allocator.free(joined);
    try std.testing.expectEqualStrings("foo/bar/baz", joined);
}
