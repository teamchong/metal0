/// Pathlib runtime - Path operations for AOT compilation
const std = @import("std");

/// Lazy file contents - mmap'd or read on demand
pub const LazyFile = struct {
    path: []const u8,
    allocator: std.mem.Allocator,
    /// Memory-mapped data (preferred for large files)
    mmap_data: ?[]align(std.mem.page_size) const u8,
    /// Fallback: allocated data for small files or mmap failure
    alloc_data: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) LazyFile {
        return .{
            .path = path,
            .allocator = allocator,
            .mmap_data = null,
            .alloc_data = null,
        };
    }

    /// Get file contents - reads/maps on first access
    pub fn get(self: *LazyFile) ![]const u8 {
        // Return cached if available
        if (self.mmap_data) |data| return data;
        if (self.alloc_data) |data| return data;

        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();

        const stat = try file.stat();
        const file_size = stat.size;

        // For large files (>64KB), try mmap
        if (file_size > 65536) {
            if (std.posix.mmap(
                null,
                file_size,
                std.posix.PROT.READ,
                .{ .TYPE = .PRIVATE },
                file.handle,
                0,
            )) |mapped| {
                self.mmap_data = mapped;
                return mapped;
            } else |_| {
                // mmap failed, fall through to regular read
            }
        }

        // Small file or mmap failed - regular read
        self.alloc_data = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        return self.alloc_data.?;
    }

    /// Get size without reading content
    pub fn size(self: *const LazyFile) !u64 {
        if (self.mmap_data) |data| return data.len;
        if (self.alloc_data) |data| return data.len;

        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();
        const stat = try file.stat();
        return stat.size;
    }

    pub fn deinit(self: *LazyFile) void {
        if (self.mmap_data) |data| {
            std.posix.munmap(data);
            self.mmap_data = null;
        }
        if (self.alloc_data) |data| {
            self.allocator.free(data);
            self.alloc_data = null;
        }
    }
};

