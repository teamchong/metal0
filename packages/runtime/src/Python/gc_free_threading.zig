/// gc_free_threading - Free-Threaded GC
/// Mirrors cpython/Python/gc_free_threading.c
///
/// Cyclic garbage collector for free-threaded (no GIL) Python builds.
/// Uses mark-alive algorithm with biased reference counting.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// GC Configuration
// ============================================================================

/// GC configuration options
pub const GCConfig = struct {
    /// Enable mark-alive pass
    mark_alive_enabled: bool = true,
    /// Enable prefetch instructions
    prefetch_enabled: bool = true,
    /// Include extra roots in mark-alive
    extra_roots: bool = true,
    /// Include Python stacks as roots
    stack_roots: bool = true,
    /// Threshold for generation 0
    threshold_0: u32 = 2000,
    /// Threshold for generation 1
    threshold_1: u32 = 10,
    /// Threshold for generation 2
    threshold_2: u32 = 10,
};

/// Global GC configuration
pub var config: GCConfig = .{};

// ============================================================================
// Object Header for GC
// ============================================================================

/// GC header flags
pub const GCFlags = packed struct {
    /// Object is tracked by GC
    tracked: bool = false,
    /// Object is reachable (mark phase)
    reachable: bool = false,
    /// Object has finalizer
    has_finalizer: bool = false,
    /// Object is in finalize list
    in_finalize: bool = false,
    /// Object's refcount is biased
    biased: bool = false,
    /// Reserved
    _reserved: u3 = 0,
};

/// GC object header (for free-threaded builds)
pub const GCHeader = struct {
    /// GC flags
    flags: GCFlags = .{},
    /// Generation (0, 1, or 2)
    generation: u8 = 0,
    /// Local reference count (biased)
    local_refcount: i32 = 0,
    /// Shared reference count
    shared_refcount: std.atomic.Value(i32) = std.atomic.Value(i32).init(0),
    /// Next object in GC list
    gc_next: ?*GCHeader = null,
    /// Previous object in GC list
    gc_prev: ?*GCHeader = null,
};

// ============================================================================
// Generation Lists
// ============================================================================

/// GC generation
pub const Generation = struct {
    /// Head of object list
    head: ?*GCHeader = null,
    /// Tail of object list
    tail: ?*GCHeader = null,
    /// Number of objects
    count: u64 = 0,
    /// Collection threshold
    threshold: u32,
    /// Number of collections
    collections: u64 = 0,
    /// Objects collected
    collected: u64 = 0,
    /// Uncollectable objects
    uncollectable: u64 = 0,

    /// Add object to generation
    pub fn addObject(self: *Generation, obj: *GCHeader) void {
        obj.gc_next = self.head;
        obj.gc_prev = null;
        if (self.head) |head| {
            head.gc_prev = obj;
        } else {
            self.tail = obj;
        }
        self.head = obj;
        self.count += 1;
    }

    /// Remove object from generation
    pub fn removeObject(self: *Generation, obj: *GCHeader) void {
        if (obj.gc_prev) |prev| {
            prev.gc_next = obj.gc_next;
        } else {
            self.head = obj.gc_next;
        }
        if (obj.gc_next) |next| {
            next.gc_prev = obj.gc_prev;
        } else {
            self.tail = obj.gc_prev;
        }
        obj.gc_next = null;
        obj.gc_prev = null;
        self.count -= 1;
    }

    /// Clear all objects
    pub fn clear(self: *Generation) void {
        self.head = null;
        self.tail = null;
        self.count = 0;
    }
};

// ============================================================================
// Free-Threaded GC State
// ============================================================================

