/// ChunkedObjectStack - Chunked stack for large stacks
/// Uses linked list of fixed-size chunks to avoid large reallocations

const std = @import("std");
const Allocator = std.mem.Allocator;
const ObjectStackMod = @import("ObjectStack.zig");
const PyObjectRef = ObjectStackMod.PyObjectRef;

/// Chunk size for chunked stack
const CHUNK_SIZE: usize = 64;

/// A chunk of stack storage
const StackChunk = struct {
    items: [CHUNK_SIZE]?PyObjectRef,
    next: ?*StackChunk,
    prev: ?*StackChunk,

    fn init() StackChunk {
        return .{
            .items = [_]?PyObjectRef{null} ** CHUNK_SIZE,
            .next = null,
            .prev = null,
        };
    }
};

/// Chunked stack for large stacks
pub const ChunkedObjectStack = struct {
    /// First chunk
    first: ?*StackChunk,
    /// Current chunk
    current: ?*StackChunk,
    /// Index within current chunk
    chunk_index: usize,
    /// Total depth
    total_depth: usize,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const chunk = try allocator.create(StackChunk);
        chunk.* = StackChunk.init();

        return .{
            .first = chunk,
            .current = chunk,
            .chunk_index = 0,
            .total_depth = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var chunk = self.first;
        while (chunk) |c| {
            const next = c.next;
            self.allocator.destroy(c);
            chunk = next;
        }
    }

    pub fn push(self: *Self, obj: ?PyObjectRef) !void {
        if (self.chunk_index >= CHUNK_SIZE) {
            // Need new chunk
            if (self.current.?.next) |next| {
                self.current = next;
            } else {
                const new_chunk = try self.allocator.create(StackChunk);
                new_chunk.* = StackChunk.init();
                new_chunk.prev = self.current;
                self.current.?.next = new_chunk;
                self.current = new_chunk;
            }
            self.chunk_index = 0;
        }

        self.current.?.items[self.chunk_index] = obj;
        self.chunk_index += 1;
        self.total_depth += 1;
    }

    pub fn pop(self: *Self) !?PyObjectRef {
        if (self.total_depth == 0) {
            return error.StackUnderflow;
        }

        if (self.chunk_index == 0) {
            // Move to previous chunk
            self.current = self.current.?.prev;
            self.chunk_index = CHUNK_SIZE;
        }

        self.chunk_index -= 1;
        self.total_depth -= 1;
        const obj = self.current.?.items[self.chunk_index];
        self.current.?.items[self.chunk_index] = null;
        return obj;
    }

    pub fn depth(self: *const Self) usize {
        return self.total_depth;
    }
};
