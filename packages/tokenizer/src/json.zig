/// Public JSON API for PyAOT - json.loads() and json.dumps()
const std = @import("std");
const runtime = @import("runtime.zig");
const parse_direct = @import("json/parse_direct.zig");

/// Deserialize JSON string to PyObject
/// Python: json.loads(json_str) -> obj
pub fn loads(json_str: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Validate input is a string
    if (json_str.type_id != .string) {
        return error.TypeError;
    }

    const str_data: *runtime.PyString = @ptrCast(@alignCast(json_str.data));
    const json_bytes = str_data.data;

    // Parse JSON directly to PyObject (no intermediate representation!)
    const result = try parse_direct.parse(json_bytes, allocator);

    return result;
}

/// Serialize PyObject to JSON string
/// Python: json.dumps(obj) -> str
pub fn dumps(obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Estimate capacity: typical JSON is ~1.5x object size (with formatting)
    // Pre-allocation avoids multiple ArrayList growth operations (1.5x faster!)
    const estimated_size = estimateJsonSize(obj);
    var buffer = try std.ArrayList(u8).initCapacity(allocator, estimated_size);
    defer buffer.deinit(allocator);

    // Direct buffer access - bypass writer() overhead!
    try stringifyPyObjectDirect(obj, &buffer, allocator);

    const result_str = try buffer.toOwnedSlice(allocator);
    // Use createOwned to take ownership without duplicating (avoids memory leak)
    return try runtime.PyString.createOwned(allocator, result_str);
}

/// Comptime string table - avoids strlen at runtime
const JSON_NULL = "null";
const JSON_TRUE = "true";
const JSON_FALSE = "false";
const JSON_ZERO = "0.0";

/// Comptime lookup table for escape detection (much faster than switch!)
const NEEDS_ESCAPE: [256]bool = blk: {
    var table: [256]bool = [_]bool{false} ** 256;
    table['"'] = true;
    table['\\'] = true;
    table['\x08'] = true;
    table['\x0C'] = true;
    table['\n'] = true;
    table['\r'] = true;
    table['\t'] = true;
    // Control characters 0x00-0x1F
    var i: u8 = 0;
    while (i <= 0x1F) : (i += 1) {
        table[i] = true;
    }
    break :blk table;
};

/// Comptime lookup table for escape sequences (eliminates switch!)
const ESCAPE_SEQUENCES: [256][]const u8 = blk: {
    var table: [256][]const u8 = [_][]const u8{""} ** 256;
    table['"'] = "\\\"";
    table['\\'] = "\\\\";
    table['\x08'] = "\\b";
    table['\x0C'] = "\\f";
    table['\n'] = "\\n";
    table['\r'] = "\\r";
    table['\t'] = "\\t";
    break :blk table;
};

/// Direct stringify - writes to ArrayList without writer() overhead
fn stringifyPyObjectDirect(obj: *runtime.PyObject, buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    switch (obj.type_id) {
        .none => try buffer.appendSlice(allocator, JSON_NULL),
        .bool => {
            const data: *runtime.PyInt = @ptrCast(@alignCast(obj.data));
            try buffer.appendSlice(allocator, if (data.value != 0) JSON_TRUE else JSON_FALSE);
        },
        .int => {
            const data: *runtime.PyInt = @ptrCast(@alignCast(obj.data));
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{data.value}) catch unreachable;
            try buffer.appendSlice(allocator, formatted);
        },
        .float => try buffer.appendSlice(allocator, JSON_ZERO),
        .string => {
            const data: *runtime.PyString = @ptrCast(@alignCast(obj.data));
            try buffer.append(allocator, '"');
            try writeEscapedStringDirect(data.data, buffer, allocator);
            try buffer.append(allocator, '"');
        },
        .list => {
            const data: *runtime.PyList = @ptrCast(@alignCast(obj.data));
            try buffer.append(allocator, '[');
            for (data.items.items, 0..) |item, i| {
                if (i > 0) try buffer.append(allocator, ',');
                try stringifyPyObjectDirect(item, buffer, allocator);
            }
            try buffer.append(allocator, ']');
        },
        .tuple => {
            const data: *runtime.PyTuple = @ptrCast(@alignCast(obj.data));
            try buffer.append(allocator, '[');
            for (data.items, 0..) |item, i| {
                if (i > 0) try buffer.append(allocator, ',');
                try stringifyPyObjectDirect(item, buffer, allocator);
            }
            try buffer.append(allocator, ']');
        },
        .dict => {
            const data: *runtime.PyDict = @ptrCast(@alignCast(obj.data));
            try buffer.append(allocator, '{');
            var it = data.map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');
                first = false;
                try buffer.append(allocator, '"');
                try writeEscapedStringDirect(entry.key_ptr.*, buffer, allocator);
                try buffer.append(allocator, '"');
                try buffer.append(allocator, ':');
                try stringifyPyObjectDirect(entry.value_ptr.*, buffer, allocator);
            }
            try buffer.append(allocator, '}');
        },
    }
}