/// GC runtime state for free-threaded build
pub const GCState = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Young generation (0)
    generation_0: Generation,
    /// Middle generation (1)
    generation_1: Generation,
    /// Old generation (2)
    generation_2: Generation,
    /// Pending finalizers
    finalizers: ?*GCHeader = null,
    /// GC is enabled
    enabled: bool = true,
    /// Currently collecting
    collecting: bool = false,
    /// Number of allocations since last collection
    alloc_count: u64 = 0,
    /// Lock for thread safety
    lock: std.Thread.Mutex = .{},

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .generation_0 = .{ .threshold = config.threshold_0 },
            .generation_1 = .{ .threshold = config.threshold_1 },
            .generation_2 = .{ .threshold = config.threshold_2 },
        };
    }

    /// Track a new object
    pub fn trackObject(self: *Self, obj: *GCHeader) void {
        self.lock.lock();
        defer self.lock.unlock();

        obj.flags.tracked = true;
        obj.generation = 0;
        self.generation_0.addObject(obj);
        self.alloc_count += 1;
    }

    /// Untrack an object
    pub fn untrackObject(self: *Self, obj: *GCHeader) void {
        if (!obj.flags.tracked) return;

        self.lock.lock();
        defer self.lock.unlock();

        const gen = self.getGeneration(obj.generation);
        gen.removeObject(obj);
        obj.flags.tracked = false;
    }

    /// Get generation by index
    fn getGeneration(self: *Self, index: u8) *Generation {
        return switch (index) {
            0 => &self.generation_0,
            1 => &self.generation_1,
            else => &self.generation_2,
        };
    }

    /// Check if collection is needed
    pub fn shouldCollect(self: *Self) bool {
        return self.enabled and self.alloc_count >= self.generation_0.threshold;
    }

    /// Run garbage collection
    pub fn collect(self: *Self, generation: u8) CollectResult {
        if (!self.enabled or self.collecting) {
            return .{ .collected = 0, .uncollectable = 0 };
        }

        self.lock.lock();
        defer self.lock.unlock();

        self.collecting = true;
        defer self.collecting = false;

        // Mark phase
        var collected: u64 = 0;
        var uncollectable: u64 = 0;

        // Mark all reachable objects
        if (config.mark_alive_enabled) {
            self.markAlive(generation);
        }

        // Sweep phase - collect unreachable objects
        const result = self.sweep(generation);
        collected = result.collected;
        uncollectable = result.uncollectable;

        // Update statistics
        const gen = self.getGeneration(generation);
        gen.collections += 1;
        gen.collected += collected;
        gen.uncollectable += uncollectable;

        // Reset allocation count
        if (generation == 0) {
            self.alloc_count = 0;
        }

        // Promote survivors to next generation
        if (generation < 2) {
            self.promoteGeneration(generation);
        }

        return .{ .collected = collected, .uncollectable = uncollectable };
    }

    /// Mark alive objects
    fn markAlive(self: *Self, generation: u8) void {
        // Reset reachable flags
        var gen_idx: u8 = 0;
        while (gen_idx <= generation) : (gen_idx += 1) {
            const gen = self.getGeneration(gen_idx);
            var obj = gen.head;
            while (obj) |o| {
                o.flags.reachable = false;
                obj = o.gc_next;
            }
        }

        // Mark from roots (simplified - in real impl, traverse all roots)
        // This would include module dicts, interned strings, etc.
    }

    /// Sweep unreachable objects
    fn sweep(self: *Self, generation: u8) CollectResult {
        var collected: u64 = 0;
        var uncollectable: u64 = 0;

        var gen_idx: u8 = 0;
        while (gen_idx <= generation) : (gen_idx += 1) {
            const gen = self.getGeneration(gen_idx);
            var obj = gen.head;
            while (obj) |o| {
                const next = o.gc_next;
                if (!o.flags.reachable) {
                    // Check if object has finalizer
                    if (o.flags.has_finalizer) {
                        // Move to finalizer list
                        gen.removeObject(o);
                        o.gc_next = self.finalizers;
                        self.finalizers = o;
                        o.flags.in_finalize = true;
                        uncollectable += 1;
                    } else {
                        // Object can be collected
                        collected += 1;
                    }
                }
                obj = next;
            }
        }

        return .{ .collected = collected, .uncollectable = uncollectable };
    }

    /// Promote objects to next generation
    fn promoteGeneration(self: *Self, generation: u8) void {
        const from_gen = self.getGeneration(generation);
        const to_gen = self.getGeneration(generation + 1);

        // Move all surviving objects to next generation
        var obj = from_gen.head;
        while (obj) |o| {
            const next = o.gc_next;
            if (o.flags.reachable) {
                from_gen.removeObject(o);
                to_gen.addObject(o);
                o.generation = generation + 1;
            }
            obj = next;
        }
    }

    /// Get GC statistics
    pub fn getStats(self: *Self) GCStats {
        self.lock.lock();
        defer self.lock.unlock();

        return GCStats{
            .collections_0 = self.generation_0.collections,
            .collections_1 = self.generation_1.collections,
            .collections_2 = self.generation_2.collections,
            .collected_0 = self.generation_0.collected,
            .collected_1 = self.generation_1.collected,
            .collected_2 = self.generation_2.collected,
            .uncollectable = self.generation_0.uncollectable +
                self.generation_1.uncollectable +
                self.generation_2.uncollectable,
        };
    }
};

