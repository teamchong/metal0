// Benchmark SIMD number parsing with 8+ digit numbers
const std = @import("std");
const runtime = @import("runtime");
const allocator_helper = @import("allocator_helper");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const base_allocator = allocator_helper.getAllocator(&gpa);

    // JSON with many 8+ digit numbers (SIMD-optimizable)
    const json_data =
        \\{"numbers": [12345678, 98765432, 11111111, 22222222, 33333333, 44444444, 55555555, 66666666, 77777777, 88888888,
        \\12345678, 98765432, 11111111, 22222222, 33333333, 44444444, 55555555, 66666666, 77777777, 88888888,
        \\12345678, 98765432, 11111111, 22222222, 33333333, 44444444, 55555555, 66666666, 77777777, 88888888,
        \\12345678, 98765432, 11111111, 22222222, 33333333, 44444444, 55555555, 66666666, 77777777, 88888888,
        \\12345678, 98765432, 11111111, 22222222, 33333333, 44444444, 55555555, 66666666, 77777777, 88888888]}
    ;

    const json_str = try runtime.PyString.create(base_allocator, json_data);
    defer runtime.decref(json_str, base_allocator);

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();

    // Parse 100K times
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        const arena_allocator = arena.allocator();
        const parsed = try runtime.json.loads(json_str, arena_allocator);
        _ = parsed;
        _ = arena.reset(.retain_capacity);
    }
}
