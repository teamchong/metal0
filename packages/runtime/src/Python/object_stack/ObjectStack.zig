/// ObjectStack - Main stack implementation for Python objects
/// Provides push/pop operations with automatic growth

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A reference to a Python object (opaque pointer)
pub const PyObjectRef = *anyopaque;

/// Null object reference
pub const NULL_REF: ?PyObjectRef = null;

/// Default stack size
pub const DEFAULT_STACK_SIZE: usize = 1024;

/// Maximum stack size
pub const MAX_STACK_SIZE: usize = 1_000_000;

/// Stack growth factor
const GROWTH_FACTOR: usize = 2;

/// Stack shrink threshold (when to shrink)
const SHRINK_THRESHOLD: usize = 4;

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
