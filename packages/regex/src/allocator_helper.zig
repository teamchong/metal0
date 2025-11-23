/// Shared allocator selection for optimal performance across platforms
/// Uses comptime to select the best allocator for each target (WASM-compatible)
const std = @import("std");
const builtin = @import("builtin");

/// Get optimal allocator for benchmark (comptime selection)
/// - Native (Linux/macOS/Windows): C allocator (fastest malloc/free)
/// - WASM: GPA (C allocator not available)
/// - Debug builds: GPA with safety checks
pub fn getBenchmarkAllocator(gpa: anytype) std.mem.Allocator {
    comptime {
        // Check if we're building for WASM
        const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;

        // Check if this is a debug build
        const is_debug = builtin.mode == .Debug;

        // Use GPA for WASM or debug builds (C allocator not available/wanted)
        if (is_wasm or is_debug) {
            return gpa.allocator();
        }
    }

    // For release builds on native platforms, use C allocator (15-30x faster)
    return std.heap.c_allocator;
}

/// Alternative: Get allocator type at comptime (for struct fields)
pub fn BenchmarkAllocatorType() type {
    comptime {
        const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;
        const is_debug = builtin.mode == .Debug;

        if (is_wasm or is_debug) {
            return std.heap.GeneralPurposeAllocator(.{});
        }
    }

    // For native release builds, we'll use c_allocator directly (no state needed)
    return void;
}

test "allocator selection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = getBenchmarkAllocator(gpa);

    // Test that allocator works
    const mem = try alloc.alloc(u8, 1024);
    defer alloc.free(mem);

    try std.testing.expect(mem.len == 1024);
}
