/// pyarena - Memory Arena
/// Mirrors cpython/Python/pyarena.c
///
/// This module provides a memory arena for AST nodes:
/// - Fast allocation without individual frees
/// - All memory freed at once when arena is destroyed
/// - Used by the parser for AST construction

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Default block size for arena allocations
pub const DEFAULT_BLOCK_SIZE: usize = 8192;

/// Alignment for allocations
pub const ARENA_ALIGNMENT: usize = @alignOf(usize);

// ============================================================================
// Arena Block
// ============================================================================

/// A block of memory in the arena
pub const ArenaBlock = struct {
    data: []u8,
    used: usize = 0,
    next: ?*ArenaBlock = null,

    const Self = @This();

    /// Create a new block
    pub fn create(allocator: Allocator, size: usize) !*Self {
        const block = try allocator.create(Self);
        block.* = .{
            .data = try allocator.alloc(u8, size),
        };
        return block;
    }

    /// Destroy this block
    pub fn destroy(self: *Self, allocator: Allocator) void {
        allocator.free(self.data);
        allocator.destroy(self);
    }

    /// Try to allocate from this block
    pub fn alloc(self: *Self, size: usize, alignment: usize) ?[]u8 {
        // Align the current position
        const aligned_used = std.mem.alignForward(usize, self.used, alignment);

        if (aligned_used + size > self.data.len) {
            return null;
        }

        const result = self.data[aligned_used .. aligned_used + size];
        self.used = aligned_used + size;
        return result;
    }

    /// Get remaining capacity
    pub fn remaining(self: Self) usize {
        return self.data.len - self.used;
    }
};

// ============================================================================
// PyArena
// ============================================================================

/// Memory arena for Python AST and parser
pub const PyArena = struct {
    allocator: Allocator,
    blocks: ?*ArenaBlock = null,
    current: ?*ArenaBlock = null,
    block_size: usize = DEFAULT_BLOCK_SIZE,

    // Statistics
    total_allocated: usize = 0,
    num_blocks: usize = 0,
    num_allocations: usize = 0,

    // Object list for finalization
    objects: std.ArrayList(*anyopaque),

    const Self = @This();

    /// Create a new arena
    pub fn create(allocator: Allocator) !*Self {
        const arena = try allocator.create(Self);
        arena.* = .{
            .allocator = allocator,
            .objects = std.ArrayList(*anyopaque).init(allocator),
        };
        return arena;
    }

    /// Create arena with custom block size
    pub fn createWithSize(allocator: Allocator, block_size: usize) !*Self {
        const arena = try allocator.create(Self);
        arena.* = .{
            .allocator = allocator,
            .block_size = @max(block_size, 1024),
            .objects = std.ArrayList(*anyopaque).init(allocator),
        };
        return arena;
    }

    /// Destroy the arena and free all memory
    pub fn destroy(self: *Self) void {
        // Free all blocks
        var block = self.blocks;
        while (block) |b| {
            const next = b.next;
            b.destroy(self.allocator);
            block = next;
        }

        // Free object list
        self.objects.deinit();

        // Free arena itself
        self.allocator.destroy(self);
    }

    /// Allocate memory from the arena
    pub fn alloc(self: *Self, comptime T: type) !*T {
        return self.allocBytes(@sizeOf(T), @alignOf(T));
    }

    /// Allocate an array from the arena
    pub fn allocArray(self: *Self, comptime T: type, n: usize) ![]T {
        const bytes = try self.allocBytesSlice(@sizeOf(T) * n, @alignOf(T));
        return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
    }

    /// Allocate raw bytes
    pub fn allocBytes(self: *Self, size: usize, alignment: usize) !*anyopaque {
        const bytes = try self.allocBytesSlice(size, alignment);
        return bytes.ptr;
    }

    /// Allocate raw bytes as slice
    pub fn allocBytesSlice(self: *Self, size: usize, alignment: usize) ![]u8 {
        // Try current block first
        if (self.current) |block| {
            if (block.alloc(size, alignment)) |result| {
                self.num_allocations += 1;
                return result;
            }
        }

        // Need a new block
        const block_size = @max(self.block_size, size + alignment);
        const new_block = try ArenaBlock.create(self.allocator, block_size);

        // Link into list
        new_block.next = self.blocks;
        self.blocks = new_block;
        self.current = new_block;
        self.num_blocks += 1;
        self.total_allocated += block_size;

        // Allocate from new block
        const result = new_block.alloc(size, alignment) orelse unreachable;
        self.num_allocations += 1;
        return result;
    }

    /// Duplicate a string in the arena
    pub fn strdup(self: *Self, str: []const u8) ![]u8 {
        const result = try self.allocArray(u8, str.len + 1);
        @memcpy(result[0..str.len], str);
        result[str.len] = 0;
        return result[0..str.len];
    }

    /// Add an object to be tracked (for reference counting)
    pub fn addObject(self: *Self, obj: *anyopaque) !void {
        try self.objects.append(obj);
    }

    /// Get arena statistics
    pub fn getStats(self: Self) ArenaStats {
        return .{
            .total_allocated = self.total_allocated,
            .num_blocks = self.num_blocks,
            .num_allocations = self.num_allocations,
            .num_objects = self.objects.items.len,
        };
    }

    /// Reset arena (free all allocations but keep arena)
    pub fn reset(self: *Self) void {
        // Free all blocks except first
        if (self.blocks) |first| {
            var block = first.next;
            while (block) |b| {
                const next = b.next;
                b.destroy(self.allocator);
                block = next;
            }
            first.next = null;
            first.used = 0;
            self.current = first;
            self.num_blocks = 1;
        }

        self.objects.clearRetainingCapacity();
        self.num_allocations = 0;
    }
};

