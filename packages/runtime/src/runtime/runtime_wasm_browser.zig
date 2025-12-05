/// Minimal runtime for browser WASM (wasm32-freestanding)
/// No threads, no OS calls, pure computation only
const std = @import("std");

/// Stub allocator for browser WASM - uses fixed buffer
var buffer: [64 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);

pub fn getWasmAllocator() std.mem.Allocator {
    return fba.allocator();
}

/// Reset allocator between calls (for long-running WASM modules)
pub fn resetAllocator() void {
    fba.reset();
}

/// Basic print stub (browser WASM has no stdout)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    _ = fmt;
    _ = args;
    // No-op in browser - use JS console.log via exports
}

/// Export memory for JS interop
pub export fn alloc(size: usize) ?[*]u8 {
    const slice = fba.allocator().alloc(u8, size) catch return null;
    return slice.ptr;
}

pub export fn free(ptr: [*]u8, size: usize) void {
    fba.allocator().free(ptr[0..size]);
}
