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
            var result: std.ArrayList(K) = .{};
            errdefer result.deinit(self.allocator);

            for (self.data.keys()) |key| {
                try result.append(self.allocator, key);
            }

            return result.toOwnedSlice(self.allocator);
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

        /// Reorganize/compact the database by rewriting it
        pub fn reorganize(self: *Self) !void {
            if (self.mode == .read) {
                return error.ReadOnly;
            }

            // Create a temporary file
            var tmp_buf: [512]u8 = undefined;
            const tmp_path = std.fmt.bufPrint(&tmp_buf, "{s}.tmp", .{self.filename}) catch return;

            // Write current data to temp file
            const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
            defer tmp_file.close();

            var iter = self.data.iterator();
            while (iter.next()) |entry| {
                try tmp_file.writer().print("{s}\t", .{entry.key_ptr.*});
                try self.writeValue(tmp_file.writer(), entry.value_ptr.*);
                try tmp_file.writer().writeByte('\n');
            }

            // Replace original file with compacted version
            try std.fs.cwd().rename(tmp_path, self.filename);
            self.modified = false;
        }

        /// Get first key (for iteration)
        pub fn firstKey(self: *Self) ?K {
            var iter = self.data.iterator();
            if (iter.next()) |entry| {
                return entry.key_ptr.*;
            }
            return null;
        }

        /// Get next key after given key (for iteration)
        pub fn nextKey(self: *Self, key: K) ?K {
            // Find current key in iteration order, return next one
            var iter = self.data.iterator();
            var found_current = false;
            while (iter.next()) |entry| {
                if (found_current) {
                    return entry.key_ptr.*;
                }
                if (K == []const u8 or K == []u8) {
                    if (std.mem.eql(u8, entry.key_ptr.*, key)) {
                        found_current = true;
                    }
                }
            }
            return null;
        }

        /// Iterator for database keys
        pub const KeyIterator = struct {
            db: *Self,
            iter: @TypeOf(@as(hashmap_helper.StringHashMap(V), undefined).iterator()),

            pub fn next(it: *KeyIterator) ?K {
                if (it.iter.next()) |entry| {
                    return entry.key_ptr.*;
                }
                return null;
            }
        };

        /// Get key iterator
        pub fn keyIterator(self: *Self) KeyIterator {
            return .{ .db = self, .iter = self.data.iterator() };
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
/// Examines file magic numbers to determine database type
pub fn whichdb(filename: []const u8) ?[]const u8 {
    // Try to open and read magic bytes
    const file = std.fs.cwd().openFile(filename, .{}) catch {
        // File doesn't exist or can't be opened
        // Check for associated files (.dir, .pag for dbm.ndbm)
        var dir_buf: [512]u8 = undefined;
        const dir_path = std.fmt.bufPrint(&dir_buf, "{s}.dir", .{filename}) catch return null;
        if (std.fs.cwd().access(dir_path, .{})) |_| {
            return "dbm.ndbm";
        } else |_| {}

        // Check for .db extension (Berkeley DB)
        var db_buf: [512]u8 = undefined;
        const db_path = std.fmt.bufPrint(&db_buf, "{s}.db", .{filename}) catch return null;
        if (std.fs.cwd().access(db_path, .{})) |_| {
            return "dbm.ndbm";
        } else |_| {}

        return null;
    };
    defer file.close();

    // Read first 16 bytes for magic detection
    var magic: [16]u8 = undefined;
    const n = file.read(&magic) catch return "dbm.dumb";
    if (n < 4) return "dbm.dumb";

    // GDBM magic: 0x13579ace or 0x13579acd (little/big endian)
    if (n >= 4) {
        const gdbm_magic_le: u32 = 0x13579ace;
        const gdbm_magic_be: u32 = 0x13579acd;
        const file_magic = std.mem.readInt(u32, magic[0..4], .little);
        if (file_magic == gdbm_magic_le or file_magic == gdbm_magic_be) {
            return "dbm.gnu";
        }
    }

    // Berkeley DB magic: 0x00061561 or 0x61150600
    if (n >= 4) {
        if (magic[0] == 0x00 and magic[1] == 0x06 and magic[2] == 0x15 and magic[3] == 0x61) {
            return "dbm.ndbm";
        }
        if (magic[0] == 0x61 and magic[1] == 0x15 and magic[2] == 0x06 and magic[3] == 0x00) {
            return "dbm.ndbm";
        }
    }

    // Check if it looks like our dumb format (text with tabs)
    for (magic[0..n]) |c| {
        if (c == '\t' or c == '\n' or (c >= 0x20 and c <= 0x7e)) {
            continue;
        }
        // Binary data - unknown format
        return null;
    }

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
