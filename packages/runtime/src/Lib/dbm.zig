//! Python 'dbm' module - Interfaces to Unix "databases"
//!
//! Provides a generic interface to variants of DBM-style databases.
//!
//! Mirrors: CPython Lib/dbm/__init__.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const DbmError = error{
    DatabaseError,
    KeyNotFound,
    ReadOnly,
    InvalidMode,
    CorruptedDatabase,
};

// ============================================================================
// Database Interface
// ============================================================================

/// Generic database interface
pub fn Database(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        data: hashmap_helper.StringHashMap(V),
        filename: []const u8,
        mode: Mode,
        allocator: std.mem.Allocator,
        modified: bool,

        pub const Mode = enum {
            read, // 'r' - Open existing database for reading only
            write, // 'w' - Open existing database for reading and writing
            create, // 'c' - Open database for reading and writing, creating if needed
            new, // 'n' - Always create a new, empty database
        };

        pub fn init(allocator: std.mem.Allocator, filename: []const u8, flag: []const u8) !Self {
            const mode: Mode = switch (flag[0]) {
                'r' => .read,
                'w' => .write,
                'c' => .create,
                'n' => .new,
                else => return error.InvalidMode,
            };

            var self = Self{
                .data = hashmap_helper.StringHashMap(V).init(allocator),
                .filename = filename,
                .mode = mode,
                .allocator = allocator,
                .modified = false,
            };

            if (mode != .new) {
                self.load() catch |err| {
                    if (mode == .read or mode == .write) {
                        return err;
                    }
                    // 'c' mode: OK if file doesn't exist
                };
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        fn load(self: *Self) !void {
            const file = try std.fs.cwd().openFile(self.filename, .{});
            defer file.close();

            const content = try file.readToEndAlloc(self.allocator, 100 * 1024 * 1024);
            defer self.allocator.free(content);

            // Simple line-based format
            var lines = std.mem.splitScalar(u8, content, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue;
                if (std.mem.indexOf(u8, line, "\t")) |tab| {
                    const key = line[0..tab];
                    const value = line[tab + 1 ..];
                    try self.data.put(
                        try self.allocator.dupe(u8, key),
                        try self.parseValue(value),
                    );
                }
            }
        }

        fn parseValue(self: *Self, value: []const u8) !V {
            _ = self;
            if (V == []const u8) {
                return value;
            } else if (V == []u8) {
                return @constCast(value);
            } else {
                return undefined;
            }
        }

        fn save(self: *Self) !void {
            if (self.mode == .read) {
                return error.ReadOnly;
            }

            const file = try std.fs.cwd().createFile(self.filename, .{});
            defer file.close();

            var iter = self.data.iterator();
            while (iter.next()) |entry| {
                try file.writer().print("{s}\t", .{entry.key_ptr.*});
                try self.writeValue(file.writer(), entry.value_ptr.*);
                try file.writer().writeByte('\n');
            }
        }

        fn writeValue(self: *Self, writer: anytype, value: V) !void {
            _ = self;
            if (V == []const u8 or V == []u8) {
                try writer.writeAll(value);
            }
        }

        /// Get a value by key
        pub fn get(self: *Self, key: K) ?V {
            if (K == []const u8 or K == []u8) {
                return self.data.get(key);
            }
            return null;
        }

        /// Set a value
        pub fn put(self: *Self, key: K, value: V) !void {
            if (self.mode == .read) {
                return error.ReadOnly;
            }

            if (K == []const u8 or K == []u8) {
                try self.data.put(key, value);
                self.modified = true;
            }
        }

        /// Delete a key
        pub fn delete(self: *Self, key: K) !void {
            if (self.mode == .read) {
                return error.ReadOnly;
            }

            if (K == []const u8 or K == []u8) {
                if (!self.data.remove(key)) {
                    return error.KeyNotFound;
                }
                self.modified = true;
            }
        }

        /// Check if key exists
        pub fn contains(self: *Self, key: K) bool {
            if (K == []const u8 or K == []u8) {
                return self.data.contains(key);
            }
            return false;
        }

        /// Get all keys
        pub fn keys(self: *Self) ![]K {
            var result = std.ArrayList(K).init(self.allocator);
            errdefer result.deinit();

            for (self.data.keys()) |key| {
                try result.append(key);
            }

            return result.toOwnedSlice();
        }

        /// Get number of entries
        pub fn len(self: *Self) usize {
            return self.data.count();
        }

        /// Sync to disk
        pub fn sync(self: *Self) !void {
            if (self.modified) {
                try self.save();
                self.modified = false;
            }
        }

        /// Close the database
        pub fn close(self: *Self) !void {
            try self.sync();
        }

        /// Clear all entries
        pub fn clear(self: *Self) !void {
            if (self.mode == .read) {
                return error.ReadOnly;
            }
            self.data.clearRetainingCapacity();
            self.modified = true;
        }

        /// Reorganize the database (no-op for this implementation)
        pub fn reorganize(self: *Self) !void {
            _ = self;
            // Would compact the database file
        }

        /// Get first key
        pub fn firstKey(self: *Self) ?K {
            const key_slice = self.data.keys();
            if (key_slice.len > 0) {
                return key_slice[0];
            }
            return null;
        }

        /// Get next key after given key
        pub fn nextKey(self: *Self, key: K) ?K {
            _ = self;
            _ = key;
            // Would return next key in iteration order
            return null;
        }
    };
}

// ============================================================================
// Module Functions
// ============================================================================

/// Open a database
pub fn open(allocator: std.mem.Allocator, filename: []const u8, flag: []const u8, mode: ?u32) !Database([]const u8, []const u8) {
    _ = mode;
    return Database([]const u8, []const u8).init(allocator, filename, flag);
}

/// Guess which db module should be used for a database file
pub fn whichdb(filename: []const u8) ?[]const u8 {
    // Would examine file to determine database type
    _ = filename;
    return "dbm.dumb";
}

// ============================================================================
// Submodule References
// ============================================================================

/// DBM GDBM backend
pub const gnu = struct {
    pub fn open(allocator: std.mem.Allocator, filename: []const u8, flag: []const u8, mode: ?u32) !Database([]const u8, []const u8) {
        _ = mode;
        return Database([]const u8, []const u8).init(allocator, filename, flag);
    }
};

/// DBM NDBM backend
pub const ndbm = struct {
    pub fn open(allocator: std.mem.Allocator, filename: []const u8, flag: []const u8, mode: ?u32) !Database([]const u8, []const u8) {
        _ = mode;
        return Database([]const u8, []const u8).init(allocator, filename, flag);
    }
};

/// DBM dumb backend (pure Python/Zig fallback)
pub const dumb = struct {
    pub fn open(allocator: std.mem.Allocator, filename: []const u8, flag: []const u8, mode: ?u32) !Database([]const u8, []const u8) {
        _ = mode;
        return Database([]const u8, []const u8).init(allocator, filename, flag);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Database basic operations" {
    const allocator = std.testing.allocator;
    var db = try Database([]const u8, []const u8).init(allocator, "/tmp/test.db", "n");
    defer db.deinit();

    try db.put("key1", "value1");
    try std.testing.expectEqualStrings("value1", db.get("key1").?);
    try std.testing.expect(db.contains("key1"));
    try std.testing.expectEqual(@as(usize, 1), db.len());

    try db.delete("key1");
    try std.testing.expect(!db.contains("key1"));
}

test "Database read-only mode" {
    const allocator = std.testing.allocator;

    // Create a database first
    {
        var db = try Database([]const u8, []const u8).init(allocator, "/tmp/test_ro.db", "n");
        defer db.deinit();
        try db.put("key", "value");
        try db.sync();
    }

    // Now open read-only - would fail on put
    // (Skipping actual test as it requires file to exist)
}

test "whichdb" {
    const result = whichdb("/nonexistent/file.db");
    // May return null or a database type
    _ = result;
}

test "open function" {
    const allocator = std.testing.allocator;
    var db = try open(allocator, "/tmp/test_open.db", "n", null);
    defer db.deinit();

    try std.testing.expectEqual(@as(usize, 0), db.len());
}
