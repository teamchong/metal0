/// brc - Biased Reference Counting
/// Mirrors cpython/Python/brc.c
///
/// This module implements biased reference counting for free-threading:
/// - Per-thread local reference counts (fast, no atomics)
/// - Shared reference counts (atomic, for cross-thread refs)
/// - Deferred reference counting for containers
/// - Integration with garbage collection

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Immortal reference count marker
pub const IMMORTAL_REFCNT: u64 = std.math.maxInt(u64);

/// Threshold for merging local to shared
pub const MERGE_THRESHOLD: u32 = 1024;

/// Flag indicating the object has deferred references
pub const DEFERRED_FLAG: u64 = 1 << 63;

// ============================================================================
// Reference Count Structure
// ============================================================================

/// Biased reference count for an object
pub const BiasedRefcount = struct {
    /// Local reference count (owner thread, no atomics needed)
    local: u32 = 1,
    /// Shared reference count (atomic for cross-thread)
    shared: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    /// Owner thread ID
    owner_tid: u64 = 0,
    /// Flags (deferred, immortal, etc.)
    flags: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    const Self = @This();

    /// Initialize with owning thread
    pub fn init() Self {
        return .{
            .local = 1,
            .shared = std.atomic.Value(u32).init(0),
            .owner_tid = getThreadId(),
            .flags = std.atomic.Value(u64).init(0),
        };
    }

    /// Get total reference count
    pub fn getRefcount(self: *const Self) u64 {
        const local: u64 = self.local;
        const shared: u64 = self.shared.load(.acquire);
        return local + shared;
    }

    /// Check if immortal
    pub fn isImmortal(self: *const Self) bool {
        return self.flags.load(.acquire) == IMMORTAL_REFCNT;
    }

    /// Make immortal
    pub fn makeImmortal(self: *Self) void {
        self.flags.store(IMMORTAL_REFCNT, .release);
    }

    /// Increment reference (fast path for owner thread)
    pub fn incref(self: *Self) void {
        if (self.isImmortal()) return;

        if (getThreadId() == self.owner_tid) {
            // Fast path: owner thread
            self.local += 1;
        } else {
            // Slow path: shared increment
            _ = self.shared.fetchAdd(1, .acq_rel);
        }
    }

    /// Decrement reference (returns true if object should be deallocated)
    pub fn decref(self: *Self) bool {
        if (self.isImmortal()) return false;

        if (getThreadId() == self.owner_tid) {
            // Fast path: owner thread
            if (self.local > 0) {
                self.local -= 1;
            }
            // Check if object can be freed
            if (self.local == 0 and self.shared.load(.acquire) == 0) {
                return true;
            }
        } else {
            // Slow path: shared decrement
            const old = self.shared.fetchSub(1, .acq_rel);
            if (old == 1 and self.local == 0) {
                return true;
            }
        }
        return false;
    }

    /// Transfer ownership to another thread
    pub fn transferOwnership(self: *Self, new_tid: u64) void {
        if (self.isImmortal()) return;

        // Merge local to shared before transfer
        if (self.local > 0) {
            _ = self.shared.fetchAdd(self.local, .release);
            self.local = 0;
        }
        self.owner_tid = new_tid;
    }

    /// Merge local counts to shared (for GC or ownership transfer)
    pub fn mergeToShared(self: *Self) void {
        if (self.isImmortal()) return;
        if (self.local > 0) {
            _ = self.shared.fetchAdd(self.local, .release);
            self.local = 0;
        }
    }

    /// Check if object is referenced only locally
    pub fn isLocalOnly(self: *const Self) bool {
        return self.shared.load(.acquire) == 0;
    }

    /// Set deferred flag
    pub fn setDeferred(self: *Self) void {
        _ = self.flags.fetchOr(DEFERRED_FLAG, .release);
    }

    /// Check if deferred
    pub fn isDeferred(self: *const Self) bool {
        return (self.flags.load(.acquire) & DEFERRED_FLAG) != 0;
    }
};

// ============================================================================
// Object Header (for objects using BRC)
// ============================================================================

/// Object header with biased reference counting
pub const BRCObjectHeader = struct {
    /// Reference count
    refcount: BiasedRefcount,
    /// Type pointer (opaque)
    type_ptr: ?*anyopaque = null,
    /// GC tracking (for cyclic garbage collection)
    gc_next: ?*BRCObjectHeader = null,
    gc_prev: ?*BRCObjectHeader = null,

    const Self = @This();

    /// Initialize a new object
    pub fn init() Self {
        return .{
            .refcount = BiasedRefcount.init(),
        };
    }

    /// Increment reference
    pub fn incref(self: *Self) void {
        self.refcount.incref();
    }

    /// Decrement reference
    pub fn decref(self: *Self) bool {
        return self.refcount.decref();
    }

    /// Get reference count
    pub fn getRefcount(self: *const Self) u64 {
        return self.refcount.getRefcount();
    }

    /// Make immortal (never freed)
    pub fn makeImmortal(self: *Self) void {
        self.refcount.makeImmortal();
    }

    /// Check if immortal
    pub fn isImmortal(self: *const Self) bool {
        return self.refcount.isImmortal();
    }
};

// ============================================================================
// Deferred Reference Counting
// ============================================================================

