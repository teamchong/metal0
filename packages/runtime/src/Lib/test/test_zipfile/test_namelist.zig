//! test.test_zipfile.test_namelist - ZIP namelist tests
//!
//! Tests for managing and querying the list of file names in ZIP archives,
//! including sorting, filtering, and path manipulation.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// NameList - Collection of archive file names
// ============================================================================

pub const NameList = struct {
    const Self = @This();

    allocator: mem.Allocator,
    names: std.ArrayList([]const u8),
    owned: std.ArrayList(bool),

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .names = std.ArrayList([]const u8).init(allocator),
            .owned = std.ArrayList(bool).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.names.items, 0..) |name, i| {
            if (self.owned.items[i]) {
                self.allocator.free(name);
            }
        }
        self.names.deinit();
        self.owned.deinit();
    }

    /// Add a name (copies the string)
    pub fn add(self: *Self, name: []const u8) !void {
        const copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(copy);
        try self.names.append(copy);
        try self.owned.append(true);
    }

    /// Add a name without copying (caller retains ownership)
    pub fn addBorrowed(self: *Self, name: []const u8) !void {
        try self.names.append(name);
        try self.owned.append(false);
    }

    /// Get number of names
    pub fn len(self: Self) usize {
        return self.names.items.len;
    }

    /// Check if empty
    pub fn isEmpty(self: Self) bool {
        return self.names.items.len == 0;
    }

    /// Get name at index
    pub fn get(self: Self, index: usize) ?[]const u8 {
        if (index >= self.names.items.len) return null;
        return self.names.items[index];
    }

    /// Check if name exists
    pub fn contains(self: Self, name: []const u8) bool {
        for (self.names.items) |n| {
            if (mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    /// Get all names as slice
    pub fn items(self: Self) []const []const u8 {
        return self.names.items;
    }

    /// Filter names matching a predicate
    pub fn filter(self: *Self, predicate: *const fn ([]const u8) bool) !NameList {
        var result = NameList.init(self.allocator);
        errdefer result.deinit();

        for (self.names.items) |name| {
            if (predicate(name)) {
                try result.add(name);
            }
        }

        return result;
    }

    /// Get directories only
    pub fn directories(self: *Self) !NameList {
        return self.filter(isDirectory);
    }

    /// Get files only (non-directories)
    pub fn files(self: *Self) !NameList {
        return self.filter(isFile);
    }

    /// Sort names alphabetically
    pub fn sort(self: *Self) void {
        const Context = struct {
            names: [][]const u8,
            owned: []bool,
        };

        const ctx = Context{
            .names = self.names.items,
            .owned = self.owned.items,
        };

        // Sort indices
        var indices = self.allocator.alloc(usize, self.names.items.len) catch return;
        defer self.allocator.free(indices);

        for (indices, 0..) |*idx, i| {
            idx.* = i;
        }

        std.mem.sort(usize, indices, ctx, struct {
            fn lessThan(c: Context, a: usize, b: usize) bool {
                return std.mem.order(u8, c.names[a], c.names[b]) == .lt;
            }
        }.lessThan);

        // Reorder based on sorted indices
        var new_names = self.allocator.alloc([]const u8, self.names.items.len) catch return;
        defer self.allocator.free(new_names);
        var new_owned = self.allocator.alloc(bool, self.owned.items.len) catch return;
        defer self.allocator.free(new_owned);

        for (indices, 0..) |idx, i| {
            new_names[i] = self.names.items[idx];
            new_owned[i] = self.owned.items[idx];
        }

        @memcpy(self.names.items, new_names);
        @memcpy(self.owned.items, new_owned);
    }

    /// Clear all names
    pub fn clear(self: *Self) void {
        for (self.names.items, 0..) |name, i| {
            if (self.owned.items[i]) {
                self.allocator.free(name);
            }
        }
        self.names.clearRetainingCapacity();
        self.owned.clearRetainingCapacity();
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if path represents a directory
pub fn isDirectory(path: []const u8) bool {
    return path.len > 0 and path[path.len - 1] == '/';
}

/// Check if path represents a file
pub fn isFile(path: []const u8) bool {
    return !isDirectory(path);
}

/// Get parent directory of a path
pub fn parentDir(path: []const u8) ?[]const u8 {
    // Remove trailing slash if present
    var clean_path = path;
    if (clean_path.len > 0 and clean_path[clean_path.len - 1] == '/') {
        clean_path = clean_path[0 .. clean_path.len - 1];
    }

    // Find last separator
    const last_sep = mem.lastIndexOfScalar(u8, clean_path, '/');
    if (last_sep) |pos| {
        if (pos == 0) return "/";
        return clean_path[0..pos];
    }
    return null;
}

/// Get file name from path
pub fn baseName(path: []const u8) []const u8 {
    // Remove trailing slash
    var clean_path = path;
    if (clean_path.len > 0 and clean_path[clean_path.len - 1] == '/') {
        clean_path = clean_path[0 .. clean_path.len - 1];
    }

    const last_sep = mem.lastIndexOfScalar(u8, clean_path, '/');
    if (last_sep) |pos| {
        return clean_path[pos + 1 ..];
    }
    return clean_path;
}

/// Get file extension
pub fn extension(path: []const u8) ?[]const u8 {
    const name = baseName(path);
    const dot = mem.lastIndexOfScalar(u8, name, '.');
    if (dot) |pos| {
        if (pos > 0 and pos < name.len - 1) {
            return name[pos + 1 ..];
        }
    }
    return null;
}

/// Get path depth (number of directory levels)
pub fn pathDepth(path: []const u8) usize {
    var depth: usize = 0;
    for (path) |c| {
        if (c == '/') depth += 1;
    }
    // Don't count trailing slash
    if (path.len > 0 and path[path.len - 1] == '/') {
        depth -|= 1;
    }
    return depth;
}

// ============================================================================
// NameMatcher - Pattern matching for names
// ============================================================================

pub const NameMatcher = struct {
    const Self = @This();

    patterns: std.ArrayList(Pattern),
    allocator: mem.Allocator,

    pub const Pattern = struct {
        text: []const u8,
        is_prefix: bool = false,
        is_suffix: bool = false,
        is_glob: bool = false,
    };

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .patterns = std.ArrayList(Pattern).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.patterns.deinit();
    }

    /// Add exact match pattern
    pub fn addExact(self: *Self, text: []const u8) !void {
        try self.patterns.append(.{ .text = text });
    }

    /// Add prefix match pattern
    pub fn addPrefix(self: *Self, text: []const u8) !void {
        try self.patterns.append(.{ .text = text, .is_prefix = true });
    }

    /// Add suffix match pattern
    pub fn addSuffix(self: *Self, text: []const u8) !void {
        try self.patterns.append(.{ .text = text, .is_suffix = true });
    }

    /// Check if name matches any pattern
    pub fn matches(self: Self, name: []const u8) bool {
        if (self.patterns.items.len == 0) return true;

        for (self.patterns.items) |pattern| {
            if (pattern.is_prefix) {
                if (mem.startsWith(u8, name, pattern.text)) return true;
            } else if (pattern.is_suffix) {
                if (mem.endsWith(u8, name, pattern.text)) return true;
            } else {
                if (mem.eql(u8, name, pattern.text)) return true;
            }
        }
        return false;
    }

    /// Filter a name list
    pub fn filterList(self: Self, list: *NameList) !NameList {
        var result = NameList.init(list.allocator);
        errdefer result.deinit();

        for (list.items()) |name| {
            if (self.matches(name)) {
                try result.add(name);
            }
        }

        return result;
    }
};

// ============================================================================
// NameIterator - Iterate over names
// ============================================================================

pub const NameIterator = struct {
    list: *const NameList,
    index: usize = 0,
    filter_fn: ?*const fn ([]const u8) bool = null,

    pub fn next(self: *@This()) ?[]const u8 {
        while (self.index < self.list.len()) {
            const name = self.list.get(self.index).?;
            self.index += 1;

            if (self.filter_fn) |f| {
                if (f(name)) return name;
            } else {
                return name;
            }
        }
        return null;
    }

    pub fn reset(self: *@This()) void {
        self.index = 0;
    }

    pub fn skip(self: *@This(), count: usize) void {
        self.index = @min(self.index + count, self.list.len());
    }

    pub fn remaining(self: @This()) usize {
        return self.list.len() - self.index;
    }
};

// ============================================================================
// DirectoryTree - Hierarchical view of names
// ============================================================================

pub const DirectoryTree = struct {
    const Self = @This();

    allocator: mem.Allocator,
    root_entries: std.ArrayList(Entry),

    pub const Entry = struct {
        name: []const u8,
        is_dir: bool,
        children: ?*std.ArrayList(Entry) = null,
    };

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .root_entries = std.ArrayList(Entry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.root_entries.deinit();
    }

    /// Build tree from name list
    pub fn build(self: *Self, list: *const NameList) !void {
        for (list.items()) |name| {
            try self.addPath(name);
        }
    }

    fn addPath(self: *Self, path: []const u8) !void {
        // Simple implementation - just add to root
        const is_dir = isDirectory(path);
        try self.root_entries.append(.{
            .name = path,
            .is_dir = is_dir,
        });
    }

    /// Get number of entries
    pub fn count(self: Self) usize {
        return self.root_entries.items.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "NameList init and deinit" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try testing.expect(list.isEmpty());
    try testing.expectEqual(@as(usize, 0), list.len());
}

test "NameList add and get" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("file1.txt");
    try list.add("file2.txt");

    try testing.expectEqual(@as(usize, 2), list.len());
    try testing.expectEqualStrings("file1.txt", list.get(0).?);
    try testing.expectEqualStrings("file2.txt", list.get(1).?);
    try testing.expect(list.get(2) == null);
}

test "NameList contains" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("hello.txt");
    try list.add("world.txt");

    try testing.expect(list.contains("hello.txt"));
    try testing.expect(list.contains("world.txt"));
    try testing.expect(!list.contains("missing.txt"));
}

test "NameList directories and files" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("dir1/");
    try list.add("file1.txt");
    try list.add("dir2/");
    try list.add("file2.txt");

    var dirs = try list.directories();
    defer dirs.deinit();
    try testing.expectEqual(@as(usize, 2), dirs.len());

    var files = try list.files();
    defer files.deinit();
    try testing.expectEqual(@as(usize, 2), files.len());
}

test "NameList sort" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("c.txt");
    try list.add("a.txt");
    try list.add("b.txt");

    list.sort();

    try testing.expectEqualStrings("a.txt", list.get(0).?);
    try testing.expectEqualStrings("b.txt", list.get(1).?);
    try testing.expectEqualStrings("c.txt", list.get(2).?);
}