/// Collection result
pub const CollectResult = struct {
    collected: u64,
    uncollectable: u64,
};

/// GC statistics
pub const GCStats = struct {
    collections_0: u64,
    collections_1: u64,
    collections_2: u64,
    collected_0: u64,
    collected_1: u64,
    collected_2: u64,
    uncollectable: u64,
};

// ============================================================================
// Biased Reference Counting
// ============================================================================

/// Increment local refcount (thread that owns the object)
pub fn increfLocal(header: *GCHeader) void {
    header.local_refcount += 1;
}

/// Decrement local refcount
pub fn decrefLocal(header: *GCHeader) bool {
    header.local_refcount -= 1;
    return header.local_refcount == 0 and header.shared_refcount.load(.acquire) == 0;
}

/// Increment shared refcount (other threads)
pub fn increfShared(header: *GCHeader) void {
    _ = header.shared_refcount.fetchAdd(1, .acq_rel);
}

/// Decrement shared refcount
pub fn decrefShared(header: *GCHeader) bool {
    const prev = header.shared_refcount.fetchSub(1, .acq_rel);
    return prev == 1 and header.local_refcount == 0;
}

/// Merge biased refcount (transfer shared to local)
pub fn mergeRefcount(header: *GCHeader) void {
    const shared = header.shared_refcount.swap(0, .acq_rel);
    header.local_refcount += shared;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;
var gc_state: ?*GCState = null;

/// Initialize the gc_free_threading module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global GC state
pub fn getGCState() ?*GCState {
    return gc_state;
}

/// Set global GC state
pub fn setGCState(state: *GCState) void {
    gc_state = state;
}

/// Reset module state
pub fn reset() void {
    gc_state = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "gc header flags" {
    var header = GCHeader{};
    try std.testing.expect(!header.flags.tracked);

    header.flags.tracked = true;
    try std.testing.expect(header.flags.tracked);
}

test "generation add/remove" {
    var gen = Generation{ .threshold = 100 };
    var header1 = GCHeader{};
    var header2 = GCHeader{};

    gen.addObject(&header1);
    try std.testing.expectEqual(@as(u64, 1), gen.count);

    gen.addObject(&header2);
    try std.testing.expectEqual(@as(u64, 2), gen.count);

    gen.removeObject(&header1);
    try std.testing.expectEqual(@as(u64, 1), gen.count);
}

test "biased refcount" {
    var header = GCHeader{};

    increfLocal(&header);
    try std.testing.expectEqual(@as(i32, 1), header.local_refcount);

    increfShared(&header);
    try std.testing.expectEqual(@as(i32, 1), header.shared_refcount.load(.acquire));

    mergeRefcount(&header);
    try std.testing.expectEqual(@as(i32, 2), header.local_refcount);
    try std.testing.expectEqual(@as(i32, 0), header.shared_refcount.load(.acquire));
}

test "gc state" {
    const allocator = std.testing.allocator;

    var state = GCState.init(allocator);
    try std.testing.expect(state.enabled);
    try std.testing.expect(!state.collecting);

    var header = GCHeader{};
    state.trackObject(&header);
    try std.testing.expect(header.flags.tracked);
    try std.testing.expectEqual(@as(u8, 0), header.generation);

    state.untrackObject(&header);
    try std.testing.expect(!header.flags.tracked);
}
