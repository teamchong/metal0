// Benchmark PyAOT's JSON stringify with optimal allocator (WASM-compatible)
const std = @import("std");
const runtime = @import("runtime");
const allocator_helper = @import("allocator_helper");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Use comptime-selected allocator (C alloc on native, GPA on WASM)
    const allocator = allocator_helper.getAllocator(&gpa);

    // Load sample.json and parse it once
    const file = try std.fs.cwd().openFile("sample.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_data);

    const json_str = try runtime.PyString.create(allocator, json_data);
    defer runtime.decref(json_str, allocator);

    const parsed_obj = try runtime.json.loads(json_str, allocator);
    defer runtime.decref(parsed_obj, allocator);

    // Stringify 50K times to match parse benchmark (62KB JSON = 3.1GB total data)
    var i: usize = 0;
    while (i < 50_000) : (i += 1) {
        const stringified = try runtime.json.dumps(parsed_obj, allocator);
        runtime.decref(stringified, allocator);
    }
}
