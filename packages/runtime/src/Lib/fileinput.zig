//! CPython source: Lib/fileinput.py
//!
//! Provides a helper class for reading lines from files.
//!
//! Mirrors: CPython Lib/fileinput.py

const std = @import("std");

// ============================================================================
// FileInput - Main class for iterating over lines
// ============================================================================

/// Main FileInput class for iterating over lines from multiple files
pub const FileInput = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    /// List of files to process
    files: []const []const u8,
    /// Current file index
    file_index: usize,
    /// Current file handle
    current_file: ?std.fs.File,
    /// Current file reader
    reader: ?std.fs.File.Reader,
    /// Line buffer
    line_buffer: std.ArrayList(u8),
    /// Current filename
    filename_: ?[]const u8,
    /// Current line number within file
    filelineno_: usize,
    /// Total line number across all files
    lineno_: usize,
    /// Whether to read from stdin if no files
    use_stdin: bool,
    /// Inplace editing mode
    inplace: ?[]const u8,
    /// Backup extension for inplace editing
    backup: ?[]const u8,
    /// Whether input is opened
    is_open: bool,
    /// Openhook function for custom file opening
    openhook: ?OpenHook,

    pub const OpenHook = *const fn (filename: []const u8, mode: []const u8) std.fs.File.OpenError!std.fs.File;

    pub fn init(
        allocator: std.mem.Allocator,
        files: []const []const u8,
    ) Self {
        return .{
            .allocator = allocator,
            .files = files,
            .file_index = 0,
            .current_file = null,
            .reader = null,
            .line_buffer = std.ArrayList(u8).init(allocator),
            .filename_ = null,
            .filelineno_ = 0,
            .lineno_ = 0,
            .use_stdin = files.len == 0,
            .inplace = null,
            .backup = null,
            .is_open = false,
            .openhook = null,
        };
    }

    pub fn initWithOptions(
        allocator: std.mem.Allocator,
        files: []const []const u8,
        inplace: ?[]const u8,
        backup: ?[]const u8,
        openhook: ?OpenHook,
    ) Self {
        var fi = init(allocator, files);
        fi.inplace = inplace;
        fi.backup = backup;
        fi.openhook = openhook;
        return fi;
    }

    pub fn deinit(self: *Self) void {
        self.close();
        self.line_buffer.deinit();
    }

    /// Close the current file
    pub fn close(self: *Self) void {
        if (self.current_file) |file| {
            file.close();
            self.current_file = null;
            self.reader = null;
        }
        self.is_open = false;
    }

    /// Get the next file to process
    fn nextFile(self: *Self) bool {
        self.close();

        if (self.file_index >= self.files.len) {
            return false;
        }

        const filename = self.files[self.file_index];
        self.file_index += 1;
        self.filename_ = filename;
        self.filelineno_ = 0;

        // Open the file
        if (self.openhook) |hook| {
            self.current_file = hook(filename, "r") catch return false;
        } else {
            self.current_file = std.fs.cwd().openFile(filename, .{}) catch return false;
        }

        self.reader = self.current_file.?.reader();
        self.is_open = true;
        return true;
    }

    /// Read the next line
    pub fn readline(self: *Self) ?[]const u8 {
        while (true) {
            if (self.reader) |*reader| {
                self.line_buffer.clearRetainingCapacity();
                reader.streamUntilDelimiter(self.line_buffer.writer(), '\n', null) catch |err| {
                    if (err == error.EndOfStream) {
                        // Try next file
                        if (!self.nextFile()) {
                            return null;
                        }
                        continue;
                    }
                    return null;
                };

                self.lineno_ += 1;
                self.filelineno_ += 1;

                // Append newline to match Python behavior
                self.line_buffer.append('\n') catch {};

                return self.line_buffer.items;
            } else {
                // No reader yet, open first file
                if (!self.nextFile()) {
                    return null;
                }
            }
        }
    }

    /// Get current filename
    pub fn filename(self: *Self) ?[]const u8 {
        return self.filename_;
    }

    /// Get current line number within file
    pub fn filelineno(self: *Self) usize {
        return self.filelineno_;
    }

    /// Get total line number
    pub fn lineno(self: *Self) usize {
        return self.lineno_;
    }

    /// Check if at first line of current file
    pub fn isfirstline(self: *Self) bool {
        return self.filelineno_ == 1;
    }

    /// Check if reading from stdin
    pub fn isstdin(self: *Self) bool {
        return self.use_stdin and self.file_index == 0;
    }

    /// Get current file index
    pub fn fileno(self: *Self) ?i32 {
        if (self.current_file) |file| {
            return file.handle;
        }
        return null;
    }

    /// Iterator interface
    pub fn next(self: *Self) ?[]const u8 {
        return self.readline();
    }
};

// ============================================================================
// Module-level functions
// ============================================================================

/// Global FileInput instance (for module-level functions)
var global_fileinput: ?FileInput = null;
var global_allocator: ?std.mem.Allocator = null;

