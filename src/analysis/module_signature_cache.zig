//! Module signature cache for type analysis - speeds up batch compilation
//! Inspired by lanceql's column caching - caches analyzed ModuleInfo across test runs
//!
//! Key Insight: When running 389 tests, many import the same modules (e.g., unittest).
//! Instead of re-analyzing the same module AST 389 times, cache the ModuleInfo with
//! content-hash validation.
//!
//! Expected impact: 40-60% faster batch tests by eliminating redundant module analysis.
//!
//! Usage:
//!   var cache = ModuleSignatureCache.init(allocator);
//!   defer cache.deinit();
//!
//!   // Check cache before analyzing
//!   if (try cache.lookup(source, "mymodule")) |cached_info| {
//!       return cached_info; // Hit!
//!   }
//!
//!   // Analyze and cache
//!   const info = try analyzeModule(...);
//!   try cache.store(source, "mymodule", info);

const std = @import("std");
const module_traits = @import("analysis.module_traits");
const hashmap_helper = @import("utils.hashmap_helper");

/// Cached module signature with content validation
pub const ModuleSignatureCache = struct {
    allocator: std.mem.Allocator,
    entries: hashmap_helper.StringHashMap(CacheEntry),
    hits: usize,
    misses: usize,

    const MAX_CACHE_SIZE = 500; // Cache up to 500 modules

    const CacheEntry = struct {
        module_info: module_traits.ModuleInfo,
        content_hash: u64, // Fast hash of source (Wyhash)
        access_count: usize,
    };

    pub fn init(allocator: std.mem.Allocator) ModuleSignatureCache {
        return .{
            .allocator = allocator,
            .entries = hashmap_helper.StringHashMap(CacheEntry).init(allocator),
            .hits = 0,
            .misses = 0,
        };
    }

    /// Lookup cached ModuleInfo for a module
    /// Returns cached info if source unchanged, otherwise null
    pub fn lookup(self: *ModuleSignatureCache, source: []const u8, module_name: []const u8) ?module_traits.ModuleInfo {
        const current_hash = self.hashSource(source);

        if (self.entries.getPtr(module_name)) |entry| {
            // Verify content unchanged
            if (entry.content_hash == current_hash) {
                entry.access_count += 1;
                self.hits += 1;
                return entry.module_info;
            } else {
                // Content changed, invalidate
                _ = self.entries.swapRemove(module_name);
            }
        }

        self.misses += 1;
        return null;
    }

    /// Store analyzed ModuleInfo in cache
    pub fn store(self: *ModuleSignatureCache, source: []const u8, module_name: []const u8, info: module_traits.ModuleInfo) !void {
        const hash = self.hashSource(source);

        // Check cache size limit
        if (self.entries.count() >= MAX_CACHE_SIZE) {
            self.evictLRU();
        }

        // Store in cache (module_name is key)
        const name_copy = try self.allocator.dupe(u8, module_name);
        try self.entries.put(name_copy, .{
            .module_info = info,
            .content_hash = hash,
            .access_count = 1,
        });
    }

    /// Hash source using Wyhash (fast, non-cryptographic)
    fn hashSource(self: *ModuleSignatureCache, source: []const u8) u64 {
        _ = self;
        // Use std.hash.Wyhash for fast hashing
        return std.hash.Wyhash.hash(0, source);
    }

    /// Evict least-recently-used entries (simplified LRU)
    fn evictLRU(self: *ModuleSignatureCache) void {
        // Remove 10% of cache (simplest strategy)
        const to_remove = self.entries.count() / 10;
        var removed: usize = 0;

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (removed >= to_remove) break;
            if (entry.value_ptr.access_count < 2) {
                const key_to_remove = entry.key_ptr.*;
                _ = self.entries.swapRemove(key_to_remove);
                self.allocator.free(key_to_remove);
                removed += 1;
            }
        }
    }

    /// Get cache statistics
    pub fn getStats(self: *const ModuleSignatureCache) struct { hits: usize, misses: usize, hit_rate: f64 } {
        const total = self.hits + self.misses;
        const hit_rate = if (total > 0) @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total)) else 0.0;
        return .{
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
        };
    }

    pub fn deinit(self: *ModuleSignatureCache) void {
        // Free module info data
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            // Free the key (module name)
            self.allocator.free(entry.key_ptr.*);

            // Free ModuleInfo internals
            var info = entry.value_ptr.module_info;
            info.functions.deinit();
            info.constants.deinit();

            // Free class metadata
            var class_iter = info.classes.iterator();
            while (class_iter.next()) |class_entry| {
                class_entry.value_ptr.methods.deinit();
                class_entry.value_ptr.class_vars.deinit();
            }
            info.classes.deinit();
        }
        self.entries.deinit();
    }
};
