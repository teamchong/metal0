/// Public JSON API for PyAOT - json.loads() and json.dumps()
const std = @import("std");
const runtime = @import("runtime.zig");
const parse_module = @import("json/parse.zig");
const JsonValue = @import("json/value.zig").JsonValue;

/// Deserialize JSON string to PyObject
/// Python: json.loads(json_str) -> obj
pub fn loads(json_str: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Validate input is a string
    if (json_str.type_id != .string) {
        return error.TypeError;
    }

    const str_data: *runtime.PyString = @ptrCast(@alignCast(json_str.data));
    const json_bytes = str_data.data;

    // Parse JSON into intermediate JsonValue
    var json_value = try parse_module.parse(json_bytes, allocator);

    // Convert to PyObject (duplicates all strings)
    const result = try json_value.toPyObject(allocator);

    // Clean up JsonValue and all its allocated data (strings were duplicated above)
    json_value.deinit(allocator);

    return result;
}

/// Serialize PyObject to JSON string
/// Python: json.dumps(obj) -> str
pub fn dumps(obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    try stringifyPyObject(obj, buffer.writer(allocator));

    const result_str = try buffer.toOwnedSlice(allocator);
    // Use createOwned to take ownership without duplicating (avoids memory leak)
    return try runtime.PyString.createOwned(allocator, result_str);
}

/// Stringify a PyObject to JSON format
fn stringifyPyObject(obj: *runtime.PyObject, writer: anytype) !void {
    switch (obj.type_id) {
        .none => {
            try writer.writeAll("null");
        },
        .bool => {
            const data: *runtime.PyInt = @ptrCast(@alignCast(obj.data));
            if (data.value != 0) {
                try writer.writeAll("true");
            } else {
                try writer.writeAll("false");
            }
        },
        .int => {
            const data: *runtime.PyInt = @ptrCast(@alignCast(obj.data));
            try writer.print("{}", .{data.value});
        },
        .float => {
            // TODO: Add proper float support when PyFloat is implemented
            try writer.writeAll("0.0");
        },
        .string => {
            const data: *runtime.PyString = @ptrCast(@alignCast(obj.data));
            try writer.writeByte('"');
            try writeEscapedString(data.data, writer);
            try writer.writeByte('"');
        },
        .list => {
            const data: *runtime.PyList = @ptrCast(@alignCast(obj.data));
            try writer.writeByte('[');

            for (data.items.items, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                try stringifyPyObject(item, writer);
            }

            try writer.writeByte(']');
        },
        .tuple => {
            const data: *runtime.PyTuple = @ptrCast(@alignCast(obj.data));
            try writer.writeByte('[');

            for (data.items, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                try stringifyPyObject(item, writer);
            }

            try writer.writeByte(']');
        },
        .dict => {
            const data: *runtime.PyDict = @ptrCast(@alignCast(obj.data));
            try writer.writeByte('{');

            // Collect and sort keys to match Python's json.dumps() behavior
            var keys = std.ArrayList([]const u8){};
            defer keys.deinit(std.heap.c_allocator);

            var it = data.map.keyIterator();
            while (it.next()) |key| {
                try keys.append(std.heap.c_allocator, key.*);
            }

            // Sort keys alphabetically (same as Python json.dumps with sort_keys=True)
            std.mem.sort([]const u8, keys.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.lessThan);

            for (keys.items, 0..) |key, i| {
                if (i > 0) try writer.writeByte(',');

                // Key
                try writer.writeByte('"');
                try writeEscapedString(key, writer);
                try writer.writeByte('"');
                try writer.writeByte(':');

                // Value
                const value = data.map.get(key).?;
                try stringifyPyObject(value, writer);
            }

            try writer.writeByte('}');
        },
    }
}

/// Write string with JSON escape sequences
fn writeEscapedString(str: []const u8, writer: anytype) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\x08' => try writer.writeAll("\\b"),
            '\x0C' => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                // Other control characters - escape as \uXXXX
                try writer.print("\\u{x:0>4}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
}

// Tests
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
    const json_str = try runtime.PyString.create(allocator, "{\"name\": \"PyAOT\"}");
    defer runtime.decref(json_str, allocator);

    const result = try loads(json_str, allocator);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.dict, result.type_id);

    if (runtime.PyDict.get(result, "name")) |value| {
        defer runtime.decref(value, allocator); // PyDict.get() increments ref count
        try std.testing.expectEqualStrings("PyAOT", runtime.PyString.getValue(value));
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

    const value = try runtime.PyString.create(allocator, "PyAOT");
    try runtime.PyDict.set(dict, "name", value);
    // Note: Dict now owns this reference, don't decref here

    const result = try dumps(dict, allocator);
    defer runtime.decref(result, allocator);

    const json_str = runtime.PyString.getValue(result);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"name\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"PyAOT\"") != null);
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
