/// LRU Cache for eval() bytecode - with memory limits and eviction
/// Comptime target selection: WASM vs Native
///
/// Module structure:
/// - subprocess.zig: Subprocess compilation
/// - lru_cache.zig: LRU cache implementation with eviction
/// - cache_globals.zig: Thread-safe global cache management
/// - execution.zig: Bytecode execution (WASM vs Native)
/// - literal_parser.zig: Fast path for simple literals

// Re-export public API from cache_globals
pub const initCache = @import("eval_cache/cache_globals.zig").initCache;
pub const evalCached = @import("eval_cache/cache_globals.zig").evalCached;
pub const evalWithScope = @import("eval_cache/cache_globals.zig").evalWithScope;
pub const clearCache = @import("eval_cache/cache_globals.zig").clearCache;
pub const getCacheStats = @import("eval_cache/cache_globals.zig").getCacheStats;
pub const deinitCache = @import("eval_cache/cache_globals.zig").deinitCache;

// Re-export types
pub const CacheConfig = @import("eval_cache/lru_cache.zig").CacheConfig;
pub const LruCache = @import("eval_cache/lru_cache.zig").LruCache;

// Re-export subprocess compilation (rarely used, but available)
pub const compileViaSubprocess = @import("eval_cache/subprocess.zig").compileViaSubprocess;