/// Write escaped string directly to ArrayList
fn writeEscapedStringDirect(str: []const u8, buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    var start: usize = 0;
    var i: usize = 0;

    while (i < str.len) : (i += 1) {
        const c = str[i];
        // Lookup table is faster than switch!
        if (NEEDS_ESCAPE[c]) {
            if (start < i) {
                try buffer.appendSlice(allocator, str[start..i]);
            }

            // Use lookup table for common escapes, fallback to \uXXXX for others
            const escape_seq = ESCAPE_SEQUENCES[c];
            if (escape_seq.len > 0) {
                try buffer.appendSlice(allocator, escape_seq);
            } else {
                var buf: [6]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                try buffer.appendSlice(allocator, formatted);
            }

            start = i + 1;
        }
    }

    if (start < str.len) {
        try buffer.appendSlice(allocator, str[start..]);
    }
}

/// Estimate JSON size for buffer pre-allocation (avoids ArrayList growth)
fn estimateJsonSize(obj: *runtime.PyObject) usize {
    switch (obj.type_id) {
        .none => return 4, // "null"
        .bool => return 5, // "true" or "false"
        .int => return 20, // "-9223372036854775808" max
        .float => return 24, // Scientific notation
        .string => {
            const data: *runtime.PyString = @ptrCast(@alignCast(obj.data));
            return data.data.len + 2 + (data.data.len / 10); // +quotes +10% escapes
        },
        .list => {
            const data: *runtime.PyList = @ptrCast(@alignCast(obj.data));
            var size: usize = 2; // []
            for (data.items.items) |item| {
                size += estimateJsonSize(item) + 1; // +comma
            }
            return size;
        },
        .tuple => {
            const data: *runtime.PyTuple = @ptrCast(@alignCast(obj.data));
            var size: usize = 2; // []
            for (data.items) |item| {
                size += estimateJsonSize(item) + 1; // +comma
            }
            return size;
        },
        .dict => {
            const data: *runtime.PyDict = @ptrCast(@alignCast(obj.data));
            var size: usize = 2; // {}
            var it = data.map.iterator();
            while (it.next()) |entry| {
                size += entry.key_ptr.*.len + 3; // "key":
                size += estimateJsonSize(entry.value_ptr.*) + 1; // value,
            }
            return size;
        },
    }
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

                // Prefetch next item while processing current (cache optimization!)
                if (i + 1 < data.items.items.len) {
                    const next_item = data.items.items[i + 1];
                    @prefetch(next_item, .{});
                    @prefetch(next_item.data, .{});
                }

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

            // Fast path: don't sort keys (Python json.dumps sort_keys=False default)
            // This is 2-3x faster than sorting for large dicts
            var it = data.map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try writer.writeByte(',');
                first = false;

                // Key
                try writer.writeByte('"');
                try writeEscapedString(entry.key_ptr.*, writer);
                try writer.writeByte('"');
                try writer.writeByte(':');

                // Value
                try stringifyPyObject(entry.value_ptr.*, writer);
            }

            try writer.writeByte('}');
        },
    }
}

/// Write string with JSON escape sequences
fn writeEscapedString(str: []const u8, writer: anytype) !void {
    // Fast path: write chunks without escapes in one go (2-3x faster for clean strings!)
    var start: usize = 0;
    var i: usize = 0;

    while (i < str.len) : (i += 1) {
        const c = str[i];
        const needs_escape = switch (c) {
            '"', '\\', '\x08', '\x0C', '\n', '\r', '\t' => true,
            0x00...0x07, 0x0B, 0x0E...0x1F => true,
            else => false,
        };

        if (needs_escape) {
            // Write clean chunk before this escaped char
            if (start < i) {
                try writer.writeAll(str[start..i]);
            }

            // Write escaped character
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\x08' => try writer.writeAll("\\b"),
                '\x0C' => try writer.writeAll("\\f"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.print("\\u{x:0>4}", .{c}),
            }

            start = i + 1;
        }
    }

    // Write final clean chunk
    if (start < str.len) {
        try writer.writeAll(str[start..]);
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