/// Path object - wraps a filesystem path
pub const Path = struct {
    path: []const u8,
    allocator: std.mem.Allocator,

    /// Create a new Path from a string (called by Python's Path() constructor)
    pub fn init(allocator: std.mem.Allocator, path_str: []const u8) !*Path {
        const p = try allocator.create(Path);
        p.* = .{
            .path = try allocator.dupe(u8, path_str),
            .allocator = allocator,
        };
        return p;
    }

    /// Alias for init (for internal use)
    pub fn create(allocator: std.mem.Allocator, path_str: []const u8) !*Path {
        return init(allocator, path_str);
    }

    /// Destroy the Path and free memory
    pub fn destroy(self: *Path) void {
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    /// Check if the path exists on the filesystem
    pub fn exists(self: *const Path) bool {
        std.fs.cwd().access(self.path, .{}) catch return false;
        return true;
    }

    /// Read the entire file contents as a string (eager - copies all data)
    pub fn read_text(self: *const Path, allocator: std.mem.Allocator) ![]const u8 {
        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();
        return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }

    /// Get lazy file handle - reads/mmap on first access
    pub fn read_text_lazy(self: *const Path, allocator: std.mem.Allocator) LazyFile {
        return LazyFile.init(allocator, self.path);
    }

    /// Check if the path is a regular file
    pub fn is_file(self: *const Path) bool {
        const stat = std.fs.cwd().statFile(self.path) catch return false;
        return stat.kind == .file;
    }

    /// Check if the path is a directory
    pub fn is_dir(self: *const Path) bool {
        var dir = std.fs.cwd().openDir(self.path, .{}) catch return false;
        dir.close();
        return true;
    }

    /// Get the string representation of the path
    pub fn toString(self: *const Path) []const u8 {
        return self.path;
    }

    /// Get the parent directory as a new Path
    pub fn parent(self: *const Path) *Path {
        const dir = std.fs.path.dirname(self.path) orelse ".";
        // Create new Path with same allocator
        const p = self.allocator.create(Path) catch unreachable;
        p.* = .{
            .path = self.allocator.dupe(u8, dir) catch unreachable,
            .allocator = self.allocator,
        };
        return p;
    }

    /// Join path with another component (Python's Path / operator)
    pub fn join(self: *const Path, component: []const u8) *Path {
        const joined = std.fs.path.join(self.allocator, &.{ self.path, component }) catch unreachable;
        const p = self.allocator.create(Path) catch unreachable;
        p.* = .{
            .path = joined,
            .allocator = self.allocator,
        };
        return p;
    }

    /// Get the file name (last component)
    pub fn name(self: *const Path) []const u8 {
        return std.fs.path.basename(self.path);
    }

    /// Get the file stem (name without extension)
    pub fn stem(self: *const Path) []const u8 {
        const basename = std.fs.path.basename(self.path);
        if (std.mem.lastIndexOf(u8, basename, ".")) |dot_pos| {
            if (dot_pos > 0) return basename[0..dot_pos];
        }
        return basename;
    }

    /// Get the file suffix (extension including dot)
    pub fn suffix(self: *const Path) []const u8 {
        const basename = std.fs.path.basename(self.path);
        if (std.mem.lastIndexOf(u8, basename, ".")) |dot_pos| {
            if (dot_pos > 0) return basename[dot_pos..];
        }
        return "";
    }

    /// Check if path is absolute
    pub fn is_absolute(self: *const Path) bool {
        return std.fs.path.isAbsolute(self.path);
    }

    /// Get absolute path
    pub fn absolute(self: *const Path) *Path {
        if (std.fs.path.isAbsolute(self.path)) {
            return self.allocator.create(Path) catch unreachable;
        }
        const cwd = std.fs.cwd().realpathAlloc(self.allocator, ".") catch return self.allocator.create(Path) catch unreachable;
        defer self.allocator.free(cwd);
        const abs = std.fs.path.join(self.allocator, &.{ cwd, self.path }) catch unreachable;
        const p = self.allocator.create(Path) catch unreachable;
        p.* = .{ .path = abs, .allocator = self.allocator };
        return p;
    }

    /// Resolve path (make absolute and normalize)
    pub fn resolve(self: *const Path) *Path {
        const resolved = std.fs.cwd().realpathAlloc(self.allocator, self.path) catch {
            // If path doesn't exist, just make it absolute
            return self.absolute();
        };
        const p = self.allocator.create(Path) catch unreachable;
        p.* = .{ .path = resolved, .allocator = self.allocator };
        return p;
    }

    /// Write text to file
    pub fn write_text(self: *const Path, content: []const u8) !void {
        const file = try std.fs.cwd().createFile(self.path, .{});
        defer file.close();
        try file.writeAll(content);
    }

    /// Write bytes to file
    pub fn write_bytes(self: *const Path, content: []const u8) !void {
        return self.write_text(content);
    }

    /// Read bytes from file
    pub fn read_bytes(self: *const Path, allocator: std.mem.Allocator) ![]const u8 {
        return self.read_text(allocator);
    }

    /// Create directory (mkdir)
    pub fn mkdir(self: *const Path) !void {
        try std.fs.cwd().makeDir(self.path);
    }

    /// Create directory and parents (mkdir -p)
    pub fn mkdir_parents(self: *const Path) !void {
        std.fs.cwd().makePath(self.path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    /// Remove file (unlink)
    pub fn unlink(self: *const Path) !void {
        try std.fs.cwd().deleteFile(self.path);
    }

    /// Remove directory (rmdir) - must be empty
    pub fn rmdir(self: *const Path) !void {
        try std.fs.cwd().deleteDir(self.path);
    }

    /// Rename/move file
    pub fn rename(self: *const Path, target: []const u8) !*Path {
        try std.fs.cwd().rename(self.path, target);
        const p = try self.allocator.create(Path);
        p.* = .{
            .path = try self.allocator.dupe(u8, target),
            .allocator = self.allocator,
        };
        return p;
    }

    /// Check if path is a symlink
    pub fn is_symlink(self: *const Path) bool {
        const stat = std.fs.cwd().statFile(self.path) catch return false;
        return stat.kind == .sym_link;
    }

    /// Get file size in bytes
    pub fn stat_size(self: *const Path) !u64 {
        const stat = try std.fs.cwd().statFile(self.path);
        return stat.size;
    }

    /// Iterate over directory contents (iterdir)
    pub fn iterdir(self: *const Path, allocator: std.mem.Allocator) !std.ArrayList(*Path) {
        var result = std.ArrayList(*Path).init(allocator);
        errdefer {
            for (result.items) |p| p.destroy();
            result.deinit();
        }

        var dir = try std.fs.cwd().openDir(self.path, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const child_path = try std.fs.path.join(allocator, &.{ self.path, entry.name });
            const p = try allocator.create(Path);
            p.* = .{ .path = child_path, .allocator = allocator };
            try result.append(p);
        }

        return result;
    }

    /// Get all parts of the path
    pub fn parts(self: *const Path, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(allocator);
        var iter = std.mem.splitScalar(u8, self.path, std.fs.path.sep);
        while (iter.next()) |part| {
            if (part.len > 0) {
                try result.append(try allocator.dupe(u8, part));
            }
        }
        return result;
    }

    /// Replace the suffix/extension
    pub fn with_suffix(self: *const Path, new_suffix: []const u8) *Path {
        const basename = std.fs.path.basename(self.path);
        const dir = std.fs.path.dirname(self.path) orelse "";

        var stem_end = basename.len;
        if (std.mem.lastIndexOf(u8, basename, ".")) |dot_pos| {
            if (dot_pos > 0) stem_end = dot_pos;
        }

        const stem_part = basename[0..stem_end];
        const new_name = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ stem_part, new_suffix }) catch unreachable;
        defer self.allocator.free(new_name);

        const new_path = if (dir.len > 0)
            std.fs.path.join(self.allocator, &.{ dir, new_name }) catch unreachable
        else
            self.allocator.dupe(u8, new_name) catch unreachable;

        const p = self.allocator.create(Path) catch unreachable;
        p.* = .{ .path = new_path, .allocator = self.allocator };
        return p;
    }

    /// Replace the name (last component)
    pub fn with_name(self: *const Path, new_name: []const u8) *Path {
        const dir = std.fs.path.dirname(self.path) orelse "";
        const new_path = if (dir.len > 0)
            std.fs.path.join(self.allocator, &.{ dir, new_name }) catch unreachable
        else
            self.allocator.dupe(u8, new_name) catch unreachable;

        const p = self.allocator.create(Path) catch unreachable;
        p.* = .{ .path = new_path, .allocator = self.allocator };
        return p;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Path basic" {
    const testing = std.testing;
    const p = try Path.init(testing.allocator, "/tmp/test.txt");
    defer p.destroy();

    try testing.expectEqualStrings("/tmp/test.txt", p.toString());
    try testing.expectEqualStrings("test.txt", p.name());
    try testing.expectEqualStrings("test", p.stem());
    try testing.expectEqualStrings(".txt", p.suffix());
    try testing.expect(p.is_absolute());
}

test "Path parent" {
    const testing = std.testing;
    const p = try Path.init(testing.allocator, "/tmp/dir/file.txt");
    defer p.destroy();

    const par = p.parent();
    defer par.destroy();
    try testing.expectEqualStrings("/tmp/dir", par.toString());
}

test "Path with_suffix" {
    const testing = std.testing;
    const p = try Path.init(testing.allocator, "/tmp/file.txt");
    defer p.destroy();

    const p2 = p.with_suffix(".md");
    defer p2.destroy();
    try testing.expectEqualStrings("/tmp/file.md", p2.toString());
}

test "Path with_name" {
    const testing = std.testing;
    const p = try Path.init(testing.allocator, "/tmp/old.txt");
    defer p.destroy();

    const p2 = p.with_name("new.txt");
    defer p2.destroy();
    try testing.expectEqualStrings("/tmp/new.txt", p2.toString());
}
