/// Global LRU cache - thread-safe wrapper and public API
const std = @import("std");
const bytecode = @import("../compile.zig");
const LruCache = @import("lru_cache.zig").LruCache;
const CacheConfig = @import("lru_cache.zig").CacheConfig;
const literal_parser = @import("literal_parser.zig");
const execution = @import("execution.zig");
const PyObject = @import("../../runtime.zig").PyObject;

/// Global LRU cache - thread-safe wrapper
var lru_cache: ?LruCache = null;
var cache_mutex: std.Thread.Mutex = .{};
var cache_allocator: ?std.mem.Allocator = null;

/// Initialize eval cache (call once at startup)
pub fn initCache(allocator: std.mem.Allocator) !void {
    cache_mutex.lock();
    defer cache_mutex.unlock();

    if (lru_cache == null) {
        cache_allocator = allocator;
        lru_cache = LruCache.init(allocator, .{});
    }
}

/// Cached eval() - compiles once, executes many times
pub fn evalCached(allocator: std.mem.Allocator, source: []const u8) !*PyObject {
    // FAST PATH: Try to parse as simple literal first (no bytecode needed)
    // This handles: numeric literals (with underscores), bools, None, string literals
    if (literal_parser.tryParseLiteral(allocator, source)) |obj| {
        return obj;
    }

    // Ensure cache is initialized
    if (lru_cache == null) {
        try initCache(allocator);
    }

    // Check cache first (thread-safe)
    // Use acquire() to increment refcount - prevents eviction during execution
    cache_mutex.lock();
    const cached = if (lru_cache) |*cache| cache.acquire(source) else null;
    cache_mutex.unlock();

    if (cached) |program| {
        // Cache hit - execute bytecode
        // program is safe to use because refcount prevents eviction
        defer {
            cache_mutex.lock();
            if (lru_cache) |*cache| cache.release(program);
            cache_mutex.unlock();
        }
        return execution.executeTarget(allocator, program);
    }

    // Cache miss - parse expression directly to bytecode
    // Uses lightweight runtime parser (Zig DCE removes if eval() never called)
    // NOTE: We intentionally do NOT fall back to subprocess spawning.
    // Subprocess spawning can cause infinite recursion if the subprocess
    // also calls eval(). Instead, return error for unsupported expressions.
    const program = parseSourceToBytecode(source, allocator) catch |err| {
        // No subprocess fallback - return error instead
        // Complex eval() expressions should be handled at compile time
        return err;
    };

    // Store in cache and acquire reference (thread-safe, LRU handles eviction)
    cache_mutex.lock();
    if (lru_cache) |*cache| {
        try cache.put(source, program);
    }
    // Acquire the stored program before unlocking
    const stored = if (lru_cache) |*cache| cache.acquire(source) else null;
    cache_mutex.unlock();

    if (stored) |p| {
        defer {
            cache_mutex.lock();
            if (lru_cache) |*cache| cache.release(p);
            cache_mutex.unlock();
        }
        return execution.executeTarget(allocator, p);
    }
    return error.CacheFailed;
}

/// Parse source code directly to bytecode using runtime expression parser
/// Supports all Python expression syntax at runtime (truly dynamic eval)
fn parseSourceToBytecode(source: []const u8, allocator: std.mem.Allocator) !bytecode.BytecodeProgram {
    const expr_parser = @import("../expr_parser.zig");
    return expr_parser.parseExpression(allocator, source);
}

/// Clear eval cache (for testing)
pub fn clearCache() void {
    cache_mutex.lock();
    defer cache_mutex.unlock();

    if (lru_cache) |*cache| {
        cache.deinit();
        lru_cache = null;
    }
}

/// Get cache statistics (thread-safe)
pub fn getCacheStats() ?struct { entries: usize, memory: usize, max_entries: usize, max_memory: usize } {
    cache_mutex.lock();
    defer cache_mutex.unlock();

    if (lru_cache) |*cache| {
        return cache.getStats();
    }
    return null;
}

/// Deinitialize cache completely (call at shutdown)
pub fn deinitCache() void {
    cache_mutex.lock();
    defer cache_mutex.unlock();

    if (lru_cache) |*cache| {
        cache.deinit();
        lru_cache = null;
        cache_allocator = null;
    }
}

/// Cached eval() with globals/locals scope - for eval(source, globals, locals)
pub fn evalWithScope(
    allocator: std.mem.Allocator,
    source: []const u8,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
) !*PyObject {
    // FAST PATH: Try to parse as simple literal first (no bytecode needed)
    // Literals don't need scope
    if (literal_parser.tryParseLiteral(allocator, source)) |obj| {
        return obj;
    }

    // Ensure cache is initialized
    if (lru_cache == null) {
        try initCache(allocator);
    }

    // Check cache first (thread-safe)
    // Use acquire() to increment refcount - prevents eviction during execution
    cache_mutex.lock();
    const cached = if (lru_cache) |*cache| cache.acquire(source) else null;
    cache_mutex.unlock();

    if (cached) |program| {
        // Cache hit - execute bytecode with scope
        // program is safe to use because refcount prevents eviction
        defer {
            cache_mutex.lock();
            if (lru_cache) |*cache| cache.release(program);
            cache_mutex.unlock();
        }
        return execution.executeWithScope(allocator, program, globals, locals);
    }

    // Cache miss - parse expression directly to bytecode
    const program = parseSourceToBytecode(source, allocator) catch |err| {
        return err;
    };

    // Store in cache and acquire reference (thread-safe, LRU handles eviction)
    cache_mutex.lock();
    if (lru_cache) |*cache| {
        try cache.put(source, program);
    }
    // Acquire the stored program before unlocking
    const stored = if (lru_cache) |*cache| cache.acquire(source) else null;
    cache_mutex.unlock();

    if (stored) |p| {
        defer {
            cache_mutex.lock();
            if (lru_cache) |*cache| cache.release(p);
            cache_mutex.unlock();
        }
        return execution.executeWithScope(allocator, p, globals, locals);
    }
    return error.CacheFailed;
}
