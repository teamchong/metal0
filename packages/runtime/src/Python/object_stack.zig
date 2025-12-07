/// object_stack - Object Stack for Evaluation
/// Mirrors cpython/Python/object_stack.c
///
/// This module provides a stack for Python objects during evaluation:
/// - Push/pop operations for bytecode execution
/// - Stack frame management
/// - Overflow/underflow detection
/// - Integration with garbage collection

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Default stack size
pub const DEFAULT_STACK_SIZE: usize = 1024;

/// Maximum stack size
pub const MAX_STACK_SIZE: usize = 1_000_000;

/// Stack growth factor
const GROWTH_FACTOR: usize = 2;

/// Stack shrink threshold (when to shrink)
const SHRINK_THRESHOLD: usize = 4;

// ============================================================================
// Object Reference
// ============================================================================

/// A reference to a Python object (opaque pointer)
pub const PyObjectRef = *anyopaque;

/// Null object reference
pub const NULL_REF: ?PyObjectRef = null;

// ============================================================================
// Object Stack
// ============================================================================

/// Stack for Python objects during evaluation
pub const ObjectStack = struct {
    /// Stack storage
    items: []?PyObjectRef,
    /// Current stack pointer (index of next free slot)
    sp: usize,
    /// Stack capacity
    capacity: usize,
    /// Allocator
    allocator: Allocator,
    /// Whether to auto-grow
    auto_grow: bool,

    const Self = @This();

    /// Initialize with default size
    pub fn init(allocator: Allocator) !Self {
        return initWithCapacity(allocator, DEFAULT_STACK_SIZE);
    }

    /// Initialize with specific capacity
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) !Self {
        const items = try allocator.alloc(?PyObjectRef, capacity);
        @memset(items, null);

        return .{
            .items = items,
            .sp = 0,
            .capacity = capacity,
            .allocator = allocator,
            .auto_grow = true,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.items);
    }

    /// Push an object onto the stack
    pub fn push(self: *Self, obj: ?PyObjectRef) !void {
        if (self.sp >= self.capacity) {
            if (self.auto_grow) {
                try self.grow();
            } else {
                return error.StackOverflow;
            }
        }

        self.items[self.sp] = obj;
        self.sp += 1;
    }

    /// Pop an object from the stack
    pub fn pop(self: *Self) !?PyObjectRef {
        if (self.sp == 0) {
            return error.StackUnderflow;
        }

        self.sp -= 1;
        const obj = self.items[self.sp];
        self.items[self.sp] = null;
        return obj;
    }

    /// Pop without error (returns null if empty)
    pub fn popOrNull(self: *Self) ?PyObjectRef {
        return self.pop() catch null;
    }

    /// Peek at top of stack without removing
    pub fn peek(self: *const Self) ?PyObjectRef {
        if (self.sp == 0) return null;
        return self.items[self.sp - 1];
    }

    /// Peek at item at offset from top (0 = top)
    pub fn peekAt(self: *const Self, offset: usize) ?PyObjectRef {
        if (offset >= self.sp) return null;
        return self.items[self.sp - 1 - offset];
    }

    /// Set item at offset from top
    pub fn setAt(self: *Self, offset: usize, obj: ?PyObjectRef) !void {
        if (offset >= self.sp) return error.InvalidOffset;
        self.items[self.sp - 1 - offset] = obj;
    }

    /// Get current stack depth
    pub fn depth(self: *const Self) usize {
        return self.sp;
    }

    /// Check if stack is empty
    pub fn isEmpty(self: *const Self) bool {
        return self.sp == 0;
    }

    /// Clear the stack
    pub fn clear(self: *Self) void {
        @memset(self.items[0..self.sp], null);
        self.sp = 0;
    }

    /// Pop multiple items
    pub fn popN(self: *Self, n: usize) ![]?PyObjectRef {
        if (n > self.sp) {
            return error.StackUnderflow;
        }

        const result = self.allocator.alloc(?PyObjectRef, n) catch return error.OutOfMemory;
        const start = self.sp - n;

        @memcpy(result, self.items[start..self.sp]);
        @memset(self.items[start..self.sp], null);
        self.sp = start;

        return result;
    }

    /// Rotate top n items (move top to position n-1)
    pub fn rotate(self: *Self, n: usize) !void {
        if (n == 0 or n == 1) return;
        if (n > self.sp) return error.StackUnderflow;

        const top = self.items[self.sp - 1];
        const start = self.sp - n;

        // Shift items up
        var i: usize = self.sp - 1;
        while (i > start) : (i -= 1) {
            self.items[i] = self.items[i - 1];
        }
        self.items[start] = top;
    }

    /// Duplicate top of stack
    pub fn dup(self: *Self) !void {
        if (self.sp == 0) return error.StackUnderflow;
        try self.push(self.items[self.sp - 1]);
    }

    /// Duplicate top n items
    pub fn dupN(self: *Self, n: usize) !void {
        if (n > self.sp) return error.StackUnderflow;

        const start = self.sp - n;
        for (self.items[start..self.sp]) |item| {
            try self.push(item);
        }
    }

    /// Swap top two items
    pub fn swap(self: *Self) !void {
        if (self.sp < 2) return error.StackUnderflow;

        const tmp = self.items[self.sp - 1];
        self.items[self.sp - 1] = self.items[self.sp - 2];
        self.items[self.sp - 2] = tmp;
    }

    /// Grow the stack
    fn grow(self: *Self) !void {
        const new_capacity = @min(self.capacity * GROWTH_FACTOR, MAX_STACK_SIZE);
        if (new_capacity == self.capacity) {
            return error.StackOverflow;
        }

        const new_items = try self.allocator.realloc(self.items, new_capacity);
        @memset(new_items[self.capacity..], null);
        self.items = new_items;
        self.capacity = new_capacity;
    }

    /// Shrink the stack if appropriate
    pub fn maybeShrink(self: *Self) void {
        if (self.capacity > DEFAULT_STACK_SIZE and
            self.sp * SHRINK_THRESHOLD < self.capacity)
        {
            const new_capacity = @max(self.capacity / GROWTH_FACTOR, DEFAULT_STACK_SIZE);
            if (self.allocator.resize(self.items, new_capacity)) |new_items| {
                self.items = new_items;
                self.capacity = new_capacity;
            }
        }
    }

    /// Get slice of current stack contents
    pub fn getSlice(self: *const Self) []const ?PyObjectRef {
        return self.items[0..self.sp];
    }
};

