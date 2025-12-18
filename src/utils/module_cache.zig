//! Thread-safe module cache for runtime library and frequently-used modules
//! Inspired by edgebox's module_cache.zig - eliminates redundant module loads
//!
//! Usage:
//!   var cache = ModuleCache.init(allocator);
//!   defer cache.deinit();
//!
//!   const data = try cache.getOrLoad("~/.metal0/runtime/libruntime.a");
//!   // data is cached, next call returns same pointer

const std = @import("std");

/// Thread-safe cache for module data with content-hash validation
pub const ModuleCache = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    entries: std.StringHashMap(CacheEntry),

    const CacheEntry = struct {
        data: []const u8,
        content_hash: [32]u8, // SHA256 for invalidation
        ref_count: std.atomic.Value(usize),
        last_access: i64, // Timestamp for LRU
    };

    const MAX_CACHED_SIZE = 10 * 1024 * 1024; // 10MB max per entry

    pub fn init(allocator: std.mem.Allocator) ModuleCache {
        return .{
            .allocator = allocator,
            .mutex = .{},
            .entries = std.StringHashMap(CacheEntry).init(allocator),
        };
    }

    /// Get cached module data or load from disk
    /// Returns cached data if content unchanged, otherwise reloads
    pub fn getOrLoad(self: *ModuleCache, path: []const u8) ![]const u8 {
        const current_hash = try self.computeContentHash(path);

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check cache
        if (self.entries.get(path)) |*entry| {
            // Verify content unchanged
            if (std.mem.eql(u8, &entry.content_hash, &current_hash)) {
                _ = entry.ref_count.fetchAdd(1, .monotonic);
                entry.last_access = std.time.timestamp();
                return entry.data;
            } else {
                // Content changed, invalidate
                self.allocator.free(entry.data);
                _ = self.entries.remove(path);
            }
        }

        // Load from disk
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        if (stat.size > MAX_CACHED_SIZE) {
            // Too large to cache, return ephemeral data
            return try file.readToEndAlloc(self.allocator, stat.size);
        }

        const data = try file.readToEndAlloc(self.allocator, stat.size);

        // Add to cache
        const path_owned = try self.allocator.dupe(u8, path);
        try self.entries.put(path_owned, .{
            .data = data,
            .content_hash = current_hash,
            .ref_count = std.atomic.Value(usize).init(1),
            .last_access = std.time.timestamp(),
        });

        return data;
    }

    /// Release reference to cached module
    pub fn release(self: *ModuleCache, path: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.getPtr(path)) |entry| {
            _ = entry.ref_count.fetchSub(1, .monotonic);
        }
    }

    /// Compute SHA256 of first 1MB of file (fast content validation)
    fn computeContentHash(self: *ModuleCache, path: []const u8) ![32]u8 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const read_size = 1024 * 1024; // 1MB
        var buffer: [read_size]u8 = undefined;
        const bytes_read = try file.readAll(&buffer);

        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(buffer[0..bytes_read], &hash, .{});
        return hash;
    }

    /// Remove least-recently-used entries to free memory
    pub fn evictLRU(self: *ModuleCache, target_count: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.count() <= target_count) return;

        // Find LRU entries with ref_count == 0
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.ref_count.load(.monotonic) == 0) {
                to_remove.append(entry.key_ptr.*) catch break;
            }
        }

        // Sort by last_access (oldest first)
        // ... (simplified - would need proper sort)

        // Remove oldest entries
        const to_evict = @min(to_remove.items.len, self.entries.count() - target_count);
        for (to_remove.items[0..to_evict]) |path| {
            if (self.entries.fetchRemove(path)) |kv| {
                self.allocator.free(kv.value.data);
                self.allocator.free(kv.key);
            }
        }
    }

    pub fn deinit(self: *ModuleCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }
};