/// Queue for deferred decrefs
pub const DeferredDecrefQueue = struct {
    items: std.ArrayList(*anyopaque),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .items = std.ArrayList(*anyopaque).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }

    /// Add an object for deferred decref
    pub fn add(self: *Self, obj: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.items.append(obj);
    }

    /// Process all deferred decrefs
    pub fn process(self: *Self, decref_fn: *const fn (*anyopaque) void) void {
        self.mutex.lock();
        const items = self.items.toOwnedSlice() catch return;
        self.mutex.unlock();

        for (items) |obj| {
            decref_fn(obj);
        }
        self.items.allocator.free(items);
    }

    /// Get pending count
    pub fn pendingCount(self: *const Self) usize {
        return self.items.items.len;
    }
};

// ============================================================================
// Thread-Local State
// ============================================================================

/// Per-thread BRC state
pub const ThreadLocalBRC = struct {
    /// Thread ID
    tid: u64,
    /// Local reference count adjustments to flush
    pending_increfs: u32 = 0,
    pending_decrefs: u32 = 0,
    /// Deferred decref queue
    deferred_queue: ?*DeferredDecrefQueue = null,

    const Self = @This();

    pub fn init() Self {
        return .{
            .tid = getThreadId(),
        };
    }

    /// Flush pending operations
    pub fn flush(self: *Self) void {
        self.pending_increfs = 0;
        self.pending_decrefs = 0;
    }
};

/// Thread-local storage for BRC state
threadlocal var tls_brc: ThreadLocalBRC = ThreadLocalBRC.init();

/// Get thread-local BRC state
pub fn getThreadLocalBRC() *ThreadLocalBRC {
    return &tls_brc;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get current thread ID
fn getThreadId() u64 {
    return @intFromPtr(std.Thread.getCurrentId());
}

// ============================================================================
// Public API
// ============================================================================

/// Create a new BRC object header
pub fn brc_alloc() BRCObjectHeader {
    return BRCObjectHeader.init();
}

/// Increment reference count
pub fn brc_incref(header: *BRCObjectHeader) void {
    header.incref();
}

/// Decrement reference count, returns true if should free
pub fn brc_decref(header: *BRCObjectHeader) bool {
    return header.decref();
}

/// Make object immortal
pub fn brc_immortalize(header: *BRCObjectHeader) void {
    header.makeImmortal();
}

/// Get reference count
pub fn brc_getcount(header: *const BRCObjectHeader) u64 {
    return header.getRefcount();
}

/// Transfer ownership
pub fn brc_transfer(header: *BRCObjectHeader, new_tid: u64) void {
    header.refcount.transferOwnership(new_tid);
}

/// Merge local to shared (for GC)
pub fn brc_merge(header: *BRCObjectHeader) void {
    header.refcount.mergeToShared();
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "biased refcount basic" {
    var rc = BiasedRefcount.init();

    try std.testing.expectEqual(@as(u64, 1), rc.getRefcount());

    rc.incref();
    try std.testing.expectEqual(@as(u64, 2), rc.getRefcount());

    const should_free = rc.decref();
    try std.testing.expect(!should_free);
    try std.testing.expectEqual(@as(u64, 1), rc.getRefcount());

    const should_free2 = rc.decref();
    try std.testing.expect(should_free2);
}

test "biased refcount immortal" {
    var rc = BiasedRefcount.init();
    rc.makeImmortal();

    try std.testing.expect(rc.isImmortal());

    // Incref/decref should be no-ops
    rc.incref();
    rc.incref();
    const should_free = rc.decref();
    try std.testing.expect(!should_free);
    try std.testing.expect(rc.isImmortal());
}

test "biased refcount merge" {
    var rc = BiasedRefcount.init();
    rc.local = 5;

    try std.testing.expectEqual(@as(u64, 5), rc.getRefcount());
    try std.testing.expect(rc.isLocalOnly());

    rc.mergeToShared();

    try std.testing.expectEqual(@as(u32, 0), rc.local);
    try std.testing.expectEqual(@as(u32, 5), rc.shared.load(.acquire));
    try std.testing.expect(!rc.isLocalOnly());
}

test "object header" {
    var header = BRCObjectHeader.init();

    try std.testing.expectEqual(@as(u64, 1), header.getRefcount());

    header.incref();
    try std.testing.expectEqual(@as(u64, 2), header.getRefcount());

    _ = header.decref();
    try std.testing.expectEqual(@as(u64, 1), header.getRefcount());
}

test "object header immortal" {
    var header = BRCObjectHeader.init();
    header.makeImmortal();

    try std.testing.expect(header.isImmortal());

    header.incref();
    try std.testing.expect(!header.decref());
}

test "deferred flag" {
    var rc = BiasedRefcount.init();

    try std.testing.expect(!rc.isDeferred());

    rc.setDeferred();
    try std.testing.expect(rc.isDeferred());
}

test "transfer ownership" {
    var rc = BiasedRefcount.init();
    rc.local = 3;

    const old_tid = rc.owner_tid;
    const new_tid: u64 = 12345;

    rc.transferOwnership(new_tid);

    try std.testing.expectEqual(new_tid, rc.owner_tid);
    try std.testing.expectEqual(@as(u32, 0), rc.local);
    try std.testing.expectEqual(@as(u32, 3), rc.shared.load(.acquire));
    try std.testing.expect(old_tid != new_tid);
}

test "public api" {
    var header = brc_alloc();

    try std.testing.expectEqual(@as(u64, 1), brc_getcount(&header));

    brc_incref(&header);
    try std.testing.expectEqual(@as(u64, 2), brc_getcount(&header));

    _ = brc_decref(&header);
    try std.testing.expectEqual(@as(u64, 1), brc_getcount(&header));

    brc_merge(&header);
    try std.testing.expectEqual(@as(u64, 1), brc_getcount(&header));
}
