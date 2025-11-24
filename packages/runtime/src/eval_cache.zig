/// LRU Cache for eval() bytecode - with memory limits and eviction
/// Comptime target selection: WASM vs Native
const std = @import("std");
const builtin = @import("builtin");
const ast_executor = @import("ast_executor.zig");
const bytecode = @import("bytecode.zig");
const PyObject = @import("runtime.zig").PyObject;
const hashmap_helper = @import("../../src/utils/hashmap_helper.zig");

/// Compile Python source via PyAOT subprocess (for dynamic eval)
/// Spawns: pyaot --emit-bytecode <source>
/// Returns parsed BytecodeProgram from subprocess stdout
pub fn compileViaSubprocess(allocator: std.mem.Allocator, source: []const u8) !bytecode.BytecodeProgram {
    // Build argv: ["pyaot", "--emit-bytecode", source]
    const argv = [_][]const u8{ "pyaot", "--emit-bytecode", source };

    // Spawn subprocess
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stdout (bytecode binary)
    const stdout = child.stdout orelse return error.NoStdout;
    const bytecode_data = try stdout.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(bytecode_data);

    // Wait for child
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.SubprocessFailed,
        else => return error.SubprocessFailed,
    }

    // Parse bytecode
    return bytecode.BytecodeProgram.deserialize(allocator, bytecode_data);
}

/// LRU cache configuration
pub const CacheConfig = struct {
    max_entries: usize = 1024,
    max_memory_bytes: usize = 10 * 1024 * 1024, // 10MB
};

/// LRU cache entry with access tracking
const CacheEntry = struct {
    program: bytecode.BytecodeProgram,
    source_key: []const u8, // owned copy of source
    memory_size: usize, // estimated memory usage
    prev: ?*CacheEntry = null, // doubly-linked list for LRU
    next: ?*CacheEntry = null,
};

/// LRU Cache for bytecode programs
pub const LruCache = struct {
    allocator: std.mem.Allocator,
    map: hashmap_helper.StringHashMap(*CacheEntry),
    head: ?*CacheEntry = null, // most recently used
    tail: ?*CacheEntry = null, // least recently used
    config: CacheConfig,
    current_entries: usize = 0,
    current_memory: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: CacheConfig) LruCache {
        return .{
            .allocator = allocator,
            .map = hashmap_helper.StringHashMap(*CacheEntry).init(allocator),
            .config = config,
        };
    }

    pub fn deinit(self: *LruCache) void {
        // Free all entries
        var entry = self.head;
        while (entry) |e| {
            const next = e.next;
            e.program.deinit();
            self.allocator.free(e.source_key);
            self.allocator.destroy(e);
            entry = next;
        }
        self.map.deinit();
    }

    /// Get cached bytecode, returns null if not found
    /// Moves entry to front of LRU list on hit
    pub fn get(self: *LruCache, source: []const u8) ?*bytecode.BytecodeProgram {
        const entry = self.map.get(source) orelse return null;
        self.moveToFront(entry);
        return &entry.program;
    }

    /// Store bytecode in cache, evicting if necessary
    pub fn put(self: *LruCache, source: []const u8, program: bytecode.BytecodeProgram) !void {
        // Check if already exists
        if (self.map.get(source)) |existing| {
            existing.program.deinit();
            existing.program = program;
            self.moveToFront(existing);
            return;
        }

        // Estimate memory for this entry
        const memory_size = estimateMemory(source, &program);

        // Evict until we have room
        while (self.shouldEvict(memory_size)) {
            self.evictLru() catch break;
        }

        // Create new entry
        const entry = try self.allocator.create(CacheEntry);
        entry.* = .{
            .program = program,
            .source_key = try self.allocator.dupe(u8, source),
            .memory_size = memory_size,
        };

        // Add to map and LRU list
        try self.map.put(entry.source_key, entry);
        self.addToFront(entry);
        self.current_entries += 1;
        self.current_memory += memory_size;
    }

    /// Check if eviction needed
    fn shouldEvict(self: *LruCache, new_size: usize) bool {
        return self.current_entries >= self.config.max_entries or
            self.current_memory + new_size > self.config.max_memory_bytes;
    }

    /// Evict least recently used entry
    fn evictLru(self: *LruCache) !void {
        const lru = self.tail orelse return error.EmptyCache;
        self.removeEntry(lru);
    }

    /// Remove entry from cache
    fn removeEntry(self: *LruCache, entry: *CacheEntry) void {
        // Remove from linked list
        if (entry.prev) |p| p.next = entry.next else self.head = entry.next;
        if (entry.next) |n| n.prev = entry.prev else self.tail = entry.prev;

        // Remove from map
        _ = self.map.remove(entry.source_key);

        // Update stats
        self.current_entries -= 1;
        self.current_memory -= entry.memory_size;

        // Free memory
        entry.program.deinit();
        self.allocator.free(entry.source_key);
        self.allocator.destroy(entry);
    }

    /// Move entry to front (most recently used)
    fn moveToFront(self: *LruCache, entry: *CacheEntry) void {
        if (self.head == entry) return; // already at front

        // Remove from current position
        if (entry.prev) |p| p.next = entry.next;
        if (entry.next) |n| n.prev = entry.prev;
        if (self.tail == entry) self.tail = entry.prev;

        // Add to front
        entry.prev = null;
        entry.next = self.head;
        if (self.head) |h| h.prev = entry;
        self.head = entry;
        if (self.tail == null) self.tail = entry;
    }

    /// Add new entry to front
    fn addToFront(self: *LruCache, entry: *CacheEntry) void {
        entry.prev = null;
        entry.next = self.head;
        if (self.head) |h| h.prev = entry;
        self.head = entry;
        if (self.tail == null) self.tail = entry;
    }

    /// Estimate memory usage of an entry
    fn estimateMemory(source: []const u8, program: *const bytecode.BytecodeProgram) usize {
        return @sizeOf(CacheEntry) +
            source.len +
            program.instructions.len * @sizeOf(bytecode.Instruction) +
            program.constants.len * @sizeOf(bytecode.Constant);
    }

    /// Get cache statistics
    pub fn getStats(self: *LruCache) struct { entries: usize, memory: usize, max_entries: usize, max_memory: usize } {
        return .{
            .entries = self.current_entries,
            .memory = self.current_memory,
            .max_entries = self.config.max_entries,
            .max_memory = self.config.max_memory_bytes,
        };
    }
};

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
    // Ensure cache is initialized
    if (lru_cache == null) {
        try initCache(allocator);
    }

    // Check cache first (thread-safe)
    cache_mutex.lock();
    const cached = if (lru_cache) |*cache| cache.get(source) else null;
    cache_mutex.unlock();

    if (cached) |program| {
        // Cache hit - execute bytecode
        return executeTarget(allocator, program);
    }

    // Cache miss - try local parse first, fallback to subprocess
    const program = blk: {
        // Try local hardcoded patterns first (fast path for known expressions)
        if (parseSource(source, allocator)) |ast| {
            defer allocator.destroy(ast);

            var compiler = bytecode.Compiler.init(allocator);
            defer compiler.deinit();

            break :blk try compiler.compile(ast);
        } else |err| {
            if (err == error.NotImplemented) {
                // Fallback: compile via PyAOT subprocess for full Python support
                break :blk try compileViaSubprocess(allocator, source);
            }
            return err;
        }
    };

    // Store in cache (thread-safe, LRU handles eviction)
    cache_mutex.lock();
    if (lru_cache) |*cache| {
        try cache.put(source, program);
    }
    cache_mutex.unlock();

    // Get the cached program to return (since put may have stored a copy)
    cache_mutex.lock();
    const stored = if (lru_cache) |*cache| cache.get(source) else null;
    cache_mutex.unlock();

    if (stored) |p| {
        return executeTarget(allocator, p);
    }
    return error.CacheFailed;
}

