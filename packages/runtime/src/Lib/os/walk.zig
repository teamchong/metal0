/// Directory traversal (os.walk)
/// CPython Reference: https://docs.python.org/3.12/library/os.html#os.walk
const std = @import("std");
const path_mod = @import("path.zig");

/// Entry from os.walk() - (dirpath, dirnames, filenames)
pub const WalkEntry = struct {
    dirpath: []const u8,
    dirnames: [][]const u8,
    filenames: [][]const u8,
};

/// Iterator for os.walk() - recursive directory traversal
pub const WalkIterator = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList([]const u8),
    topdown: bool,

    pub fn next(self: *WalkIterator) !?WalkEntry {
        while (self.stack.items.len > 0) {
            const dir_path = self.stack.pop();
            defer self.allocator.free(dir_path);

            var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var dirnames = std.ArrayList([]const u8).init(self.allocator);
            var filenames = std.ArrayList([]const u8).init(self.allocator);
            errdefer {
                for (dirnames.items) |d| self.allocator.free(d);
                dirnames.deinit();
                for (filenames.items) |f| self.allocator.free(f);
                filenames.deinit();
            }

            var iter = dir.iterate();
            while (iter.next() catch null) |entry| {
                const entry_name = try self.allocator.dupe(u8, entry.name);
                if (entry.kind == .directory) {
                    try dirnames.append(entry_name);
                } else {
                    try filenames.append(entry_name);
                }
            }

            // Add subdirectories to stack for traversal
            if (self.topdown) {
                // For topdown, add in reverse order so we process in order
                var i: usize = dirnames.items.len;
                while (i > 0) {
                    i -= 1;
                    const subdir = try path_mod.join(self.allocator, &.{ dir_path, dirnames.items[i] });
                    try self.stack.append(subdir);
                }
            }

            return WalkEntry{
                .dirpath = try self.allocator.dupe(u8, dir_path),
                .dirnames = try dirnames.toOwnedSlice(),
                .filenames = try filenames.toOwnedSlice(),
            };
        }
        return null;
    }

    pub fn deinit(self: *WalkIterator) void {
        for (self.stack.items) |p| self.allocator.free(p);
        self.stack.deinit();
    }
};

/// os.walk(top, topdown=True) - Directory tree generator
/// Yields (dirpath, dirnames, filenames) for each directory in the tree
pub fn walk(allocator: std.mem.Allocator, top: []const u8) !WalkIterator {
    return walkTopdown(allocator, top, true);
}

/// os.walk with topdown parameter
pub fn walkTopdown(allocator: std.mem.Allocator, top: []const u8, topdown: bool) !WalkIterator {
    var stack = std.ArrayList([]const u8).init(allocator);
    try stack.append(try allocator.dupe(u8, top));
    return WalkIterator{
        .allocator = allocator,
        .stack = stack,
        .topdown = topdown,
    };
}
