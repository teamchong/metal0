/// Pathlib runtime - Path operations for AOT compilation
const std = @import("std");

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

    /// Read the entire file contents as a string
    pub fn read_text(self: *const Path, allocator: std.mem.Allocator) ![]const u8 {
        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();
        return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
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
};