/// Comptime target selection - WASM vs Native
fn executeTarget(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    if (builtin.cpu.arch.isWasm()) {
        // WASM: Use bytecode VM (no JIT possible)
        return executeWasm(allocator, program);
    } else {
        // Native: Use bytecode VM for now
        // Future: Could JIT to machine code here
        return executeNative(allocator, program);
    }
}

/// WASM bytecode execution
fn executeWasm(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    var vm = bytecode.VM.init(allocator);
    defer vm.deinit();
    return vm.execute(program);
}

/// Native bytecode execution (same as WASM for now)
fn executeNative(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    var vm = bytecode.VM.init(allocator);
    defer vm.deinit();
    return vm.execute(program);
}

/// Parse source code to AST (MVP: hardcoded patterns)
fn parseSource(source: []const u8, allocator: std.mem.Allocator) !*ast_executor.Node {
    // For MVP: hardcoded pattern matching
    // Full implementation would use actual lexer/parser

    // Pattern: integer constant "42"
    if (std.mem.eql(u8, source, "42")) {
        const node = try allocator.create(ast_executor.Node);
        node.* = .{ .constant = .{ .value = .{ .int = 42 } } };
        return node;
    }

    // Pattern: "1 + 2"
    if (std.mem.eql(u8, source, "1 + 2")) {
        const left = try allocator.create(ast_executor.Node);
        left.* = .{ .constant = .{ .value = .{ .int = 1 } } };

        const right = try allocator.create(ast_executor.Node);
        right.* = .{ .constant = .{ .value = .{ .int = 2 } } };

        const node = try allocator.create(ast_executor.Node);
        node.* = .{
            .binop = .{
                .left = left,
                .op = .Add,
                .right = right,
            },
        };
        return node;
    }

    // Pattern: "1 + 2 * 3"
    if (std.mem.eql(u8, source, "1 + 2 * 3")) {
        const two = try allocator.create(ast_executor.Node);
        two.* = .{ .constant = .{ .value = .{ .int = 2 } } };

        const three = try allocator.create(ast_executor.Node);
        three.* = .{ .constant = .{ .value = .{ .int = 3 } } };

        const mult = try allocator.create(ast_executor.Node);
        mult.* = .{
            .binop = .{
                .left = two,
                .op = .Mult,
                .right = three,
            },
        };

        const one = try allocator.create(ast_executor.Node);
        one.* = .{ .constant = .{ .value = .{ .int = 1 } } };

        const node = try allocator.create(ast_executor.Node);
        node.* = .{
            .binop = .{
                .left = one,
                .op = .Add,
                .right = mult,
            },
        };
        return node;
    }

    return error.NotImplemented;
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
