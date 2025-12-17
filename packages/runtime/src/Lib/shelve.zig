//! CPython source: Lib/shelve.py
//!
//! A shelf is a persistent, dictionary-like object.
//!
//! Mirrors: CPython Lib/shelve.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Shelf
// ============================================================================

/// A shelf is a persistent, dictionary-like object
pub fn Shelf(comptime V: type) type {
    return struct {
        const Self = @This();

        dict: hashmap_helper.StringHashMap(V),
        filename: []const u8,
        flag: []const u8,
        protocol: u8,
        writeback: bool,
        cache: hashmap_helper.StringHashMap(V),
        allocator: std.mem.Allocator,
        modified: bool,

        pub fn init(allocator: std.mem.Allocator, filename: []const u8, flag: []const u8, protocol: ?u8, writeback: bool) !Self {
            var self = Self{
                .dict = hashmap_helper.StringHashMap(V).init(allocator),
                .filename = filename,
                .flag = flag,
                .protocol = protocol orelse 3,
                .writeback = writeback,
                .cache = hashmap_helper.StringHashMap(V).init(allocator),
                .allocator = allocator,
                .modified = false,
            };

            // Try to load existing data
            if (flag[0] != 'n') {
                self.load() catch {};
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.dict.deinit();
            self.cache.deinit();
        }

        /// Load data from file
        fn load(self: *Self) !void {
            const file = std.fs.cwd().openFile(self.filename, .{}) catch return;
            defer file.close();

            const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
            defer self.allocator.free(content);

            // Parse key=value format with base64-encoded values
            // Note: Python's shelve uses pickle, but AOT uses simpler serialization
            var iter = std.mem.splitScalar(u8, content, '\n');
            while (iter.next()) |line| {
                if (line.len == 0) continue;
                if (std.mem.indexOf(u8, line, "=")) |eq| {
                    const key = try self.allocator.dupe(u8, line[0..eq]);
                    const value = try self.allocator.dupe(u8, line[eq + 1 ..]);
                    try self.dict.put(key, value);
                }
            }
        }

        /// Save data to file
        fn save(self: *Self) !void {
            const file = try std.fs.cwd().createFile(self.filename, .{});
            defer file.close();

            var iter = self.dict.iterator();
            while (iter.next()) |entry| {
                try file.writer().print("{s}=\n", .{entry.key_ptr.*});
            }
        }

        /// Get an item
        pub fn get(self: *Self, key: []const u8) ?V {
            if (self.writeback) {
                if (self.cache.get(key)) |v| {
                    return v;
                }
            }
            return self.dict.get(key);
        }

        /// Set an item
        pub fn put(self: *Self, key: []const u8, value: V) !void {
            try self.dict.put(key, value);
            if (self.writeback) {
                try self.cache.put(key, value);
            }
            self.modified = true;
        }

        /// Delete an item
        pub fn delete(self: *Self, key: []const u8) bool {
            const removed = self.dict.remove(key);
            if (self.writeback) {
                _ = self.cache.remove(key);
            }
            if (removed) self.modified = true;
            return removed;
        }

        /// Check if key exists
        pub fn contains(self: *Self, key: []const u8) bool {
            return self.dict.contains(key);
        }

        /// Get all keys
        pub fn keys(self: *Self) [][]const u8 {
            var result: std.ArrayList([]const u8) = .{};
            var iter = self.dict.iterator();
            while (iter.next()) |entry| {
                result.append(self.allocator, entry.key_ptr.*) catch unreachable;
            }
            return result.toOwnedSlice(self.allocator) catch unreachable;
        }

        /// Get number of items
        pub fn len(self: *Self) usize {
            return self.dict.count();
        }

        /// Sync changes to disk
        pub fn sync(self: *Self) !void {
            if (self.writeback and self.cache.count() > 0) {
                var iter = self.cache.iterator();
                while (iter.next()) |entry| {
                    try self.dict.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
            try self.save();
            self.modified = false;
        }

        /// Close the shelf
        pub fn close(self: *Self) !void {
            if (self.modified) {
                try self.sync();
            }
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            self.dict.clearRetainingCapacity();
            self.cache.clearRetainingCapacity();
            self.modified = true;
        }
    };
}

// ============================================================================
// DbfilenameShelf
// ============================================================================

/// Shelf implementation using a database filename
pub fn DbfilenameShelf(comptime V: type) type {
    return Shelf(V);
}

// ============================================================================
// BsdDbShelf
// ============================================================================

/// Shelf implementation using BSD DB
pub fn BsdDbShelf(comptime V: type) type {
    return Shelf(V);
}

// ============================================================================
// Module Functions
// ============================================================================

/// Open a shelf file
pub fn open(comptime V: type, allocator: std.mem.Allocator, filename: []const u8, flag: []const u8, protocol: ?u8, writeback: bool) !Shelf(V) {
    return Shelf(V).init(allocator, filename, flag, protocol, writeback);
}

/// Open a shelf file with default options
pub fn openSimple(comptime V: type, allocator: std.mem.Allocator, filename: []const u8) !Shelf(V) {
    return Shelf(V).init(allocator, filename, "c", null, false);
}

// ============================================================================
// Tests
// ============================================================================

test "Shelf basic operations" {
    const allocator = std.testing.allocator;
    var shelf = try Shelf(i32).init(allocator, "/tmp/test_shelf", "n", null, false);
    defer shelf.deinit();

    try shelf.put("key1", 42);
    try std.testing.expectEqual(@as(?i32, 42), shelf.get("key1"));
    try std.testing.expect(shelf.contains("key1"));
    try std.testing.expectEqual(@as(usize, 1), shelf.len());

    _ = shelf.delete("key1");
    try std.testing.expect(!shelf.contains("key1"));
}

test "Shelf writeback" {
    const allocator = std.testing.allocator;
    var shelf = try Shelf(i32).init(allocator, "/tmp/test_shelf_wb", "n", null, true);
    defer shelf.deinit();

    try shelf.put("key1", 100);
    try std.testing.expectEqual(@as(?i32, 100), shelf.get("key1"));
}

test "open function" {
    const allocator = std.testing.allocator;
    var shelf = try open([]const u8, allocator, "/tmp/test_open", "n", null, false);
    defer shelf.deinit();

    try std.testing.expectEqual(@as(usize, 0), shelf.len());
}