test "NameList clear" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("file.txt");
    try testing.expectEqual(@as(usize, 1), list.len());

    list.clear();
    try testing.expect(list.isEmpty());
}

test "isDirectory" {
    try testing.expect(isDirectory("mydir/"));
    try testing.expect(!isDirectory("file.txt"));
    try testing.expect(!isDirectory(""));
}

test "isFile" {
    try testing.expect(isFile("file.txt"));
    try testing.expect(!isFile("mydir/"));
}

test "parentDir" {
    try testing.expectEqualStrings("a/b", parentDir("a/b/c.txt").?);
    try testing.expectEqualStrings("/", parentDir("/root").?);
    try testing.expect(parentDir("file.txt") == null);
    try testing.expectEqualStrings("a/b", parentDir("a/b/c/").?);
}

test "baseName" {
    try testing.expectEqualStrings("file.txt", baseName("a/b/file.txt"));
    try testing.expectEqualStrings("dir", baseName("a/dir/"));
    try testing.expectEqualStrings("file.txt", baseName("file.txt"));
}

test "extension" {
    try testing.expectEqualStrings("txt", extension("file.txt").?);
    try testing.expectEqualStrings("gz", extension("file.tar.gz").?);
    try testing.expect(extension("file") == null);
    try testing.expect(extension(".hidden") == null);
}

