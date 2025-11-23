// Benchmark PyAOT's JSON stringify with optimal allocator (WASM-compatible)
const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("src/allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Use comptime-selected allocator (C alloc on native, GPA on WASM)
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    // Create a PyObject structure to stringify
    // {"name":"test","value":123,"active":true,"items":[1,2,3]}
    const dict_obj = try runtime.PyDict.create(allocator);
    defer runtime.decref(dict_obj, allocator);

    // Add "name": "test"
    const val_name = try runtime.PyString.create(allocator, "test");
    try runtime.PyDict.set(dict_obj, "name", val_name);

    // Add "value": 123
    const val_value = try runtime.PyInt.create(allocator, 123);
    try runtime.PyDict.set(dict_obj, "value", val_value);

    // Add "active": true
    const val_active = try runtime.PyInt.create(allocator, 1);
    try runtime.PyDict.set(dict_obj, "active", val_active);

    // Add "items": [1,2,3]
    const list_obj = try runtime.PyList.create(allocator);
    const item1 = try runtime.PyInt.create(allocator, 1);
    const item2 = try runtime.PyInt.create(allocator, 2);
    const item3 = try runtime.PyInt.create(allocator, 3);
    try runtime.PyList.append(list_obj, item1);
    try runtime.PyList.append(list_obj, item2);
    try runtime.PyList.append(list_obj, item3);
    try runtime.PyDict.set(dict_obj, "items", list_obj);

    // Stringify 10000 times
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        const json_str = try json_module.dumps(dict_obj, allocator);
        runtime.decref(json_str, allocator);
    }
}
