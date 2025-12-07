/// stackrefs - Stack References
/// Mirrors cpython/Python/stackrefs.c
///
/// This module provides stack reference management for Python objects:
/// - Borrowed vs owned references on stack
/// - Reference stealing operations
/// - Integration with free-threading (PEP 703)
/// - Safe reference counting for stack operations

const std = @import("std");
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Tag bits for reference type
const TAG_BITS: usize = 2;
const TAG_MASK: usize = (1 << TAG_BITS) - 1;

/// Reference tags
const TAG_NULL: usize = 0;
const TAG_BORROWED: usize = 1;
const TAG_OWNED: usize = 2;
const TAG_IMMORTAL: usize = 3;

// ============================================================================
// Stack Reference
// ============================================================================

/// A tagged reference on the stack
/// Encodes ownership information in low bits of pointer
pub const StackRef = packed struct {
    /// The raw tagged pointer value
    bits: usize,

    const Self = @This();

    /// Create a null reference
    pub fn null_ref() Self {
        return .{ .bits = TAG_NULL };
    }

    /// Create a borrowed reference
    pub fn borrowed(ptr: *anyopaque) Self {
        return .{ .bits = @intFromPtr(ptr) | TAG_BORROWED };
    }

    /// Create an owned reference
    pub fn owned(ptr: *anyopaque) Self {
        return .{ .bits = @intFromPtr(ptr) | TAG_OWNED };
    }

    /// Create an immortal reference
    pub fn immortal(ptr: *anyopaque) Self {
        return .{ .bits = @intFromPtr(ptr) | TAG_IMMORTAL };
    }

    /// Get the pointer (stripped of tags)
    pub fn ptr(self: Self) ?*anyopaque {
        const addr = self.bits & ~TAG_MASK;
        if (addr == 0) return null;
        return @ptrFromInt(addr);
    }

    /// Check if null
    pub fn isNull(self: Self) bool {
        return (self.bits & ~TAG_MASK) == 0;
    }

    /// Check if borrowed
    pub fn isBorrowed(self: Self) bool {
        return (self.bits & TAG_MASK) == TAG_BORROWED;
    }

    /// Check if owned
    pub fn isOwned(self: Self) bool {
        return (self.bits & TAG_MASK) == TAG_OWNED;
    }

    /// Check if immortal
    pub fn isImmortal(self: Self) bool {
        return (self.bits & TAG_MASK) == TAG_IMMORTAL;
    }

    /// Get the tag
    pub fn getTag(self: Self) usize {
        return self.bits & TAG_MASK;
    }

    /// Convert to owned (for stealing)
    pub fn toOwned(self: Self) Self {
        if (self.isNull() or self.isImmortal()) return self;
        return .{ .bits = (self.bits & ~TAG_MASK) | TAG_OWNED };
    }

    /// Convert to borrowed
    pub fn toBorrowed(self: Self) Self {
        if (self.isNull() or self.isImmortal()) return self;
        return .{ .bits = (self.bits & ~TAG_MASK) | TAG_BORROWED };
    }

    /// Compare two stack refs
    pub fn eql(self: Self, other: Self) bool {
        return self.bits == other.bits;
    }

    /// Compare pointers only (ignore tags)
    pub fn ptrEql(self: Self, other: Self) bool {
        return (self.bits & ~TAG_MASK) == (other.bits & ~TAG_MASK);
    }
};

// ============================================================================
// Reference Operations
// ============================================================================

/// Callback type for reference counting operations
pub const IncrefFn = *const fn (*anyopaque) void;
pub const DecrefFn = *const fn (*anyopaque) void;

/// Reference counting callbacks (set by runtime)
var incref_fn: ?IncrefFn = null;
var decref_fn: ?DecrefFn = null;

/// Set reference counting callbacks
pub fn setRefcountCallbacks(incref: IncrefFn, decref: DecrefFn) void {
    incref_fn = incref;
    decref_fn = decref;
}

/// Increment reference count
pub fn incref(ref: StackRef) void {
    if (ref.isNull() or ref.isImmortal() or ref.isBorrowed()) return;
    if (incref_fn) |f| {
        if (ref.ptr()) |p| {
            f(p);
        }
    }
}