test "pathDepth" {
    try testing.expectEqual(@as(usize, 0), pathDepth("file.txt"));
    try testing.expectEqual(@as(usize, 1), pathDepth("a/file.txt"));
    try testing.expectEqual(@as(usize, 2), pathDepth("a/b/file.txt"));
    try testing.expectEqual(@as(usize, 2), pathDepth("a/b/c/"));
}

test "NameMatcher exact" {
    var matcher = NameMatcher.init(testing.allocator);
    defer matcher.deinit();

    try matcher.addExact("target.txt");
    try testing.expect(matcher.matches("target.txt"));
    try testing.expect(!matcher.matches("other.txt"));
}

test "NameMatcher prefix" {
    var matcher = NameMatcher.init(testing.allocator);
    defer matcher.deinit();

    try matcher.addPrefix("test_");
    try testing.expect(matcher.matches("test_file.txt"));
    try testing.expect(!matcher.matches("file_test.txt"));
}

test "NameMatcher suffix" {
    var matcher = NameMatcher.init(testing.allocator);
    defer matcher.deinit();

    try matcher.addSuffix(".txt");
    try testing.expect(matcher.matches("file.txt"));
    try testing.expect(!matcher.matches("file.jpg"));
}

test "NameMatcher empty matches all" {
    var matcher = NameMatcher.init(testing.allocator);
    defer matcher.deinit();

    try testing.expect(matcher.matches("anything"));
}

