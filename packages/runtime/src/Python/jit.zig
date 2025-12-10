/// jit - JIT Compiler
/// Mirrors cpython/Python/jit.c
///
/// Just-In-Time compiler for Python bytecode (experimental in CPython 3.13+).
/// Compiles hot code paths to native machine code for improved performance.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// JIT Configuration
// ============================================================================

/// JIT compiler configuration
pub const JITConfig = struct {
    /// Enable JIT compilation
    enabled: bool = false,
    /// Hotness threshold (number of executions before compilation)
    threshold: u32 = 1000,
    /// Maximum compiled code cache size (bytes)
    max_cache_size: usize = 64 * 1024 * 1024, // 64 MB
    /// Enable debug output
    debug: bool = false,
    /// Enable optimization passes
    optimize: bool = true,
    /// Tier 1: Simple compilation
    tier1_enabled: bool = true,
    /// Tier 2: Advanced optimization
    tier2_enabled: bool = false,
    /// Tier 2 threshold
    tier2_threshold: u32 = 10000,
};

/// Default JIT configuration
pub const default_config = JITConfig{};

// ============================================================================
// JIT State
// ============================================================================

/// JIT compiler state
pub const JITState = enum {
    /// JIT not initialized
    uninitialized,
    /// JIT disabled
    disabled,
    /// JIT ready
    ready,
    /// JIT currently compiling
    compiling,
    /// JIT error state
    failed,
};

/// Compilation tier
pub const CompilationTier = enum(u8) {
    /// Interpreted (not compiled)
    interpreter = 0,
    /// Basic compilation
    tier1 = 1,
    /// Optimized compilation
    tier2 = 2,
};

// ============================================================================
// Compiled Code Entry
// ============================================================================

/// Entry for compiled code
pub const CompiledEntry = struct {
    /// Code object this was compiled from
    code_id: u64,
    /// Compiled native code
    native_code: []const u8,
    /// Entry point offset
    entry_offset: usize = 0,
    /// Compilation tier
    tier: CompilationTier = .tier1,
    /// Execution count
    exec_count: u64 = 0,
    /// Size in bytes
    size: usize,
    /// Timestamp
    compiled_at: i64,
};

// ============================================================================
// JIT Compiler
// ============================================================================

/// JIT compiler instance
pub const JITCompiler = struct {
    const Self = @This();

    /// Configuration
    config: JITConfig,
    /// Current state
    state: JITState = .uninitialized,
    /// Compiled code cache
    cache: std.AutoHashMap(u64, CompiledEntry),
    /// Total compiled code size
    total_size: usize = 0,
    /// Number of compilations
    compilation_count: u64 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: JITConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .cache = std.AutoHashMap(u64, CompiledEntry).init(allocator),
            .state = if (config.enabled) .ready else .disabled,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.native_code);
        }
        self.cache.deinit();
    }

    /// Check if code should be compiled
    pub fn shouldCompile(self: *const Self, exec_count: u32) bool {
        if (self.state != .ready) return false;
        return exec_count >= self.config.threshold;
    }

    /// Check if code should be promoted to tier 2
    pub fn shouldPromote(self: *const Self, entry: *const CompiledEntry) bool {
        if (!self.config.tier2_enabled) return false;
        if (entry.tier != .tier1) return false;
        return entry.exec_count >= self.config.tier2_threshold;
    }

    /// Compile a code object
    pub fn compile(self: *Self, code_id: u64, bytecode: []const u8) !?*CompiledEntry {
        if (self.state != .ready) return null;

        // Check cache size
        if (self.total_size >= self.config.max_cache_size) {
            self.evictOldest();
        }

        self.state = .compiling;
        defer self.state = .ready;

        // Simulate compilation (in real impl, would generate native code)
        const native_code = try self.generateNativeCode(bytecode);

        const entry = CompiledEntry{
            .code_id = code_id,
            .native_code = native_code,
            .size = native_code.len,
            .tier = .tier1,
            .compiled_at = std.time.timestamp(),
        };

        try self.cache.put(code_id, entry);
        self.total_size += native_code.len;
        self.compilation_count += 1;

        return self.cache.getPtr(code_id);
    }

    /// Generate native code from bytecode
    /// Metal0 AOT: This module exists for CPython API compatibility.
    /// In Metal0, all Python code is compiled to native code at build time
    /// by the AOT compiler, not at runtime. This function returns the
    /// bytecode unchanged as a compatibility shim.
    fn generateNativeCode(self: *Self, bytecode: []const u8) ![]const u8 {
        // AOT: Code is already native - return bytecode as-is for caching
        const native = try self.allocator.alloc(u8, bytecode.len);
        @memcpy(native, bytecode);
        return native;
    }

    /// Get compiled entry for code
    pub fn getCompiled(self: *Self, code_id: u64) ?*CompiledEntry {
        return self.cache.getPtr(code_id);
    }

    /// Invalidate compiled code
    pub fn invalidate(self: *Self, code_id: u64) void {
        if (self.cache.fetchSwapRemove(code_id)) |entry| {
            self.total_size -= entry.value.size;
            self.allocator.free(entry.value.native_code);
        }
    }

    /// Evict oldest entries to make room
    fn evictOldest(self: *Self) void {
        // Simple eviction - remove entries until under limit
        const target_size = self.config.max_cache_size * 3 / 4;
        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        var it = self.cache.iterator();
        while (it.next()) |entry| {
            if (self.total_size <= target_size) break;
            to_remove.append(entry.key_ptr.*) catch break;
            self.total_size -= entry.value_ptr.size;
        }

        for (to_remove.items) |id| {
            self.invalidate(id);
        }
    }

    /// Get statistics
    pub fn getStats(self: *const Self) JITStats {
        return JITStats{
            .enabled = self.config.enabled,
            .state = self.state,
            .cache_entries = self.cache.count(),
            .total_size = self.total_size,
            .compilation_count = self.compilation_count,
        };
    }
};

