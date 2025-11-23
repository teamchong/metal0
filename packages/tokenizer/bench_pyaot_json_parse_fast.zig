// Benchmark PyAOT's JSON parse with optimal allocator (WASM-compatible)
const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("src/allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Use comptime-selected allocator (C alloc on native, GPA on WASM)
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    const file = try std.fs.cwd().openFile("sample.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_data);

    // Convert to PyString once
    const json_str = try runtime.PyString.create(allocator, json_data);
    defer runtime.decref(json_str, allocator);

    // Parse 100K times (62KB JSON = 6.2GB total data)
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        const parsed = try json_module.loads(json_str, allocator);
        runtime.decref(parsed, allocator);
    }
}
