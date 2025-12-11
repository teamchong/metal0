/// pkgutil/iterator.zig - Module iteration functionality
/// Provides ModuleIterator for iterating over modules in paths

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

pub const ModuleInfo = types.ModuleInfo;

/// Iterator over modules in a path
pub const ModuleIterator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    path: []const []const u8,
    path_index: usize = 0,
    dir: ?std.fs.Dir = null,
    iter: ?std.fs.Dir.Iterator = null,
    prefix: []const u8 = "",
    seen: hashmap_helper.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, path: ?[]const []const u8, prefix: ?[]const u8) Self {
        const default_path = &[_][]const u8{"."};
        return .{
            .allocator = allocator,
            .path = path orelse default_path,
            .prefix = prefix orelse "",
            .seen = hashmap_helper.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.dir) |*d| {
            d.close();
        }
        self.seen.deinit();
    }

    pub fn next(self: *Self) !?ModuleInfo {
        while (true) {
            // If we don't have a directory open, open the next one
            if (self.dir == null) {
                if (self.path_index >= self.path.len) {
                    return null;
                }

                self.dir = std.fs.cwd().openDir(self.path[self.path_index], .{ .iterate = true }) catch {
                    self.path_index += 1;
                    continue;
                };
                self.iter = self.dir.?.iterate();
                self.path_index += 1;
            }

            // Get next entry
            if (self.iter) |*iter| {
                if (try iter.next()) |entry| {
                    const info = try self.processEntry(entry);
                    if (info) |i| {
                        return i;
                    }
                    continue;
                }
            }

            // No more entries in this directory
            if (self.dir) |*d| {
                d.close();
                self.dir = null;
                self.iter = null;
            }
        }
    }

    fn processEntry(self: *Self, entry: std.fs.Dir.Entry) !?ModuleInfo {
        const name = entry.name;

        // Skip hidden files and __pycache__
        if (name.len == 0 or name[0] == '.') return null;
        if (std.mem.eql(u8, name, "__pycache__")) return null;

        var module_name: []const u8 = undefined;
        var ispkg = false;

        if (entry.kind == .directory) {
            // Check if it's a package (has __init__.py)
            var dir_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const dir_path = std.fmt.bufPrint(&dir_path_buf, "{s}/{s}/__init__.py", .{ self.path[self.path_index - 1], name }) catch return null;

            const is_package = blk: {
                std.fs.cwd().access(dir_path, .{}) catch break :blk false;
                break :blk true;
            };

            if (!is_package) return null;

            module_name = name;
            ispkg = true;
        } else {
            // Check if it's a .py file
            if (!std.mem.endsWith(u8, name, ".py")) return null;
            if (std.mem.eql(u8, name, "__init__.py")) return null;

            // Strip .py extension
            module_name = name[0 .. name.len - 3];
            ispkg = false;
        }

        // Skip if already seen
        if (self.seen.contains(module_name)) return null;
        try self.seen.put(try self.allocator.dupe(u8, module_name), {});

        // Create full name with prefix
        var full_name: []const u8 = undefined;
        if (self.prefix.len > 0) {
            full_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.prefix, module_name });
        } else {
            full_name = try self.allocator.dupe(u8, module_name);
        }

        return ModuleInfo{
            .name = full_name,
            .ispkg = ispkg,
        };
    }
};

/// Iterate over all modules in given path(s)
pub fn iter_modules(
    allocator: std.mem.Allocator,
    path: ?[]const []const u8,
    prefix: ?[]const u8,
) ModuleIterator {
    return ModuleIterator.init(allocator, path, prefix);
}

test "ModuleIterator init" {
    const allocator = std.testing.allocator;
    var iter = ModuleIterator.init(allocator, null, null);
    defer iter.deinit();
    try std.testing.expectEqual(@as(usize, 0), iter.path_index);
}