/// Arena statistics
pub const ArenaStats = struct {
    total_allocated: usize,
    num_blocks: usize,
    num_allocations: usize,
    num_objects: usize,
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a new arena
pub fn PyArena_New() !*PyArena {
    return PyArena.create(allocator_helper.fast_allocator);
}

/// Free an arena
pub fn PyArena_Free(arena: *PyArena) void {
    arena.destroy();
}

/// Allocate from arena
pub fn PyArena_Malloc(arena: *PyArena, size: usize) !*anyopaque {
    return arena.allocBytes(size, ARENA_ALIGNMENT);
}

/// Add object to arena's object list
pub fn PyArena_AddPyObject(arena: *PyArena, obj: *anyopaque) !void {
    try arena.addObject(obj);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "arena basic allocation" {
    const arena = try PyArena.create(std.testing.allocator);
    defer arena.destroy();

    const ptr1 = try arena.alloc(u64);
    ptr1.* = 42;
    try std.testing.expectEqual(@as(u64, 42), ptr1.*);

    const ptr2 = try arena.alloc(u32);
    ptr2.* = 123;
    try std.testing.expectEqual(@as(u32, 123), ptr2.*);
}

test "arena array allocation" {
    const arena = try PyArena.create(std.testing.allocator);
    defer arena.destroy();

    const arr = try arena.allocArray(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), arr.len);

    for (arr, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }
}

test "arena string duplication" {
    const arena = try PyArena.create(std.testing.allocator);
    defer arena.destroy();

    const s = try arena.strdup("hello world");
    try std.testing.expectEqualStrings("hello world", s);
}

test "arena statistics" {
    const arena = try PyArena.create(std.testing.allocator);
    defer arena.destroy();

    _ = try arena.alloc(u64);
    _ = try arena.alloc(u32);
    _ = try arena.allocArray(u8, 100);

    const stats = arena.getStats();
    try std.testing.expectEqual(@as(usize, 3), stats.num_allocations);
    try std.testing.expect(stats.total_allocated >= 100);
}

test "arena reset" {
    const arena = try PyArena.create(std.testing.allocator);
    defer arena.destroy();

    _ = try arena.alloc(u64);
    _ = try arena.allocArray(u8, 1000);

    const stats1 = arena.getStats();
    try std.testing.expect(stats1.num_allocations >= 2);

    arena.reset();

    const stats2 = arena.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats2.num_allocations);
}

test "arena large allocation" {
    const arena = try PyArena.create(std.testing.allocator);
    defer arena.destroy();

    // Allocate more than default block size
    const large = try arena.allocArray(u8, DEFAULT_BLOCK_SIZE * 2);
    try std.testing.expectEqual(@as(usize, DEFAULT_BLOCK_SIZE * 2), large.len);
}
