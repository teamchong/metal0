//! multiprocessing.heap - Shared memory heap management
//! Reference: cpython/Lib/multiprocessing/heap.py
//!
//! CPython __all__: ['BufferWrapper']
//!
//! Provides memory allocation from shared memory (mmap) for use
//! in multiprocessing. Allows efficient allocation and deallocation
//! of shared memory blocks.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Arena - Shared memory region
// ============================================================================

/// CPython: class Arena
/// A shared memory region backed by mmap
pub const Arena = struct {
    const Self = @This();

    size: usize,
    buffer: []align(std.mem.page_size) u8,
    name: ?[]const u8,
    fd: ?std.posix.fd_t,

    pub fn init(size: usize) !Self {
        // Create anonymous mmap
        const buffer = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );

        return .{
            .size = size,
            .buffer = buffer,
            .name = null,
            .fd = null,
        };
    }

    /// Create arena from file descriptor (for sharing between processes)
    pub fn initFromFd(fd: std.posix.fd_t, size: usize) !Self {
        const buffer = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );

        return .{
            .size = size,
            .buffer = buffer,
            .name = null,
            .fd = fd,
        };
    }

    pub fn deinit(self: *Self) void {
        std.posix.munmap(self.buffer);
        if (self.fd) |fd| {
            std.posix.close(fd);
        }
    }
};

// ============================================================================
// Heap - Memory allocator from shared arenas
// ============================================================================

/// Block header for tracking allocations
const BlockHeader = struct {
    size: usize,
    arena_index: usize,
    offset: usize,
    in_use: bool,
};

/// CPython: class Heap
/// Allocates memory from shared arenas
pub const Heap = struct {
    const Self = @This();
    const MIN_BLOCK_SIZE: usize = 64;
    const MAX_BLOCK_SIZE: usize = 1024 * 1024; // 1MB

    allocator: std.mem.Allocator,
    arenas: std.ArrayList(Arena),
    free_blocks: std.ArrayList(BlockHeader),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .arenas = .{},
            .free_blocks = .{},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.arenas.items) |*arena| {
            arena.deinit();
        }
        self.arenas.deinit(self.allocator);
        self.free_blocks.deinit(self.allocator);
    }

    /// Allocate a block of memory
    pub fn malloc(self: *Self, size: usize) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Round up to minimum block size
        const actual_size = @max(size, MIN_BLOCK_SIZE);

        // Try to find a free block
        for (self.free_blocks.items, 0..) |*block, i| {
            if (!block.in_use and block.size >= actual_size) {
                block.in_use = true;
                const arena = &self.arenas.items[block.arena_index];
                return arena.buffer[block.offset .. block.offset + actual_size];
            }
            _ = i;
        }

        // Need to allocate from a new arena
        const arena_size = @max(actual_size, 64 * 1024); // At least 64KB
        var arena = try Arena.init(arena_size);
        try self.arenas.append(self.allocator, arena);

        // Create block header
        const block = BlockHeader{
            .size = actual_size,
            .arena_index = self.arenas.items.len - 1,
            .offset = 0,
            .in_use = true,
        };
        try self.free_blocks.append(self.allocator, block);

        return self.arenas.items[self.arenas.items.len - 1].buffer[0..actual_size];
    }

    /// Free a block of memory
    pub fn free(self: *Self, ptr: []u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find the block
        for (self.free_blocks.items) |*block| {
            if (block.in_use) {
                const arena = &self.arenas.items[block.arena_index];
                const block_ptr = arena.buffer[block.offset .. block.offset + block.size];
                if (block_ptr.ptr == ptr.ptr) {
                    block.in_use = false;
                    return;
                }
            }
        }
    }
};

// ============================================================================
// BufferWrapper
// ============================================================================

/// CPython: class BufferWrapper
/// Wraps a shared memory buffer with automatic cleanup
pub const BufferWrapper = struct {
    const Self = @This();

    heap: *Heap,
    size: usize,
    buffer: ?[]u8,

    pub fn init(heap: *Heap, size: usize) !Self {
        const buffer = try heap.malloc(size);
        return .{
            .heap = heap,
            .size = size,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.buffer) |buf| {
            self.heap.free(buf);
            self.buffer = null;
        }
    }

    /// Get the buffer contents
    pub fn getBuffer(self: *Self) ?[]u8 {
        return self.buffer;
    }

    /// Create a view into the buffer
    pub fn createMemoryview(self: *Self) ?[]u8 {
        return self.buffer;
    }
};

// ============================================================================
// Module-level Heap
// ============================================================================

var _heap: ?Heap = null;
var _heap_lock: std.Thread.Mutex = .{};

/// Get or create the global heap
pub fn get_heap(allocator: std.mem.Allocator) *Heap {
    _heap_lock.lock();
    defer _heap_lock.unlock();

    if (_heap == null) {
        _heap = Heap.init(allocator);
    }
    return &_heap.?;
}

// ============================================================================
// Tests
// ============================================================================

test "Arena init" {
    var arena = try Arena.init(4096);
    defer arena.deinit();

    try std.testing.expectEqual(@as(usize, 4096), arena.size);
    try std.testing.expect(arena.buffer.len >= 4096);
}

test "Heap malloc and free" {
    const allocator = std.testing.allocator;
    var heap = Heap.init(allocator);
    defer heap.deinit();

    const buf = try heap.malloc(256);
    try std.testing.expect(buf.len >= 256);

    heap.free(buf);
}

test "BufferWrapper" {
    const allocator = std.testing.allocator;
    var heap = Heap.init(allocator);
    defer heap.deinit();

    var wrapper = try BufferWrapper.init(&heap, 128);
    defer wrapper.deinit();

    try std.testing.expect(wrapper.getBuffer() != null);
}
