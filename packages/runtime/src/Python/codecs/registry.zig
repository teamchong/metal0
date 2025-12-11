/// codecs/registry - Codec Registry
/// Manages codec search functions and caching

const std = @import("std");
const types = @import("types.zig");
const normalization = @import("normalization.zig");

const CodecInfo = types.CodecInfo;
const CodecSearchFn = types.CodecSearchFn;

// ============================================================================
// Codec Registry State
// ============================================================================

/// Maximum number of search functions
const MAX_SEARCH_FUNCTIONS = 32;

/// Maximum cache entries
const MAX_CACHE_ENTRIES = 256;

/// Codec registry state
pub const CodecRegistry = struct {
    /// Search functions (in order of registration)
    search_path: [MAX_SEARCH_FUNCTIONS]?CodecSearchFn = [_]?CodecSearchFn{null} ** MAX_SEARCH_FUNCTIONS,
    search_path_len: usize = 0,

    /// Codec cache (normalized encoding -> codec info)
    cache_keys: [MAX_CACHE_ENTRIES][]const u8 = undefined,
    cache_values: [MAX_CACHE_ENTRIES]?*const CodecInfo = [_]?*const CodecInfo{null} ** MAX_CACHE_ENTRIES,
    cache_len: usize = 0,

    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},

    /// Whether the registry is initialized
    initialized: bool = false,

    /// Initialize the registry
    pub fn init(self: *CodecRegistry) void {
        self.search_path_len = 0;
        self.cache_len = 0;
        self.initialized = true;
    }

    /// Register a codec search function
    pub fn register(self: *CodecRegistry, search_fn: CodecSearchFn) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.search_path_len >= MAX_SEARCH_FUNCTIONS) {
            return error.TooManySearchFunctions;
        }

        self.search_path[self.search_path_len] = search_fn;
        self.search_path_len += 1;
    }

    /// Unregister a codec search function
    pub fn unregister(self: *CodecRegistry, search_fn: CodecSearchFn) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.search_path_len) {
            if (self.search_path[i] == search_fn) {
                // Shift remaining entries
                var j = i;
                while (j + 1 < self.search_path_len) : (j += 1) {
                    self.search_path[j] = self.search_path[j + 1];
                }
                self.search_path_len -= 1;
                // Clear cache
                self.clearCache();
                return;
            }
            i += 1;
        }
    }

    /// Clear the codec cache
    pub fn clearCache(self: *CodecRegistry) void {
        self.cache_len = 0;
    }

    /// Lookup codec in cache
    fn lookupCache(self: *CodecRegistry, normalized: []const u8) ?*const CodecInfo {
        for (0..self.cache_len) |i| {
            if (std.mem.eql(u8, self.cache_keys[i], normalized)) {
                return self.cache_values[i];
            }
        }
        return null;
    }

    /// Add codec to cache
    fn addToCache(self: *CodecRegistry, normalized: []const u8, codec: *const CodecInfo) void {
        if (self.cache_len >= MAX_CACHE_ENTRIES) {
            // Simple eviction: clear entire cache
            self.clearCache();
        }
        self.cache_keys[self.cache_len] = normalized;
        self.cache_values[self.cache_len] = codec;
        self.cache_len += 1;
    }

    /// Lookup a codec by encoding name
    pub fn lookup(self: *CodecRegistry, encoding: []const u8) !*const CodecInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Normalize encoding name
        var normalized_buf: [256]u8 = undefined;
        const normalized = normalization.normalizeEncoding(&normalized_buf, encoding);

        // Check cache first
        if (self.lookupCache(normalized)) |codec| {
            return codec;
        }

        // Search through registered functions
        if (self.search_path_len == 0) {
            return error.NoCodecSearchFunctions;
        }

        for (0..self.search_path_len) |i| {
            if (self.search_path[i]) |search_fn| {
                if (search_fn(normalized)) |codec| {
                    self.addToCache(normalized, codec);
                    return codec;
                }
            }
        }

        return error.UnknownEncoding;
    }
};

/// Global codec registry
var global_registry: CodecRegistry = .{};

// ============================================================================
// Public API
// ============================================================================

/// Register a codec search function
/// Mirrors: PyCodec_Register
pub fn register(search_fn: CodecSearchFn) !void {
    return global_registry.register(search_fn);
}

/// Unregister a codec search function
/// Mirrors: PyCodec_Unregister
pub fn unregister(search_fn: CodecSearchFn) void {
    global_registry.unregister(search_fn);
}

/// Lookup a codec by name
/// Mirrors: _PyCodec_Lookup, PyCodec_Lookup
pub fn lookup(encoding: []const u8) !*const CodecInfo {
    if (!global_registry.initialized) {
        global_registry.init();
    }
    return global_registry.lookup(encoding);
}

/// Initialize the registry
pub fn init() void {
    global_registry.init();
}

/// Finalize the registry
pub fn fini() void {
    global_registry.clearCache();
}
