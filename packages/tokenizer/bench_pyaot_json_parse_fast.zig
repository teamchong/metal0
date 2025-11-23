// Benchmark PyAOT's JSON parse with arena allocator optimization
const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("src/allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Use comptime-selected allocator (C alloc on native, GPA on WASM)
    const base_allocator = allocator_helper.getBenchmarkAllocator(gpa);

    // Read JSON file once
    const file = try std.fs.cwd().openFile("sample.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(base_allocator, 1024 * 1024);
    defer base_allocator.free(json_data);

    // Convert to PyString once (persistent)
    const json_str = try runtime.PyString.create(base_allocator, json_data);
    defer runtime.decref(json_str, base_allocator);

    // Create arena once, reuse for all iterations (2x faster than per-iteration arenas!)
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();

    // Parse 100K times (62KB JSON × 100K = 6.2GB total)
    // Arena reuse: allocate → parse → reset (retains capacity for next iteration)
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        const arena_allocator = arena.allocator();
        const parsed = try json_module.loads(json_str, arena_allocator);
        _ = parsed; // No decref needed - arena.reset() frees everything!
        _ = arena.reset(.retain_capacity); // Free memory, keep capacity for next iteration
    }
}
