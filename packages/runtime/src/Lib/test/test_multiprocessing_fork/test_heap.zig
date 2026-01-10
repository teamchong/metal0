//! test.test_multiprocessing_fork.test_heap - Multiprocessing heap tests (fork start method)
const std = @import("std");

/// Arena for shared memory allocation (fork method - can share memory directly)
pub const Arena = struct {
    buffer: []u8,
    offset: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize) !Arena {
        const buffer = try allocator.alloc(u8, size);
        return .{
            .buffer = buffer,
            .offset = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Arena) void {
        self.allocator.free(self.buffer);
    }

    pub fn alloc(self: *Arena, size: usize) ![]u8 {
        if (self.offset + size > self.buffer.len) {
            return error.OutOfMemory;
        }
        const result = self.buffer[self.offset..][0..size];
        self.offset += size;
        return result;
    }

    pub fn free_space(self: *Arena) usize {
        return self.buffer.len - self.offset;
    }

    pub fn reset(self: *Arena) void {
        self.offset = 0;
    }
};

/// Heap for managing shared memory blocks (fork method)
pub const Heap = struct {
    arenas: std.ArrayList(*Arena),
    allocator: std.mem.Allocator,
    block_size: usize,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, block_size: usize) Heap {
        return .{
            .arenas = std.ArrayList(*Arena).init(allocator),
            .allocator = allocator,
            .block_size = block_size,
        };
    }

    pub fn deinit(self: *Heap) void {
        for (self.arenas.items) |arena| {
            arena.deinit();
            self.allocator.destroy(arena);
        }
        self.arenas.deinit();
    }

    pub fn malloc(self: *Heap, size: usize) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to allocate from existing arenas
        for (self.arenas.items) |arena| {
            if (arena.free_space() >= size) {
                return arena.alloc(size);
            }
        }

        // Create new arena
        const arena_size = @max(self.block_size, size);
        const arena = try self.allocator.create(Arena);
        arena.* = try Arena.init(self.allocator, arena_size);
        try self.arenas.append(arena);

        return arena.alloc(size);
    }

    pub fn free(self: *Heap, ptr: []u8) void {
        _ = self;
        _ = ptr;
        // In this simple implementation, memory is only freed when heap is destroyed
    }

    pub fn total_size(self: *Heap) usize {
        var total: usize = 0;
        for (self.arenas.items) |arena| {
            total += arena.buffer.len;
        }
        return total;
    }

    pub fn used_size(self: *Heap) usize {
        var used: usize = 0;
        for (self.arenas.items) |arena| {
            used += arena.offset;
        }
        return used;
    }
};

/// Free list based allocator
pub const FreeList = struct {
    const Block = struct {
        start: usize,
        size: usize,
    };

    blocks: std.ArrayList(Block),
    buffer: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize) !FreeList {
        var blocks = std.ArrayList(Block).init(allocator);
        const buffer = try allocator.alloc(u8, size);

        // Start with one big free block
        try blocks.append(.{ .start = 0, .size = size });

        return .{
            .blocks = blocks,
            .buffer = buffer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FreeList) void {
        self.blocks.deinit();
        self.allocator.free(self.buffer);
    }

    pub fn alloc(self: *FreeList, size: usize) ![]u8 {
        // First fit algorithm
        for (self.blocks.items, 0..) |*block, i| {
            if (block.size >= size) {
                const start = block.start;
                if (block.size == size) {
                    _ = self.blocks.orderedRemove(i);
                } else {
                    block.start += size;
                    block.size -= size;
                }
                return self.buffer[start..][0..size];
            }
        }
        return error.OutOfMemory;
    }

    pub fn free(self: *FreeList, ptr: []u8) !void {
        const start = @intFromPtr(ptr.ptr) - @intFromPtr(self.buffer.ptr);
        const size = ptr.len;

        // Add back to free list (simplified - no coalescing)
        try self.blocks.append(.{ .start = start, .size = size });
    }
};

