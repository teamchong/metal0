/// types - GC Types and Constants
/// GC head, generation, debug flags, and callback types.

const std = @import("std");

// ============================================================================
// GC Head (object tracking header)
// ============================================================================

/// GC header placed before every tracked object
pub const GCHead = struct {
    /// Next pointer (also contains flags in low bits)
    _gc_next: usize = 0,

    /// Previous pointer (also contains ref count and flags)
    _gc_prev: usize = 0,

    const Self = @This();

    /// Flag: object is being collected
    pub const PREV_MASK_COLLECTING: usize = 1;

    /// Flag: object is finalized
    pub const PREV_MASK_FINALIZED: usize = 2;

    /// Shift for reference count in _gc_prev
    pub const PREV_SHIFT: u6 = 4;

    /// Mask for prev pointer
    pub const PREV_MASK: usize = 3;

    /// Flag: unreachable object
    pub const NEXT_MASK_UNREACHABLE: usize = 2;

    /// Flag: old space bit
    pub const NEXT_MASK_OLD_SPACE: usize = 1;

    pub fn next(self: *const Self) ?*Self {
        const ptr = self._gc_next & ~@as(usize, 3);
        if (ptr == 0) return null;
        return @ptrFromInt(ptr);
    }

    pub fn prev(self: *const Self) ?*Self {
        const ptr = self._gc_prev & ~PREV_MASK;
        if (ptr == 0) return null;
        return @ptrFromInt(ptr);
    }

    pub fn setNext(self: *Self, n: ?*Self) void {
        const flags = self._gc_next & 3;
        self._gc_next = if (n) |p| @intFromPtr(p) | flags else flags;
    }

    pub fn setPrev(self: *Self, p: ?*Self) void {
        const flags = self._gc_prev & PREV_MASK;
        self._gc_prev = if (p) |ptr| @intFromPtr(ptr) | flags else flags;
    }

    pub fn isCollecting(self: *const Self) bool {
        return (self._gc_prev & PREV_MASK_COLLECTING) != 0;
    }

    pub fn setCollecting(self: *Self, collecting: bool) void {
        if (collecting) {
            self._gc_prev |= PREV_MASK_COLLECTING;
        } else {
            self._gc_prev &= ~PREV_MASK_COLLECTING;
        }
    }

    pub fn isFinalized(self: *const Self) bool {
        return (self._gc_prev & PREV_MASK_FINALIZED) != 0;
    }

    pub fn setFinalized(self: *Self, finalized: bool) void {
        if (finalized) {
            self._gc_prev |= PREV_MASK_FINALIZED;
        } else {
            self._gc_prev &= ~PREV_MASK_FINALIZED;
        }
    }

    pub fn getRefs(self: *const Self) i64 {
        return @intCast(self._gc_prev >> PREV_SHIFT);
    }

    pub fn setRefs(self: *Self, refs: i64) void {
        self._gc_prev = (self._gc_prev & PREV_MASK) |
            (@as(usize, @intCast(refs)) << PREV_SHIFT);
    }

    pub fn decRef(self: *Self) void {
        self._gc_prev -= @as(usize, 1) << PREV_SHIFT;
    }

    pub fn getOldSpace(self: *const Self) u1 {
        return @intCast(self._gc_next & NEXT_MASK_OLD_SPACE);
    }

    pub fn setOldSpace(self: *Self, space: u1) void {
        self._gc_next = (self._gc_next & ~NEXT_MASK_OLD_SPACE) | space;
    }

    pub fn flipOldSpace(self: *Self) void {
        self._gc_next ^= NEXT_MASK_OLD_SPACE;
    }
};

// ============================================================================
// Generation Management
// ============================================================================

/// GC Generation (linked list of tracked objects)
pub const Generation = struct {
    /// List head (sentinel)
    head: GCHead = .{},

    /// Number of objects in this generation
    count: usize = 0,

    /// Threshold for collection
    threshold: usize = 700,

    /// Number of collections
    collections: usize = 0,

    /// Number of uncollectable objects
    uncollectable: usize = 0,

    const Self = @This();

    pub fn init(self: *Self) void {
        self.head._gc_next = @intFromPtr(&self.head);
        self.head._gc_prev = @intFromPtr(&self.head);
        self.count = 0;
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.head._gc_next == @intFromPtr(&self.head);
    }

    /// Add object to this generation
    pub fn add(self: *Self, gc: *GCHead) void {
        const last = self.head.prev() orelse &self.head;
        gc.setNext(&self.head);
        gc.setPrev(last);
        last.setNext(gc);
        self.head.setPrev(gc);
        self.count += 1;
    }

    /// Remove object from this generation
    pub fn remove(self: *Self, gc: *GCHead) void {
        const p = gc.prev() orelse return;
        const n = gc.next() orelse return;
        p.setNext(n);
        n.setPrev(p);
        gc.setNext(null);
        gc.setPrev(null);
        self.count -= 1;
    }

    /// Move all objects to another generation
    pub fn moveAll(self: *Self, dest: *Self) void {
        if (self.isEmpty()) return;

        // Get first and last of source
        const first = self.head.next() orelse return;
        const last = self.head.prev() orelse return;

        // Get tail of destination
        const dest_last = dest.head.prev() orelse &dest.head;

        // Link source list to end of destination
        dest_last.setNext(first);
        first.setPrev(dest_last);
        last.setNext(&dest.head);
        dest.head.setPrev(last);

        // Update count
        dest.count += self.count;

        // Reset source
        self.init();
    }
};

// ============================================================================
// Callback Types
// ============================================================================

/// GC callback function type
pub const GCCallback = *const fn (phase: Phase, info: *const GCInfo) void;

/// GC collection phase
pub const Phase = enum {
    start,
    end,
};

/// GC collection info
pub const GCInfo = struct {
    generation: u2,
    collected: usize,
    uncollectable: usize,
};

/// GC statistics
pub const GCStats = struct {
    /// Collections per generation
    collections: [3]usize = .{ 0, 0, 0 },

    /// Objects collected per generation
    collected: [3]usize = .{ 0, 0, 0 },

    /// Uncollectable objects per generation
    uncollectable: [3]usize = .{ 0, 0, 0 },
};

/// Debug flags
pub const Debug = struct {
    pub const STATS: u32 = 1 << 0;
    pub const COLLECTABLE: u32 = 1 << 1;
    pub const UNCOLLECTABLE: u32 = 1 << 2;
    pub const SAVEALL: u32 = 1 << 5;
    pub const LEAK: u32 = COLLECTABLE | UNCOLLECTABLE;
};
