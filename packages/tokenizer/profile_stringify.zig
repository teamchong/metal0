const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("src/allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = allocator_helper.getBenchmarkAllocator(gpa);

    const file = try std.fs.cwd().openFile("sample.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(base_allocator, 1024 * 1024);
    defer base_allocator.free(json_data);

    const json_str = try runtime.PyString.create(base_allocator, json_data);
    defer runtime.decref(json_str, base_allocator);

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const parsed = try json_module.loads(json_str, arena.allocator());

    // Just 100 iterations for quick profiling
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const result = try json_module.dumps(parsed, base_allocator);
        runtime.decref(result, base_allocator);
    }
    const end = std.time.nanoTimestamp();
    
    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    std.debug.print("Total: {d:.1}ms for 100 iterations\n", .{elapsed_ms});
    std.debug.print("Per iteration: {d:.2}ms\n", .{elapsed_ms / 100.0});
}
