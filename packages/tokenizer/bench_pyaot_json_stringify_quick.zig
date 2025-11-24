const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("../../src/utils/allocator_helper.zig");

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
    const arena_allocator = arena.allocator();

    const parsed = try json_module.loads(json_str, arena_allocator);

    // Stringify 10K times (10x faster than 100K for quick iteration)
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        const result = try json_module.dumps(parsed, base_allocator);
        runtime.decref(result, base_allocator);
    }
}
