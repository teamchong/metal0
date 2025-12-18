//! Thread-local scratch buffer for temporary allocations
//! Inspired by zell's allocator pattern - avoids repeated small allocations
//!
//! Usage pattern:
//!   var scratch = ScratchBuffer.init();
//!   defer scratch.deinit();
//!
//!   const temp_str = try std.fmt.allocPrint(scratch.allocator(), "temp {d}", .{42});
//!   // Use temp_str...
//!   scratch.reset(); // Reuse buffer for next operation

const std = @import("std");

/// Thread-local scratch buffer for temporary allocations
/// Reset after use instead of individual frees - 2-3x faster than repeated allocations
pub const ScratchBuffer = struct {
    /// 128KB scratch space - enough for most codegen temp strings
    const SIZE = 128 * 1024;

    buffer: [SIZE]u8 = undefined,
    fba: std.heap.FixedBufferAllocator,

    pub fn init() ScratchBuffer {
        var self: ScratchBuffer = undefined;
        self.fba = std.heap.FixedBufferAllocator.init(&self.buffer);
        return self;
    }

    pub fn allocator(self: *ScratchBuffer) std.mem.Allocator {
        return self.fba.allocator();
    }

    /// Reset buffer for reuse - much faster than freeing individual allocations
    pub fn reset(self: *ScratchBuffer) void {
        self.fba.reset();
    }

    /// Get remaining capacity in bytes
    pub fn remainingCapacity(self: *const ScratchBuffer) usize {
        return self.fba.end_index - self.fba.index;
    }

    /// Check if buffer has at least N bytes available
    pub fn hasCapacity(self: *const ScratchBuffer, bytes: usize) bool {
        return self.remainingCapacity() >= bytes;
    }

    pub fn deinit(self: *ScratchBuffer) void {
        _ = self; // No cleanup needed for fixed buffer
    }
};

/// Per-thread scratch buffer - use this in codegen hot paths
threadlocal var thread_scratch: ?ScratchBuffer = null;

/// Get thread-local scratch buffer (lazy init)
pub fn getThreadScratch() *ScratchBuffer {
    if (thread_scratch == null) {
        thread_scratch = ScratchBuffer.init();
    }
    return &thread_scratch.?;
}

/// Reset thread-local scratch buffer
pub fn resetThreadScratch() void {
    if (thread_scratch) |*scratch| {
        scratch.reset();
    }
}
