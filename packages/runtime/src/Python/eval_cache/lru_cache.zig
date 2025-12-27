/// LRU Cache for eval() bytecode - with memory limits and eviction
const std = @import("std");
const bytecode = @import("../compile.zig");
const hashmap_helper = @import("utils.hashmap_helper");

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
    refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(0), // prevents eviction while in use
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
    /// WARNING: Use acquire() instead if you need the pointer after releasing the mutex!
    pub fn get(self: *LruCache, source: []const u8) ?*bytecode.BytecodeProgram {
        const entry = self.map.get(source) orelse return null;
        self.moveToFront(entry);
        return &entry.program;
    }

    /// Acquire cached bytecode with refcount increment - prevents eviction
    /// MUST call release() when done to allow eviction
    /// Use this when the pointer will be used after releasing the cache mutex
    pub fn acquire(self: *LruCache, source: []const u8) ?*bytecode.BytecodeProgram {
        const entry = self.map.get(source) orelse return null;
        _ = entry.refcount.fetchAdd(1, .monotonic);
        self.moveToFront(entry);
        return &entry.program;
    }

    /// Release a previously acquired program - decrements refcount
    /// Once refcount reaches 0, the entry can be evicted
    pub fn release(self: *LruCache, program: *bytecode.BytecodeProgram) void {
        _ = self; // Unused, but required for method syntax
        // Get the CacheEntry from the program pointer using @fieldParentPtr
        const entry: *CacheEntry = @fieldParentPtr("program", program);
        const prev = entry.refcount.fetchSub(1, .monotonic);
        // Safety check: refcount should never go below 0
        if (prev == 0) {
            @panic("LruCache: release() called more times than acquire()");
        }
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

    /// Evict least recently used entry that is not in use
    /// Skips entries with refcount > 0 (currently being executed)
    fn evictLru(self: *LruCache) !void {
        // Start from tail (least recently used) and find first evictable entry
        var candidate = self.tail;
        while (candidate) |entry| {
            if (entry.refcount.load(.monotonic) == 0) {
                // Entry is not in use, safe to evict
                self.removeEntry(entry);
                return;
            }
            // Entry is in use, try the next (more recently used) one
            candidate = entry.prev;
        }
        // All entries are in use - cannot evict
        return error.AllEntriesInUse;
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
