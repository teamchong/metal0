/// Allocator selection for PyAOT generated code
///
/// Strategy:
/// - Release builds (native): c_allocator - fastest, OS reclaims at exit
/// - Debug builds: GPA with safety checks for leak detection
/// - WASM: GPA (c_allocator not available)
///
/// Note: c_allocator in release mode means memory is not explicitly freed.
/// This is intentional for short-lived CLI programs where OS cleanup at
/// exit is acceptable (same pattern as Go, many Rust CLIs).
const std = @import("std");
const builtin = @import("builtin");

/// Returns true if we should use c_allocator (fast path, no cleanup needed)
pub fn useFastAllocator() bool {
    const is_wasm = comptime (builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64);
    const is_debug = comptime (builtin.mode == .Debug);
    return !is_wasm and !is_debug;
}

/// Get the appropriate allocator for generated code
/// - Release native: c_allocator (fast, no GPA needed)
/// - Debug/WASM: GPA allocator (safe, leak detection)
pub fn getAllocator(gpa_ptr: anytype) std.mem.Allocator {
    if (comptime useFastAllocator()) {
        return std.heap.c_allocator;
    }
    return gpa_ptr.allocator();
}

test "allocator selection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = getAllocator(&gpa);

    // Test that allocator works
    const mem = try alloc.alloc(u8, 1024);
    defer alloc.free(mem);

    try std.testing.expect(mem.len == 1024);
}
