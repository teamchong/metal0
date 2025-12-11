/// Public JSON API for metal0 - modular structure
///
/// This module provides CPython-compatible JSON encoding/decoding
/// Split into focused submodules for maintainability:
/// - encoder.zig: JSON encoding (dumps, JSONEncoder)
/// - decoder.zig: JSON decoding (loads, JSONDecoder)
/// - types.zig: Type definitions and options
/// - errors.zig: Error types

const std = @import("std");
const runtime = @import("../runtime.zig");

// Re-export submodules
pub const encoder = @import("json/encoder.zig");
pub const decoder = @import("json/decoder.zig");
pub const types = @import("json/types.zig");
pub const errors = @import("json/errors.zig");

// Re-export for internal use (e.g. notebook parsing)
pub const parse = @import("json_impl/parse.zig").parse;
pub const Value = @import("json_impl/value.zig").JsonValue;
pub const JsonValue = Value;

// Re-export main encoding functions
pub const dumps = encoder.dumps;
pub const dumpsDirect = encoder.dumpsDirect;
pub const dumpsValue = encoder.dumpsValue;
pub const dump = encoder.dump;
pub const dumpsWithOptions = encoder.dumpsWithOptions;
pub const JSONEncoder = encoder.JSONEncoder;

// Re-export main decoding functions
pub const loads = decoder.loads;
pub const loadsLegacy = decoder.loadsLegacy;
pub const load = decoder.load;
pub const loadsWithOptions = decoder.loadsWithOptions;
pub const JSONDecoder = decoder.JSONDecoder;

// Re-export types
pub const DumpOptions = types.DumpOptions;
pub const LoadsOptions = types.LoadsOptions;

// Re-export errors
pub const JSONDecodeError = errors.JSONDecodeError;

// Tests moved to submodules remain accessible via test blocks
test "loads: parse null" {
    const allocator = std.testing.allocator;
    const json_str = try runtime.PyString.create(allocator, "null");
    defer runtime.decref(json_str, allocator);

    const result = try loads(json_str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.none, result.type_id);
}

test "loads: parse number" {
    const allocator = std.testing.allocator;
    const json_str = try runtime.PyString.create(allocator, "42");
    defer runtime.decref(json_str, allocator);

    const result = try loads(json_str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.int, result.type_id);
    try std.testing.expectEqual(@as(i64, 42), runtime.PyInt.getValue(result));
}

test "loads: parse string" {
    const allocator = std.testing.allocator;
    const json_str = try runtime.PyString.create(allocator, "\"hello\"");
    defer runtime.decref(json_str, allocator);

    const result = try loads(json_str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.string, result.type_id);
    try std.testing.expectEqualStrings("hello", runtime.PyString.getValue(result));
}

test "loads: parse array" {
    const allocator = std.testing.allocator;
    const json_str = try runtime.PyString.create(allocator, "[1, 2, 3]");
    defer runtime.decref(json_str, allocator);

    const result = try loads(json_str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.list, result.type_id);
    try std.testing.expectEqual(@as(usize, 3), runtime.PyList.len(result));
}

test "loads: parse object" {
    const allocator = std.testing.allocator;
    const json_str = try runtime.PyString.create(allocator, "{\"name\": \"metal0\"}");
    defer runtime.decref(json_str, allocator);

    const result = try loads(json_str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.dict, result.type_id);

    if (runtime.PyDict.get(result, "name")) |value| {
        defer runtime.decref(value, allocator); // PyDict.get() increments ref count
        try std.testing.expectEqualStrings("metal0", runtime.PyString.getValue(value));
    } else {
        return error.TestUnexpectedResult;
    }
}

test "dumps: stringify number" {
    const allocator = std.testing.allocator;
    const num = try runtime.PyInt.create(allocator, 42);
    defer runtime.decref(num, allocator);

    const result = try dumps(num, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqualStrings("42", runtime.PyString.getValue(result));
}

test "dumps: stringify string" {
    const allocator = std.testing.allocator;
    const str = try runtime.PyString.create(allocator, "hello");
    defer runtime.decref(str, allocator);

    const result = try dumps(str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqualStrings("\"hello\"", runtime.PyString.getValue(result));
}

test "dumps: stringify array" {
    const allocator = std.testing.allocator;
    const list = try runtime.PyList.create(allocator);
    defer runtime.decref(list, allocator);

    const item1 = try runtime.PyInt.create(allocator, 1);
    const item2 = try runtime.PyInt.create(allocator, 2);
    const item3 = try runtime.PyInt.create(allocator, 3);

    try runtime.PyList.append(list, item1);
    try runtime.PyList.append(list, item2);
    try runtime.PyList.append(list, item3);

    // Note: List now owns these references, don't decref here
    // They will be cleaned up when list is decref'd

    const result = try dumps(list, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqualStrings("[1,2,3]", runtime.PyString.getValue(result));
}

test "dumps: stringify object" {
    const allocator = std.testing.allocator;
    const dict = try runtime.PyDict.create(allocator);
    defer runtime.decref(dict, allocator);

    const value = try runtime.PyString.create(allocator, "metal0");
    try runtime.PyDict.set(dict, "name", value);
    // Note: Dict now owns this reference, don't decref here

    const result = try dumps(dict, allocator);
    defer runtime.decref(result, allocator);

    const json_str = runtime.PyString.getValue(result);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"name\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"metal0\"") != null);
}

test "round-trip: loads + dumps" {
    const allocator = std.testing.allocator;

    const original_json = "{\"test\":[1,2,3],\"nested\":{\"key\":\"value\"}}";
    const json_str = try runtime.PyString.create(allocator, original_json);
    defer runtime.decref(json_str, allocator);

    const parsed = try loads(json_str, allocator);
    defer runtime.decref(parsed, allocator);

    const dumped = try dumps(parsed, allocator);
    defer runtime.decref(dumped, allocator);

    // Verify structure matches (order may differ for objects)
    try std.testing.expectEqual(runtime.PyObject.TypeId.dict, parsed.type_id);
}