/// Buffer wrapper for shared memory
pub const BufferWrapper = struct {
    data: []u8,
    size: usize,
    offset: usize = 0,

    pub fn init(data: []u8) BufferWrapper {
        return .{
            .data = data,
            .size = data.len,
        };
    }

    pub fn write(self: *BufferWrapper, bytes: []const u8) !usize {
        if (self.offset + bytes.len > self.size) {
            return error.BufferFull;
        }
        @memcpy(self.data[self.offset..][0..bytes.len], bytes);
        self.offset += bytes.len;
        return bytes.len;
    }

    pub fn read(self: *BufferWrapper, count: usize) ![]u8 {
        if (self.offset < count) {
            return error.BufferEmpty;
        }
        self.offset -= count;
        return self.data[self.offset..][0..count];
    }

    pub fn remaining(self: *BufferWrapper) usize {
        return self.size - self.offset;
    }
};

test "arena allocation" {
    const allocator = std.testing.allocator;
    var arena = try Arena.init(allocator, 1024);
    defer arena.deinit();

    const block1 = try arena.alloc(100);
    try std.testing.expectEqual(@as(usize, 100), block1.len);

    const block2 = try arena.alloc(200);
    try std.testing.expectEqual(@as(usize, 200), block2.len);

    try std.testing.expectEqual(@as(usize, 724), arena.free_space());
}

test "arena overflow" {
    const allocator = std.testing.allocator;
    var arena = try Arena.init(allocator, 100);
    defer arena.deinit();

    _ = try arena.alloc(50);
    try std.testing.expectError(error.OutOfMemory, arena.alloc(100));
}

test "arena reset" {
    const allocator = std.testing.allocator;
    var arena = try Arena.init(allocator, 100);
    defer arena.deinit();

    _ = try arena.alloc(50);
    try std.testing.expectEqual(@as(usize, 50), arena.free_space());

    arena.reset();
    try std.testing.expectEqual(@as(usize, 100), arena.free_space());
}

test "heap allocation" {
    const allocator = std.testing.allocator;
    var heap = Heap.init(allocator, 1024);
    defer heap.deinit();

    const block1 = try heap.malloc(100);
    try std.testing.expectEqual(@as(usize, 100), block1.len);

    const block2 = try heap.malloc(200);
    try std.testing.expectEqual(@as(usize, 200), block2.len);

    try std.testing.expectEqual(@as(usize, 300), heap.used_size());
}

test "heap grows" {
    const allocator = std.testing.allocator;
    var heap = Heap.init(allocator, 100);
    defer heap.deinit();

    _ = try heap.malloc(50);
    _ = try heap.malloc(50);
    _ = try heap.malloc(50); // Should create new arena

    try std.testing.expect(heap.arenas.items.len >= 2);
}

test "heap total size" {
    const allocator = std.testing.allocator;
    var heap = Heap.init(allocator, 100);
    defer heap.deinit();

    _ = try heap.malloc(50);
    try std.testing.expectEqual(@as(usize, 100), heap.total_size());

    _ = try heap.malloc(60); // Forces new arena
    try std.testing.expectEqual(@as(usize, 200), heap.total_size());
}

test "freelist allocation" {
    const allocator = std.testing.allocator;
    var fl = try FreeList.init(allocator, 1024);
    defer fl.deinit();

    const block1 = try fl.alloc(100);
    try std.testing.expectEqual(@as(usize, 100), block1.len);

    const block2 = try fl.alloc(200);
    try std.testing.expectEqual(@as(usize, 200), block2.len);
}

test "buffer wrapper" {
    var data: [100]u8 = undefined;
    var buf = BufferWrapper.init(&data);

    const written = try buf.write("hello");
    try std.testing.expectEqual(@as(usize, 5), written);
    try std.testing.expectEqual(@as(usize, 95), buf.remaining());
}

test "buffer wrapper overflow" {
    var data: [5]u8 = undefined;
    var buf = BufferWrapper.init(&data);

    try std.testing.expectError(error.BufferFull, buf.write("hello world"));
}

test "freelist free and realloc" {
    const allocator = std.testing.allocator;
    var fl = try FreeList.init(allocator, 1024);
    defer fl.deinit();

    const block1 = try fl.alloc(100);
    try fl.free(block1);

    // Can allocate again after freeing
    const block2 = try fl.alloc(50);
    try std.testing.expectEqual(@as(usize, 50), block2.len);
}