test "NameIterator" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("a.txt");
    try list.add("b.txt");
    try list.add("c.txt");

    var iter = NameIterator{ .list = &list };
    try testing.expectEqualStrings("a.txt", iter.next().?);
    try testing.expectEqualStrings("b.txt", iter.next().?);
    try testing.expectEqualStrings("c.txt", iter.next().?);
    try testing.expect(iter.next() == null);
}

test "NameIterator with filter" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("dir/");
    try list.add("file.txt");
    try list.add("another/");

    var iter = NameIterator{ .list = &list, .filter_fn = isFile };
    try testing.expectEqualStrings("file.txt", iter.next().?);
    try testing.expect(iter.next() == null);
}

test "NameIterator reset" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("file.txt");

    var iter = NameIterator{ .list = &list };
    _ = iter.next();
    try testing.expect(iter.next() == null);

    iter.reset();
    try testing.expectEqualStrings("file.txt", iter.next().?);
}

test "NameIterator skip" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("a.txt");
    try list.add("b.txt");
    try list.add("c.txt");

    var iter = NameIterator{ .list = &list };
    iter.skip(2);
    try testing.expectEqualStrings("c.txt", iter.next().?);
}

test "DirectoryTree init" {
    var tree = DirectoryTree.init(testing.allocator);
    defer tree.deinit();

    try testing.expectEqual(@as(usize, 0), tree.count());
}

test "DirectoryTree build" {
    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.add("file1.txt");
    try list.add("dir/");
    try list.add("dir/file2.txt");

    var tree = DirectoryTree.init(testing.allocator);
    defer tree.deinit();

    try tree.build(&list);
    try testing.expectEqual(@as(usize, 3), tree.count());
}

test "NameList addBorrowed" {
    const borrowed = "borrowed_string";

    var list = NameList.init(testing.allocator);
    defer list.deinit();

    try list.addBorrowed(borrowed);
    try testing.expectEqual(@as(usize, 1), list.len());
    try testing.expectEqualStrings(borrowed, list.get(0).?);
}