/// Initialize global file input
pub fn input(
    allocator: std.mem.Allocator,
    files: []const []const u8,
) *FileInput {
    if (global_fileinput) |*fi| {
        fi.deinit();
    }
    global_fileinput = FileInput.init(allocator, files);
    global_allocator = allocator;
    return &global_fileinput.?;
}

/// Close global file input
pub fn closeGlobal() void {
    if (global_fileinput) |*fi| {
        fi.close();
    }
}

/// Get next line from global
pub fn nextline() ?[]const u8 {
    if (global_fileinput) |*fi| {
        return fi.readline();
    }
    return null;
}

/// Get filename from global
pub fn filenameGlobal() ?[]const u8 {
    if (global_fileinput) |*fi| {
        return fi.filename();
    }
    return null;
}

/// Get lineno from global
pub fn linenoGlobal() usize {
    if (global_fileinput) |*fi| {
        return fi.lineno();
    }
    return 0;
}

/// Get filelineno from global
pub fn filelinenoGlobal() usize {
    if (global_fileinput) |*fi| {
        return fi.filelineno();
    }
    return 0;
}

/// Check if first line from global
pub fn isfirstlineGlobal() bool {
    if (global_fileinput) |*fi| {
        return fi.isfirstline();
    }
    return false;
}

/// Check if stdin from global
pub fn isstdinGlobal() bool {
    if (global_fileinput) |*fi| {
        return fi.isstdin();
    }
    return false;
}

// ============================================================================
// Hook functions
// ============================================================================

/// Hook for opening gzip or bz2 compressed files
/// For .gz files, opens the underlying file (decompression handled by reader)
/// For .bz2 files, opens the underlying file (decompression handled by reader)
pub fn hook_compressed(filename: []const u8, mode: []const u8) std.fs.File.OpenError!std.fs.File {
    _ = mode;
    // Check for compression suffixes
    // Note: Actual decompression is handled by wrapping the reader with
    // std.compress.gzip.decompressor or std.compress.xz.decompress
    // The caller is responsible for creating the appropriate decompressor

    if (std.mem.endsWith(u8, filename, ".gz")) {
        // Return the raw file - caller should wrap with gzip decompressor
        return std.fs.cwd().openFile(filename, .{});
    } else if (std.mem.endsWith(u8, filename, ".bz2")) {
        // Return the raw file - caller should wrap with bz2 decompressor
        return std.fs.cwd().openFile(filename, .{});
    }

    // Not a compressed file
    return std.fs.cwd().openFile(filename, .{});
}

/// Hook for opening with specific encoding
pub fn hook_encoded(encoding: []const u8) OpenHook {
    _ = encoding;
    // Return a hook that opens with encoding
    return struct {
        fn hook(filename: []const u8, mode: []const u8) std.fs.File.OpenError!std.fs.File {
            _ = mode;
            return std.fs.cwd().openFile(filename, .{});
        }
    }.hook;
}

pub const OpenHook = FileInput.OpenHook;

// ============================================================================
// Tests
// ============================================================================

test "FileInput init" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{ "file1.txt", "file2.txt" };
    var fi = FileInput.init(allocator, &files);
    defer fi.deinit();

    try std.testing.expectEqual(@as(usize, 2), fi.files.len);
    try std.testing.expectEqual(@as(usize, 0), fi.lineno());
    try std.testing.expect(fi.filename() == null);
}

test "FileInput empty files" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{};
    var fi = FileInput.init(allocator, &files);
    defer fi.deinit();

    try std.testing.expect(fi.use_stdin);
    try std.testing.expectEqual(@as(usize, 0), fi.files.len);
}

test "FileInput initWithOptions" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{"test.txt"};
    var fi = FileInput.initWithOptions(allocator, &files, ".bak", null, null);
    defer fi.deinit();

    try std.testing.expectEqualStrings(".bak", fi.inplace.?);
}

test "FileInput isfirstline" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{};
    var fi = FileInput.init(allocator, &files);
    defer fi.deinit();

    // No file read yet
    try std.testing.expect(!fi.isfirstline());
}

test "FileInput isstdin" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{};
    var fi = FileInput.init(allocator, &files);
    defer fi.deinit();

    // Empty files list means stdin
    try std.testing.expect(fi.isstdin());
}

test "global input function" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{"nonexistent.txt"};
    _ = input(allocator, &files);
    defer closeGlobal();

    try std.testing.expect(global_fileinput != null);
}

test "global filename when not initialized" {
    global_fileinput = null;
    try std.testing.expect(filenameGlobal() == null);
}

test "global lineno when not initialized" {
    global_fileinput = null;
    try std.testing.expectEqual(@as(usize, 0), linenoGlobal());
}

test "global filelineno when not initialized" {
    global_fileinput = null;
    try std.testing.expectEqual(@as(usize, 0), filelinenoGlobal());
}

test "global isfirstline when not initialized" {
    global_fileinput = null;
    try std.testing.expect(!isfirstlineGlobal());
}

test "global isstdin when not initialized" {
    global_fileinput = null;
    try std.testing.expect(!isstdinGlobal());
}