/// JIT statistics
pub const JITStats = struct {
    enabled: bool,
    state: JITState,
    cache_entries: usize,
    total_size: usize,
    compilation_count: u64,
};

// ============================================================================
// Execution Counter
// ============================================================================

/// Per-code execution counter for hotness tracking
pub const ExecutionCounter = struct {
    const Self = @This();

    /// Execution counts by code ID
    counts: std.AutoHashMap(u64, u32),
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .counts = std.AutoHashMap(u64, u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.counts.deinit();
    }

    /// Increment execution count
    pub fn increment(self: *Self, code_id: u64) u32 {
        const result = self.counts.getOrPut(code_id) catch return 0;
        if (!result.found_existing) {
            result.value_ptr.* = 0;
        }
        result.value_ptr.* += 1;
        return result.value_ptr.*;
    }

    /// Get count
    pub fn getCount(self: *const Self, code_id: u64) u32 {
        return self.counts.get(code_id) orelse 0;
    }

    /// Reset count
    pub fn resetCount(self: *Self, code_id: u64) void {
        _ = self.counts.remove(code_id);
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_jit: ?JITCompiler = null;
var global_counters: ?ExecutionCounter = null;

/// Initialize the JIT module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global JIT compiler
pub fn getJIT(allocator: Allocator) *JITCompiler {
    if (global_jit == null) {
        global_jit = JITCompiler.init(allocator, default_config);
    }
    return &global_jit.?;
}

/// Get execution counters
pub fn getCounters(allocator: Allocator) *ExecutionCounter {
    if (global_counters == null) {
        global_counters = ExecutionCounter.init(allocator);
    }
    return &global_counters.?;
}

/// Reset module state
pub fn reset() void {
    if (global_jit) |*jit| {
        jit.deinit();
    }
    if (global_counters) |*counters| {
        counters.deinit();
    }
    global_jit = null;
    global_counters = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "jit config defaults" {
    const config = JITConfig{};
    try std.testing.expect(!config.enabled);
    try std.testing.expectEqual(@as(u32, 1000), config.threshold);
}

test "jit compiler init disabled" {
    const allocator = std.testing.allocator;
    var jit = JITCompiler.init(allocator, .{ .enabled = false });
    defer jit.deinit();

    try std.testing.expectEqual(JITState.disabled, jit.state);
    try std.testing.expect(!jit.shouldCompile(2000));
}

test "jit compiler init enabled" {
    const allocator = std.testing.allocator;
    var jit = JITCompiler.init(allocator, .{ .enabled = true, .threshold = 100 });
    defer jit.deinit();

    try std.testing.expectEqual(JITState.ready, jit.state);
    try std.testing.expect(!jit.shouldCompile(50));
    try std.testing.expect(jit.shouldCompile(100));
}

test "execution counter" {
    const allocator = std.testing.allocator;
    var counters = ExecutionCounter.init(allocator);
    defer counters.deinit();

    try std.testing.expectEqual(@as(u32, 0), counters.getCount(1));

    _ = counters.increment(1);
    _ = counters.increment(1);
    _ = counters.increment(1);

    try std.testing.expectEqual(@as(u32, 3), counters.getCount(1));

    counters.resetCount(1);
    try std.testing.expectEqual(@as(u32, 0), counters.getCount(1));
}

test "jit stats" {
    const allocator = std.testing.allocator;
    var jit = JITCompiler.init(allocator, .{ .enabled = true });
    defer jit.deinit();

    const stats = jit.getStats();
    try std.testing.expect(stats.enabled);
    try std.testing.expectEqual(@as(usize, 0), stats.cache_entries);
}