/// Decrement reference count
pub fn decref(ref: StackRef) void {
    if (ref.isNull() or ref.isImmortal() or ref.isBorrowed()) return;
    if (decref_fn) |f| {
        if (ref.ptr()) |p| {
            f(p);
        }
    }
}

/// Steal a reference (convert to owned without incref)
pub fn steal(ref: StackRef) StackRef {
    return ref.toOwned();
}

/// Borrow a reference (create borrowed ref)
pub fn borrow(ref: StackRef) StackRef {
    return ref.toBorrowed();
}

/// New reference (incref and return owned)
pub fn newRef(ref: StackRef) StackRef {
    incref(ref);
    return ref.toOwned();
}

/// Clear reference (decref if owned)
pub fn clearRef(ref: *StackRef) void {
    if (ref.isOwned()) {
        decref(ref.*);
    }
    ref.* = StackRef.null_ref();
}

/// Move reference (transfer ownership)
pub fn moveRef(dest: *StackRef, src: *StackRef) void {
    clearRef(dest);
    dest.* = src.*;
    src.* = StackRef.null_ref();
}

/// Copy reference (incref and copy)
pub fn copyRef(dest: *StackRef, src: StackRef) void {
    clearRef(dest);
    dest.* = newRef(src);
}

// ============================================================================
// Stack Reference Array
// ============================================================================

/// Array of stack references with automatic cleanup
pub const StackRefArray = struct {
    refs: []StackRef,
    len: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        const refs = try allocator.alloc(StackRef, capacity);
        for (refs) |*r| {
            r.* = StackRef.null_ref();
        }
        return .{
            .refs = refs,
            .len = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.clearAll();
        self.allocator.free(self.refs);
    }

    /// Add a reference
    pub fn push(self: *Self, ref: StackRef) !void {
        if (self.len >= self.refs.len) {
            return error.ArrayFull;
        }
        self.refs[self.len] = ref;
        self.len += 1;
    }

    /// Remove last reference
    pub fn pop(self: *Self) ?StackRef {
        if (self.len == 0) return null;
        self.len -= 1;
        const ref = self.refs[self.len];
        self.refs[self.len] = StackRef.null_ref();
        return ref;
    }

    /// Get reference at index
    pub fn get(self: *const Self, idx: usize) ?StackRef {
        if (idx >= self.len) return null;
        return self.refs[idx];
    }

    /// Set reference at index (clears existing)
    pub fn set(self: *Self, idx: usize, ref: StackRef) !void {
        if (idx >= self.refs.len) return error.IndexOutOfBounds;
        clearRef(&self.refs[idx]);
        self.refs[idx] = ref;
        if (idx >= self.len) self.len = idx + 1;
    }

    /// Clear all references
    pub fn clearAll(self: *Self) void {
        for (self.refs[0..self.len]) |*r| {
            clearRef(r);
        }
        self.len = 0;
    }

    /// Get current length
    pub fn length(self: *const Self) usize {
        return self.len;
    }
};

// ============================================================================
// Tagged Union Reference
// ============================================================================

/// A reference that can be either a Python object or a special value
pub const TaggedRef = union(enum) {
    object: StackRef,
    none: void,
    true_val: void,
    false_val: void,
    not_implemented: void,
    ellipsis: void,
    int_cached: i64,

    const Self = @This();

    pub fn fromObject(ref: StackRef) Self {
        return .{ .object = ref };
    }

    pub fn isObject(self: Self) bool {
        return self == .object;
    }

    pub fn getObject(self: Self) ?StackRef {
        return switch (self) {
            .object => |ref| ref,
            else => null,
        };
    }
};

// ============================================================================
// Reference Pool
// ============================================================================