// ============================================================================
// Stack Chunk (for chunked allocation)
// ============================================================================

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

// ============================================================================
// Stack Mark (for try/except)
// ============================================================================

/// Stack mark for exception handling
pub const StackMark = struct {
    depth: usize,
    frame_depth: usize,
};

/// Mark current stack position
pub fn markStack(stack: *const ObjectStack) StackMark {
    return .{
        .depth = stack.sp,
        .frame_depth = 0,
    };
}

/// Restore stack to mark
pub fn restoreStack(stack: *ObjectStack, mark: StackMark) void {
    if (stack.sp > mark.depth) {
        @memset(stack.items[mark.depth..stack.sp], null);
        stack.sp = mark.depth;
    }
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "object stack basic" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), stack.depth());

    // Use simple integers as mock objects
    var obj1: u32 = 1;
    var obj2: u32 = 2;
    var obj3: u32 = 3;

    try stack.push(&obj1);
    try stack.push(&obj2);
    try stack.push(&obj3);

    try std.testing.expectEqual(@as(usize, 3), stack.depth());
    try std.testing.expect(!stack.isEmpty());

    const top = stack.peek();
    try std.testing.expect(top == &obj3);

    const popped = try stack.pop();
    try std.testing.expect(popped == &obj3);
    try std.testing.expectEqual(@as(usize, 2), stack.depth());
}

test "object stack peek at" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;
    var obj3: u32 = 3;

    try stack.push(&obj1);
    try stack.push(&obj2);
    try stack.push(&obj3);

    try std.testing.expect(stack.peekAt(0) == &obj3);
    try std.testing.expect(stack.peekAt(1) == &obj2);
    try std.testing.expect(stack.peekAt(2) == &obj1);
    try std.testing.expect(stack.peekAt(3) == null);
}

test "object stack swap" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;

    try stack.push(&obj1);
    try stack.push(&obj2);

    try stack.swap();

    try std.testing.expect(stack.peekAt(0) == &obj1);
    try std.testing.expect(stack.peekAt(1) == &obj2);
}

test "object stack dup" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj: u32 = 42;

    try stack.push(&obj);
    try stack.dup();

    try std.testing.expectEqual(@as(usize, 2), stack.depth());
    try std.testing.expect(stack.peekAt(0) == &obj);
    try std.testing.expect(stack.peekAt(1) == &obj);
}

test "object stack rotate" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;
    var obj3: u32 = 3;

    try stack.push(&obj1);
    try stack.push(&obj2);
    try stack.push(&obj3);

    // Stack: [1, 2, 3] (3 on top)
    // Rotate 3: [3, 1, 2]
    try stack.rotate(3);

    try std.testing.expect(stack.peekAt(0) == &obj2);
    try std.testing.expect(stack.peekAt(1) == &obj1);
    try std.testing.expect(stack.peekAt(2) == &obj3);
}

test "object stack clear" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj: u32 = 42;

    try stack.push(&obj);
    try stack.push(&obj);

    stack.clear();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), stack.depth());
}

test "object stack underflow" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expectError(error.StackUnderflow, stack.pop());
}

test "stack mark and restore" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;

    try stack.push(&obj1);

    const mark = markStack(&stack);

    try stack.push(&obj2);
    try std.testing.expectEqual(@as(usize, 2), stack.depth());

    restoreStack(&stack, mark);
    try std.testing.expectEqual(@as(usize, 1), stack.depth());
}

test "chunked stack basic" {
    var stack = try ChunkedObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj: u32 = 42;

    // Push more than one chunk
    for (0..100) |_| {
        try stack.push(&obj);
    }

    try std.testing.expectEqual(@as(usize, 100), stack.depth());

    // Pop all
    for (0..100) |_| {
        _ = try stack.pop();
    }

    try std.testing.expectEqual(@as(usize, 0), stack.depth());
}
