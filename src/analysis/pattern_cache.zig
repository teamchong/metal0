//! Pattern cache for type inference - speeds up repetitive code patterns
//! Inspired by zell's ngram cache - caches common AST patterns → inferred types
//!
//! Usage:
//!   var cache = PatternCache.init(allocator);
//!   defer cache.deinit();
//!
//!   const context = try cache.captureContext(node, scope);
//!   if (cache.lookup(context)) |cached_type| {
//!       return cached_type; // Hit!
//!   }
//!   const inferred = expensiveInference(node);
//!   cache.record(context, inferred);

const std = @import("std");
const ast = @import("analysis.ast");
const native_types = @import("native_types.zig");
const NativeType = native_types.NativeType;
const wyhash = @import("../utils/wyhash.zig");

/// Pattern cache for type inference results
pub const PatternCache = struct {
    allocator: std.mem.Allocator,
    patterns: std.AutoHashMap(u64, CachedInference),
    hits: usize,
    misses: usize,

    const MAX_CACHE_SIZE = 10000; // Cache up to 10K patterns

    const CachedInference = struct {
        result_type: NativeType,
        confidence: TypeConfidence,
        access_count: usize,
    };

    const TypeConfidence = enum {
        certain,
        uncertain,
    };

    pub fn init(allocator: std.mem.Allocator) PatternCache {
        return .{
            .allocator = allocator,
            .patterns = std.AutoHashMap(u64, CachedInference).init(allocator),
            .hits = 0,
            .misses = 0,
        };
    }

    /// Capture context for a node (node type + surrounding scope)
    pub fn captureContext(self: *PatternCache, node: ast.Node, scope_vars: []const []const u8) ![]const u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        const writer = buf.writer();

        // Capture node type
        try writer.print("{s}|", .{@tagName(node)});

        // Capture surrounding variable types (for context)
        for (scope_vars) |var_name| {
            try writer.print("{s},", .{var_name});
        }

        return try buf.toOwnedSlice();
    }

    /// Lookup cached inference for a context
    pub fn lookup(self: *PatternCache, context: []const u8) ?NativeType {
        const hash = self.hashContext(context);

        if (self.patterns.getPtr(hash)) |entry| {
            entry.access_count += 1;
            self.hits += 1;
            return entry.result_type;
        }

        self.misses += 1;
        return null;
    }

    /// Record a pattern for future lookups
    pub fn record(self: *PatternCache, context: []const u8, result_type: NativeType, confidence: TypeConfidence) void {
        const hash = self.hashContext(context);

        self.patterns.put(hash, .{
            .result_type = result_type,
            .confidence = confidence,
            .access_count = 1,
        }) catch {
            // Cache full, evict LRU if needed
            if (self.patterns.count() >= MAX_CACHE_SIZE) {
                self.evictLRU();
                _ = self.patterns.put(hash, .{
                    .result_type = result_type,
                    .confidence = confidence,
                    .access_count = 1,
                }) catch {};
            }
        };
    }

    /// Hash context string using Wyhash (fast)
    fn hashContext(self: *PatternCache, context: []const u8) u64 {
        _ = self;
        return wyhash.WyhashStateless.hash(0, context);
    }

    /// Evict least-recently-used entries (simplified LRU)
    fn evictLRU(self: *PatternCache) void {
        // Remove 10% of cache (simplest strategy)
        const to_remove = self.patterns.count() / 10;
        var removed: usize = 0;

        var iter = self.patterns.iterator();
        while (iter.next()) |entry| {
            if (removed >= to_remove) break;
            if (entry.value_ptr.access_count < 2) {
                _ = self.patterns.remove(entry.key_ptr.*);
                removed += 1;
            }
        }
    }

    /// Get cache statistics
    pub fn getStats(self: *const PatternCache) struct { hits: usize, misses: usize, hit_rate: f64 } {
        const total = self.hits + self.misses;
        const hit_rate = if (total > 0) @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total)) else 0.0;
        return .{
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
        };
    }

    pub fn deinit(self: *PatternCache) void {
        self.patterns.deinit();
    }
};
