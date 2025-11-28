/// JSON Arena Allocator - Fast bump-pointer allocation for JSON parsing
///
/// Strategy: Allocate a single large slab, bump pointer for each allocation.
/// All memory is freed at once when the JSON document is deallocated.
/// This matches PyPy's GC strategy: bump-allocate, bulk-free.
///
/// Performance: ~2 CPU cycles per allocation vs ~100+ for malloc
const std = @import("std");
const allocator_helper = @import("allocator_helper");

/// Thread-local arena pool for reuse (avoids mmap/munmap syscalls)
const POOL_SIZE = 8;
threadlocal var arena_pool: [POOL_SIZE]?*JsonArena = [_]?*JsonArena{null} ** POOL_SIZE;

/// JSON Arena - single contiguous allocation for entire parse
pub const JsonArena = struct {
    /// The memory slab
    buffer: []u8,
    /// Current allocation position (bump pointer)
    pos: usize,
    /// Backing allocator (for the slab itself)
    backing: std.mem.Allocator,
    /// Reference count - freed when reaches 0
    ref_count: usize,

    /// Default slab size: 1MB - enough for most JSON documents
    pub const DEFAULT_SIZE: usize = 1024 * 1024;

    /// Create a new arena with specified size (tries pool first)
    pub fn init(backing: std.mem.Allocator, size: usize) !*JsonArena {
        // Always try pool first for standard sizes
        for (&arena_pool) |*slot| {
            if (slot.*) |pooled| {
                // Only reuse if buffer is large enough
                if (pooled.buffer.len >= size) {
                    slot.* = null;
                    pooled.pos = 0; // Reset for reuse
                    pooled.ref_count = 1;
                    return pooled;
                }
            }
        }

        // Pool empty or no suitable arena - allocate new
        const arena = try backing.create(JsonArena);
        errdefer backing.destroy(arena);

        const actual_size = @max(size, DEFAULT_SIZE);
        const buffer = try backing.alloc(u8, actual_size);
        arena.* = .{
            .buffer = buffer,
            .pos = 0,
            .backing = backing,
            .ref_count = 1,
        };
        return arena;
    }

    /// Create arena with default size
    pub fn initDefault(backing: std.mem.Allocator) !*JsonArena {
        return init(backing, DEFAULT_SIZE);
    }

    /// Increment reference count
    pub fn incref(self: *JsonArena) void {
        self.ref_count += 1;
    }

    /// Decrement reference count, return to pool or free if zero
    pub fn decref(self: *JsonArena) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            // Try to return to pool (only standard-sized arenas)
            if (self.buffer.len == DEFAULT_SIZE) {
                for (&arena_pool) |*slot| {
                    if (slot.* == null) {
                        slot.* = self;
                        return; // Pooled for reuse!
                    }
                }
            }
            // Pool full or non-standard size - actually free
            self.backing.free(self.buffer);
            self.backing.destroy(self);
        }
    }

    /// Allocate from the arena (bump pointer)
    pub inline fn alloc(self: *JsonArena, comptime T: type) !*T {
        return self.allocAligned(T, @alignOf(T));
    }

    /// Allocate with specific alignment
    pub inline fn allocAligned(self: *JsonArena, comptime T: type, comptime alignment: u29) !*T {
        const size = @sizeOf(T);

        // Align position
        const aligned_pos = std.mem.alignForward(usize, self.pos, alignment);

        // Check if we have space
        if (aligned_pos + size > self.buffer.len) {
            return error.OutOfMemory;
        }

        const ptr: *T = @ptrCast(@alignCast(self.buffer[aligned_pos..].ptr));
        self.pos = aligned_pos + size;
        return ptr;
    }

    /// Allocate a slice from the arena
    pub inline fn allocSlice(self: *JsonArena, comptime T: type, len: usize) ![]T {
        const size = @sizeOf(T) * len;
        const alignment = @alignOf(T);

        const aligned_pos = std.mem.alignForward(usize, self.pos, alignment);

        if (aligned_pos + size > self.buffer.len) {
            return error.OutOfMemory;
        }

        const ptr: [*]T = @ptrCast(@alignCast(self.buffer[aligned_pos..].ptr));
        self.pos = aligned_pos + size;
        return ptr[0..len];
    }

    /// Duplicate a string into the arena
    pub fn dupeString(self: *JsonArena, str: []const u8) ![]const u8 {
        const dest = try self.allocSlice(u8, str.len);
        @memcpy(dest, str);
        return dest;
    }

    /// Get remaining capacity
    pub fn remaining(self: *const JsonArena) usize {
        return self.buffer.len - self.pos;
    }

    /// Reset arena for reuse (keeps buffer)
    pub fn reset(self: *JsonArena) void {
        self.pos = 0;
    }

    /// Create an allocator interface for this arena
    pub fn allocator(self: *JsonArena) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = vtableAlloc,
        .resize = vtableResize,
        .remap = vtableRemap,
        .free = vtableFree,
    };

    fn vtableAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *JsonArena = @ptrCast(@alignCast(ctx));
        const align_val = alignment.toByteUnits();

        const aligned_pos = std.mem.alignForward(usize, self.pos, align_val);
        if (aligned_pos + len > self.buffer.len) {
            return null;
        }

        const ptr = self.buffer[aligned_pos..].ptr;
        self.pos = aligned_pos + len;
        return ptr;
    }

    fn vtableResize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        // Arena doesn't support resize - always fail
        return false;
    }

    fn vtableRemap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        // Arena doesn't support remap - always fail
        return null;
    }

    fn vtableFree(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = ret_addr;
        // Arena doesn't free individual allocations - no-op
    }
};

test "JsonArena basic allocation" {
    const backing = std.testing.allocator;
    const arena = try JsonArena.init(backing, 4096);
    defer arena.decref();

    // Allocate some structs
    const TestStruct = struct { a: i64, b: i64 };
    const s1 = try arena.alloc(TestStruct);
    s1.* = .{ .a = 1, .b = 2 };

    const s2 = try arena.alloc(TestStruct);
    s2.* = .{ .a = 3, .b = 4 };

    try std.testing.expectEqual(@as(i64, 1), s1.a);
    try std.testing.expectEqual(@as(i64, 4), s2.b);
}

test "JsonArena string duplication" {
    const backing = std.testing.allocator;
    const arena = try JsonArena.init(backing, 4096);
    defer arena.decref();

    const str = try arena.dupeString("hello world");
    try std.testing.expectEqualStrings("hello world", str);
}

test "JsonArena refcount" {
    const backing = std.testing.allocator;
    const arena = try JsonArena.init(backing, 4096);

    arena.incref();
    try std.testing.expectEqual(@as(usize, 2), arena.ref_count);

    arena.decref();
    try std.testing.expectEqual(@as(usize, 1), arena.ref_count);

    arena.decref(); // Should free
}

test "JsonArena as allocator" {
    const backing = std.testing.allocator;
    const arena = try JsonArena.init(backing, 4096);
    defer arena.decref();

    const alloc = arena.allocator();

    // Use as standard allocator
    const slice = try alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), slice.len);

    // Free is a no-op (arena style)
    alloc.free(slice);
}