/// Pool of pre-allocated stack references for fast allocation
pub const RefPool = struct {
    pool: []StackRef,
    free_list: []usize,
    free_count: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
        const pool = try allocator.alloc(StackRef, size);
        const free_list = try allocator.alloc(usize, size);

        for (pool, 0..) |*r, i| {
            r.* = StackRef.null_ref();
            free_list[i] = size - 1 - i;
        }

        return .{
            .pool = pool,
            .free_list = free_list,
            .free_count = size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.pool);
        self.allocator.free(self.free_list);
    }

    /// Allocate a slot
    pub fn alloc_slot(self: *Self) ?*StackRef {
        if (self.free_count == 0) return null;
        self.free_count -= 1;
        const idx = self.free_list[self.free_count];
        return &self.pool[idx];
    }

    /// Free a slot
    pub fn free(self: *Self, slot: *StackRef) void {
        clearRef(slot);
        const idx = (@intFromPtr(slot) - @intFromPtr(self.pool.ptr)) / @sizeOf(StackRef);
        if (self.free_count < self.free_list.len) {
            self.free_list[self.free_count] = idx;
            self.free_count += 1;
        }
    }
};

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "stack ref creation" {
    var obj: u32 = 42;

    const null_ref = StackRef.null_ref();
    try std.testing.expect(null_ref.isNull());

    const borrowed_ref = StackRef.borrowed(&obj);
    try std.testing.expect(borrowed_ref.isBorrowed());
    try std.testing.expect(!borrowed_ref.isNull());
    try std.testing.expect(borrowed_ref.ptr() == &obj);

    const owned_ref = StackRef.owned(&obj);
    try std.testing.expect(owned_ref.isOwned());
    try std.testing.expect(owned_ref.ptr() == &obj);

    const immortal_ref = StackRef.immortal(&obj);
    try std.testing.expect(immortal_ref.isImmortal());
}

test "stack ref conversion" {
    var obj: u32 = 42;

    const borrowed_ref = StackRef.borrowed(&obj);
    const owned_ref = borrowed_ref.toOwned();

    try std.testing.expect(owned_ref.isOwned());
    try std.testing.expect(borrowed_ref.ptrEql(owned_ref));

    const back_to_borrowed = owned_ref.toBorrowed();
    try std.testing.expect(back_to_borrowed.isBorrowed());
}

test "stack ref comparison" {
    var obj1: u32 = 1;
    var obj2: u32 = 2;

    const ref1 = StackRef.owned(&obj1);
    const ref1_borrowed = StackRef.borrowed(&obj1);
    const ref2 = StackRef.owned(&obj2);

    try std.testing.expect(!ref1.eql(ref1_borrowed)); // Different tags
    try std.testing.expect(ref1.ptrEql(ref1_borrowed)); // Same pointer
    try std.testing.expect(!ref1.ptrEql(ref2)); // Different pointers
}

test "stack ref array" {
    var arr = try StackRefArray.init(std.testing.allocator, 10);
    defer arr.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;

    try arr.push(StackRef.owned(&obj1));
    try arr.push(StackRef.owned(&obj2));

    try std.testing.expectEqual(@as(usize, 2), arr.length());

    const ref1 = arr.get(0);
    try std.testing.expect(ref1 != null);
    try std.testing.expect(ref1.?.ptr() == &obj1);

    const popped = arr.pop();
    try std.testing.expect(popped != null);
    try std.testing.expect(popped.?.ptr() == &obj2);
    try std.testing.expectEqual(@as(usize, 1), arr.length());
}

test "tagged ref" {
    var obj: u32 = 42;
    const ref = StackRef.owned(&obj);

    const tagged = TaggedRef.fromObject(ref);
    try std.testing.expect(tagged.isObject());

    const retrieved = tagged.getObject();
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.ptr() == &obj);

    const none = TaggedRef{ .none = {} };
    try std.testing.expect(!none.isObject());
    try std.testing.expect(none.getObject() == null);
}

test "ref pool" {
    var pool = try RefPool.init(std.testing.allocator, 10);
    defer pool.deinit();

    const slot1 = pool.alloc_slot();
    try std.testing.expect(slot1 != null);

    const slot2 = pool.alloc_slot();
    try std.testing.expect(slot2 != null);
    try std.testing.expect(slot1 != slot2);

    pool.free(slot1.?);

    const slot3 = pool.alloc_slot();
    try std.testing.expect(slot3 != null);
    try std.testing.expect(slot3 == slot1); // Reused
}

test "steal and borrow" {
    var obj: u32 = 42;

    const owned_ref = StackRef.owned(&obj);
    const stolen = steal(owned_ref);
    try std.testing.expect(stolen.isOwned());

    const borrowed_ref = borrow(owned_ref);
    try std.testing.expect(borrowed_ref.isBorrowed());
}
