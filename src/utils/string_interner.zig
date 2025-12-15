/// String interner for zero-copy identifier deduplication
/// All interned strings share the same pointer - enables O(1) equality via pointer comparison
///
/// Usage:
/// ```zig
/// var interner = StringInterner.init(allocator);
/// defer interner.deinit();
///
/// const a = try interner.intern("__init__");
/// const b = try interner.intern("__init__");
/// // a.ptr == b.ptr (same pointer, zero-copy)
/// ```
const std = @import("std");

pub const StringInterner = struct {
    /// Backing storage - keys are the canonical interned strings
    strings: std.StringHashMapUnmanaged(void),
    allocator: std.mem.Allocator,

    /// Statistics for debugging/profiling
    stats: Stats = .{},

    pub const Stats = struct {
        /// Number of unique strings interned
        unique_count: usize = 0,
        /// Number of cache hits (string already interned)
        cache_hits: usize = 0,
        /// Total bytes allocated for strings
        bytes_allocated: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) StringInterner {
        return .{
            .strings = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StringInterner) void {
        // Free all interned string keys
        var it = self.strings.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.strings.deinit(self.allocator);
    }

    /// Intern a string - returns pointer to canonical copy
    /// If already interned, returns existing pointer (zero-copy)
    /// The returned slice is valid until deinit() is called
    pub fn intern(self: *StringInterner, s: []const u8) ![]const u8 {
        // Check if already interned
        if (self.strings.getKey(s)) |existing| {
            self.stats.cache_hits += 1;
            return existing;
        }

        // Not found - allocate and store
        const owned = try self.allocator.dupe(u8, s);
        try self.strings.put(self.allocator, owned, {});

        self.stats.unique_count += 1;
        self.stats.bytes_allocated += s.len;

        return owned;
    }

    /// Check if a string is already interned without adding it
    pub fn contains(self: *const StringInterner, s: []const u8) bool {
        return self.strings.contains(s);
    }

    /// Get interned version if exists, null otherwise
    pub fn get(self: *const StringInterner, s: []const u8) ?[]const u8 {
        return self.strings.getKey(s);
    }

    /// Get current statistics
    pub fn getStats(self: *const StringInterner) Stats {
        return self.stats;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "intern returns same pointer for same string" {
    var interner = StringInterner.init(std.testing.allocator);
    defer interner.deinit();

    const a = try interner.intern("__init__");
    const b = try interner.intern("__init__");

    // Same pointer (zero-copy)
    try std.testing.expectEqual(a.ptr, b.ptr);
    try std.testing.expectEqualStrings(a, b);
}

test "intern different strings get different pointers" {
    var interner = StringInterner.init(std.testing.allocator);
    defer interner.deinit();

    const a = try interner.intern("__init__");
    const b = try interner.intern("__str__");

    // Different pointers
    try std.testing.expect(a.ptr != b.ptr);
}

test "stats tracking" {
    var interner = StringInterner.init(std.testing.allocator);
    defer interner.deinit();

    _ = try interner.intern("foo");
    _ = try interner.intern("bar");
    _ = try interner.intern("foo"); // cache hit

    const stats = interner.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.unique_count);
    try std.testing.expectEqual(@as(usize, 1), stats.cache_hits);
    try std.testing.expectEqual(@as(usize, 6), stats.bytes_allocated); // "foo" + "bar"
}

test "contains and get" {
    var interner = StringInterner.init(std.testing.allocator);
    defer interner.deinit();

    try std.testing.expect(!interner.contains("test"));
    try std.testing.expectEqual(@as(?[]const u8, null), interner.get("test"));

    _ = try interner.intern("test");

    try std.testing.expect(interner.contains("test"));
    try std.testing.expectEqualStrings("test", interner.get("test").?);
}
