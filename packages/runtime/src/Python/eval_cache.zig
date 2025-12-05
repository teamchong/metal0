/// LRU Cache for eval() bytecode - with memory limits and eviction
/// Comptime target selection: WASM vs Native
const std = @import("std");
const builtin = @import("builtin");
const ast_executor = @import("ast_executor.zig");
const bytecode = @import("compile.zig");
const PyObject = @import("../runtime.zig").PyObject;
const hashmap_helper = @import("hashmap_helper");

/// Compile Python source via metal0 subprocess (for dynamic eval)
/// Spawns: metal0 --emit-bytecode <source>
/// Returns parsed BytecodeProgram from subprocess stdout
pub fn compileViaSubprocess(allocator: std.mem.Allocator, source: []const u8) !bytecode.BytecodeProgram {
    // Build argv: ["metal0", "--emit-bytecode", source]
    const argv = [_][]const u8{ "metal0", "--emit-bytecode", source };

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

        // Remove from map (Zig 0.15: swapRemove replaces remove)
        _ = self.map.swapRemove(entry.source_key);

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
    // FAST PATH: Try to parse as simple literal first (no bytecode needed)
    // This handles: numeric literals (with underscores), bools, None, string literals
    if (tryParseLiteral(allocator, source)) |obj| {
        return obj;
    }

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

/// Parse source code directly to bytecode using runtime expression parser
/// Supports all Python expression syntax at runtime (truly dynamic eval)
fn parseSourceToBytecode(source: []const u8, allocator: std.mem.Allocator) !bytecode.BytecodeProgram {
    const expr_parser = @import("expr_parser.zig");
    return expr_parser.parseExpression(allocator, source);
}

/// Fast path: Try to parse source as a simple Python literal
/// Returns PyObject if successful, null if not a simple literal
/// Handles: numeric literals (with underscores), bools, None, string literals
fn tryParseLiteral(allocator: std.mem.Allocator, source: []const u8) ?*PyObject {
    const PyInt = @import("../Objects/intobject.zig").PyInt;
    const PyFloat = @import("../Objects/floatobject.zig").PyFloat;
    const PyBool = @import("../Objects/boolobject.zig").PyBool;
    const PyString = @import("../Objects/stringlib/core.zig").PyString;
    const runtime = @import("../runtime.zig");

    // Trim whitespace
    const trimmed = std.mem.trim(u8, source, " \t\n\r");
    if (trimmed.len == 0) return null;

    // Try bool literals
    if (std.mem.eql(u8, trimmed, "True")) {
        return PyBool.create(allocator, true) catch return null;
    }
    if (std.mem.eql(u8, trimmed, "False")) {
        return PyBool.create(allocator, false) catch return null;
    }

    // Try None (Py_None is a singleton, no allocation needed)
    if (std.mem.eql(u8, trimmed, "None")) {
        return runtime.Py_None;
    }

    // Try float literal (handles underscores, inf, nan)
    if (tryParseFloatLiteral(trimmed)) |f| {
        return PyFloat.create(allocator, f) catch return null;
    }

    // Try int literal (handles underscores)
    if (tryParseIntLiteral(trimmed)) |i| {
        return PyInt.create(allocator, i) catch return null;
    }

    // Try string literal ('...' or "...")
    if (tryParseStringLiteral(allocator, trimmed)) |s| {
        return PyString.create(allocator, s) catch return null;
    }

    return null;
}

/// Validate underscore placement in Python numeric literal
/// Returns false if:
/// - starts with underscore
/// - ends with underscore
/// - has consecutive underscores
/// - underscore adjacent to . or e/E without digit in between
fn validateUnderscores(s: []const u8) bool {
    if (s.len == 0) return true;
    // Can't start with underscore (after optional sign)
    var start: usize = 0;
    if (s[0] == '-' or s[0] == '+') start = 1;
    if (start < s.len and s[start] == '_') return false;
    // Can't end with underscore
    if (s[s.len - 1] == '_') return false;
    // Check for consecutive underscores and underscore adjacent to special chars
    var prev: u8 = 0;
    for (s) |c| {
        if (c == '_') {
            // Consecutive underscores
            if (prev == '_') return false;
            // Underscore after . or e/E
            if (prev == '.' or prev == 'e' or prev == 'E') return false;
        } else if (c == '.' or c == 'e' or c == 'E') {
            // These chars after underscore is invalid
            if (prev == '_') return false;
        }
        prev = c;
    }
    return true;
}

/// Parse float literal with underscore support
/// "1_000.0" → 1000.0, "inf" → inf, "nan" → nan
fn tryParseFloatLiteral(s: []const u8) ?f64 {
    // Handle special values first
    if (std.mem.eql(u8, s, "inf") or std.mem.eql(u8, s, "Infinity")) {
        return std.math.inf(f64);
    }
    if (std.mem.eql(u8, s, "-inf") or std.mem.eql(u8, s, "-Infinity")) {
        return -std.math.inf(f64);
    }
    if (std.mem.eql(u8, s, "nan") or std.mem.eql(u8, s, "NaN")) {
        return std.math.nan(f64);
    }

    // Must contain a decimal point, 'e', or 'E' to be a float
    var has_float_char = false;
    for (s) |c| {
        if (c == '.' or c == 'e' or c == 'E') {
            has_float_char = true;
            break;
        }
    }
    if (!has_float_char) return null;

    // Validate underscore placement (Python rules)
    if (!validateUnderscores(s)) return null;

    // Strip underscores and parse
    var buf: [256]u8 = undefined;
    var len: usize = 0;
    for (s) |c| {
        if (c != '_') {
            if (len >= buf.len) return null;
            buf[len] = c;
            len += 1;
        }
    }
    if (len == 0) return null;

    return std.fmt.parseFloat(f64, buf[0..len]) catch null;
}

/// Validate underscore placement in int literal (after base prefix)
fn validateIntUnderscores(s: []const u8) bool {
    if (s.len == 0) return true;
    // Can't start with underscore
    if (s[0] == '_') return false;
    // Can't end with underscore
    if (s[s.len - 1] == '_') return false;
    // Check for consecutive underscores
    var prev: u8 = 0;
    for (s) |c| {
        if (c == '_' and prev == '_') return false;
        prev = c;
    }
    return true;
}

/// Parse int literal with underscore support
/// "1_000" → 1000, "0x1_000" → 4096, "0b1010" → 10
fn tryParseIntLiteral(s: []const u8) ?i64 {
    if (s.len == 0) return null;

    // Determine base and skip prefix
    var base: u8 = 10;
    var start: usize = 0;
    var negative = false;

    if (s[0] == '-') {
        negative = true;
        start = 1;
    } else if (s[0] == '+') {
        start = 1;
    }

    if (start < s.len and s[start] == '0' and start + 1 < s.len) {
        const next = s[start + 1];
        if (next == 'x' or next == 'X') {
            base = 16;
            start += 2;
        } else if (next == 'o' or next == 'O') {
            base = 8;
            start += 2;
        } else if (next == 'b' or next == 'B') {
            base = 2;
            start += 2;
        }
    }

    // Validate underscore placement in the number part
    const num_part = s[start..];
    if (!validateIntUnderscores(num_part)) return null;

    // Strip underscores and parse
    var buf: [256]u8 = undefined;
    var len: usize = 0;
    for (num_part) |c| {
        if (c != '_') {
            if (len >= buf.len) return null;
            buf[len] = c;
            len += 1;
        }
    }
    if (len == 0) return null;

    const value = std.fmt.parseInt(i64, buf[0..len], base) catch return null;
    return if (negative) -value else value;
}

/// Parse string literal ('...' or "...")
fn tryParseStringLiteral(allocator: std.mem.Allocator, s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;

    const quote = s[0];
    if (quote != '\'' and quote != '"') return null;
    if (s[s.len - 1] != quote) return null;

    // Extract content between quotes (simple case, no escape handling for now)
    const content = s[1 .. s.len - 1];
    return allocator.dupe(u8, content) catch null;
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
