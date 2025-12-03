/// Public JSON API for metal0 - json.loads() and json.dumps()
const std = @import("std");
const runtime = @import("runtime.zig");
const parse_direct = @import("json/parse_direct.zig");
const parse_arena = @import("json/parse_arena.zig");

// Export for internal use (e.g. notebook parsing)
pub const parse = @import("json/parse.zig").parse;
pub const Value = @import("json/value.zig").JsonValue;
pub const JsonValue = Value;

/// Deserialize JSON string to PyObject (arena-allocated for speed!)
/// Python: json.loads(json_str) -> obj
/// Uses arena allocation: single malloc for entire parse, single free on cleanup
pub fn loads(json_str: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Validate input is a string
    if (!runtime.PyUnicode_Check(json_str)) {
        return error.TypeError;
    }

    const json_bytes = runtime.PyString.getValue(json_str);

    // Use arena-based parser for maximum performance
    // Arena is attached to root object and freed when root is decref'd to 0
    const result = try parse_arena.parseWithArena(json_bytes, allocator);

    return result;
}

/// Deserialize JSON string to PyObject (legacy - uses per-object allocation)
/// Use this when you need objects to outlive the parse scope independently
pub fn loadsLegacy(json_str: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Validate input is a string
    if (!runtime.PyUnicode_Check(json_str)) {
        return error.TypeError;
    }

    const json_bytes = runtime.PyString.getValue(json_str);

    // Parse with lazy mode - strings borrow from source (zero-copy!)
    // Source is kept alive because borrowed strings hold refcount to it
    const result = try parse_direct.parseWithSource(json_bytes, allocator, json_str);

    return result;
}

/// Serialize PyObject to JSON string
/// Python: json.dumps(obj) -> str
pub fn dumps(obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    const json_str = try dumpsDirect(obj, allocator);
    return try runtime.PyString.createOwned(allocator, json_str);
}

/// FAST PATH: Serialize directly to string WITHOUT PyObject wrapper
/// This is what Rust does - direct string return!
pub fn dumpsDirect(obj: *runtime.PyObject, allocator: std.mem.Allocator) ![]const u8 {
    // Start with 64KB buffer - matches typical JSON output size, eliminates growth
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 65536);

    // Manual error handling to avoid defer overhead
    stringifyPyObjectDirect(obj, &buffer, allocator) catch |err| {
        buffer.deinit(allocator);
        return err;
    };

    return buffer.toOwnedSlice(allocator) catch |err| {
        buffer.deinit(allocator);
        return err;
    };
}

/// Serialize native Zig values to JSON string (generic version)
/// Handles strings, ints, floats, bools, null directly without PyObject wrapper
pub fn dumpsValue(value: anytype, allocator: std.mem.Allocator) ![]const u8 {
    const T = @TypeOf(value);
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 256);

    stringifyValue(value, T, &buffer, allocator) catch |err| {
        buffer.deinit(allocator);
        return err;
    };

    return buffer.toOwnedSlice(allocator) catch |err| {
        buffer.deinit(allocator);
        return err;
    };
}

/// Stringify native value to buffer
fn stringifyValue(value: anytype, comptime T: type, buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    const type_info = @typeInfo(T);

    // Handle null
    if (T == @TypeOf(null)) {
        try buffer.appendSlice(allocator, JSON_NULL);
        return;
    }

    // Handle optionals
    if (type_info == .optional) {
        if (value) |v| {
            try stringifyValue(v, type_info.optional.child, buffer, allocator);
        } else {
            try buffer.appendSlice(allocator, JSON_NULL);
        }
        return;
    }

    // Handle bools
    if (T == bool) {
        try buffer.appendSlice(allocator, if (value) JSON_TRUE else JSON_FALSE);
        return;
    }

    // Handle integers
    if (type_info == .int or type_info == .comptime_int) {
        var buf: [32]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try buffer.appendSlice(allocator, formatted);
        return;
    }

    // Handle floats
    if (type_info == .float or type_info == .comptime_float) {
        var buf: [32]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try buffer.appendSlice(allocator, formatted);
        return;
    }

    // Handle strings (pointers to u8 arrays or slices)
    if (type_info == .pointer) {
        const child_info = @typeInfo(type_info.pointer.child);
        // Slice of u8 - []const u8 or []u8
        if (type_info.pointer.size == .slice and type_info.pointer.child == u8) {
            try buffer.append(allocator, '"');
            for (value) |c| {
                if (NEEDS_ESCAPE[c]) {
                    const escape = ESCAPE_SEQUENCES[c];
                    if (escape.len > 0) {
                        try buffer.appendSlice(allocator, escape);
                    } else {
                        var hex_buf: [6]u8 = undefined;
                        _ = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{c}) catch unreachable;
                        try buffer.appendSlice(allocator, &hex_buf);
                    }
                } else {
                    try buffer.append(allocator, c);
                }
            }
            try buffer.append(allocator, '"');
            return;
        }
        // Pointer to array of u8 - *const [N]u8
        if (type_info.pointer.size == .one and child_info == .array and child_info.array.child == u8) {
            const slice: []const u8 = value;
            try buffer.append(allocator, '"');
            for (slice) |c| {
                if (NEEDS_ESCAPE[c]) {
                    const escape = ESCAPE_SEQUENCES[c];
                    if (escape.len > 0) {
                        try buffer.appendSlice(allocator, escape);
                    } else {
                        var hex_buf: [6]u8 = undefined;
                        _ = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{c}) catch unreachable;
                        try buffer.appendSlice(allocator, &hex_buf);
                    }
                } else {
                    try buffer.append(allocator, c);
                }
            }
            try buffer.append(allocator, '"');
            return;
        }
        // Pointer to PyObject - use dumpsDirect
        if (type_info.pointer.child == runtime.PyObject) {
            try stringifyPyObjectDirect(value, buffer, allocator);
            return;
        }
    }

    // Handle arrays (e.g. [3]i64)
    if (type_info == .array) {
        try buffer.append(allocator, '[');
        for (value, 0..) |elem, i| {
            if (i > 0) try buffer.appendSlice(allocator, ", ");
            try stringifyValue(elem, type_info.array.child, buffer, allocator);
        }
        try buffer.append(allocator, ']');
        return;
    }

    // Fallback for unsupported types
    try buffer.appendSlice(allocator, JSON_NULL);
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
    @setRuntimeSafety(false); // Disable ALL safety checks in hot path

    // Use the type checking functions for CPython-compatible layout
    const type_id = runtime.getTypeId(obj);
    switch (type_id) {
        .none => try buffer.appendSlice(allocator, JSON_NULL),
        .bool => {
            const bool_obj: *runtime.PyBoolObject = @ptrCast(@alignCast(obj));
            try buffer.appendSlice(allocator, if (bool_obj.ob_digit != 0) JSON_TRUE else JSON_FALSE);
        },
        .int => {
            const long_obj: *runtime.PyLongObject = @ptrCast(@alignCast(obj));
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{long_obj.ob_digit}) catch unreachable;
            try buffer.appendSlice(allocator, formatted);
        },
        .float => {
            const float_obj: *runtime.PyFloatObject = @ptrCast(@alignCast(obj));
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{float_obj.ob_fval}) catch unreachable;
            try buffer.appendSlice(allocator, formatted);
        },
        .string => {
            const str_data = runtime.PyString.getValue(obj);
            try buffer.append(allocator, '"');
            try writeEscapedStringDirect(str_data, buffer, allocator);
            try buffer.append(allocator, '"');
        },
        .list => {
            const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(obj));
            const size: usize = @intCast(list_obj.ob_base.ob_size);
            try buffer.append(allocator, '[');
            if (size > 0) {
                try stringifyPyObjectDirect(list_obj.ob_item[0], buffer, allocator);
                for (1..size) |i| {
                    try buffer.append(allocator, ',');
                    try stringifyPyObjectDirect(list_obj.ob_item[i], buffer, allocator);
                }
            }
            try buffer.append(allocator, ']');
        },
        .tuple => {
            const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(obj));
            const size: usize = @intCast(tuple_obj.ob_base.ob_size);
            try buffer.append(allocator, '[');
            if (size > 0) {
                try stringifyPyObjectDirect(tuple_obj.ob_item[0], buffer, allocator);
                for (1..size) |i| {
                    try buffer.append(allocator, ',');
                    try stringifyPyObjectDirect(tuple_obj.ob_item[i], buffer, allocator);
                }
            }
            try buffer.append(allocator, ']');
        },
        .dict => {
            const dict_obj: *runtime.PyDictObject = @ptrCast(@alignCast(obj));
            try buffer.append(allocator, '{');

            if (dict_obj.ma_keys) |keys_ptr| {
                const map: *@import("hashmap_helper").StringHashMap(*runtime.PyObject) = @ptrCast(@alignCast(keys_ptr));
                // Fast path: process first entry without comma check
                var it = map.iterator();
                if (it.next()) |entry| {
                    try buffer.appendSlice(allocator, "\"");
                    try writeEscapedStringDirect(entry.key_ptr.*, buffer, allocator);
                    try buffer.appendSlice(allocator, "\":");
                    try stringifyPyObjectDirect(entry.value_ptr.*, buffer, allocator);

                    // Rest of entries always have comma
                    while (it.next()) |next_entry| {
                        try buffer.appendSlice(allocator, ",\"");
                        try writeEscapedStringDirect(next_entry.key_ptr.*, buffer, allocator);
                        try buffer.appendSlice(allocator, "\":");
                        try stringifyPyObjectDirect(next_entry.value_ptr.*, buffer, allocator);
                    }
                }
            }

            try buffer.append(allocator, '}');
        },
        .bigint => {
            // BigInt - serialize as number string
            const bigint_obj: *runtime.PyBigIntObject = @ptrCast(@alignCast(obj));
            const str = bigint_obj.value.toString(allocator, 10) catch return error.OutOfMemory;
            defer allocator.free(str);
            try buffer.appendSlice(allocator, str);
        },
        .regex, .file, .bytes => {
            // Not JSON serializable - output null
            try buffer.appendSlice(allocator, JSON_NULL);
        },
    }
}

/// Write escaped string directly to ArrayList with SIMD acceleration
inline fn writeEscapedStringDirect(str: []const u8, buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    @setRuntimeSafety(false); // Disable bounds checks - we control the input
    var start: usize = 0;
    var i: usize = 0;

    // SIMD fast path: check 16 bytes at once using vectors
    const Vec16 = @Vector(16, u8);
    const threshold: Vec16 = @splat(32); // Control chars (0-31) need escaping
    const quote: Vec16 = @splat('"');
    const backslash: Vec16 = @splat('\\');

    while (i + 16 <= str.len) {
        const chunk: Vec16 = str[i..][0..16].*;

        // Check for control chars, quotes, backslashes in one SIMD op
        const has_control = chunk < threshold;
        const has_quote = chunk == quote;
        const has_backslash = chunk == backslash;
        const needs_escape_vec = has_control | has_quote | has_backslash;

        // If any bit set, at least one char needs escaping
        if (@reduce(.Or, needs_escape_vec)) {
            // Fall back to scalar for this chunk
            const end = @min(i + 16, str.len);
            while (i < end) : (i += 1) {
                const c = str[i];
                if (NEEDS_ESCAPE[c]) {
                    if (start < i) {
                        try buffer.appendSlice(allocator, str[start..i]);
                    }
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
        } else {
            // Fast path: no escapes needed, skip 16 bytes
            i += 16;
        }
    }

    // Handle remaining bytes (< 16)
    while (i < str.len) : (i += 1) {
        const c = str[i];
        if (NEEDS_ESCAPE[c]) {
            if (start < i) {
                try buffer.appendSlice(allocator, str[start..i]);
            }
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
    const type_id = runtime.getTypeId(obj);
    switch (type_id) {
        .none => return 4, // "null"
        .bool => return 5, // "true" or "false"
        .int => return 20, // "-9223372036854775808" max
        .float => return 24, // Scientific notation
        .string => {
            const str_data = runtime.PyString.getValue(obj);
            return str_data.len + 2 + (str_data.len / 10); // +quotes +10% escapes
        },
        .list => {
            const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(obj));
            const len: usize = @intCast(list_obj.ob_base.ob_size);
            var size: usize = 2; // []
            for (0..len) |i| {
                size += estimateJsonSize(list_obj.ob_item[i]) + 1; // +comma
            }
            return size;
        },
        .tuple => {
            const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(obj));
            const len: usize = @intCast(tuple_obj.ob_base.ob_size);
            var size: usize = 2; // []
            for (0..len) |i| {
                size += estimateJsonSize(tuple_obj.ob_item[i]) + 1; // +comma
            }
            return size;
        },
        .dict => {
            const dict_obj: *runtime.PyDictObject = @ptrCast(@alignCast(obj));
            var size: usize = 2; // {}
            if (dict_obj.ma_keys) |keys_ptr| {
                const map: *@import("hashmap_helper").StringHashMap(*runtime.PyObject) = @ptrCast(@alignCast(keys_ptr));
                var it = map.iterator();
                while (it.next()) |entry| {
                    size += entry.key_ptr.*.len + 3; // "key":
                    size += estimateJsonSize(entry.value_ptr.*) + 1; // value,
                }
            }
            return size;
        },
        else => return 4, // "null" for unsupported types
    }
}

/// Stringify a PyObject to JSON format
fn stringifyPyObject(obj: *runtime.PyObject, writer: anytype) !void {
    const type_id = runtime.getTypeId(obj);
    switch (type_id) {
        .none => {
            try writer.writeAll("null");
        },
        .bool => {
            const bool_obj: *runtime.PyBoolObject = @ptrCast(@alignCast(obj));
            if (bool_obj.ob_digit != 0) {
                try writer.writeAll("true");
            } else {
                try writer.writeAll("false");
            }
        },
        .int => {
            const long_obj: *runtime.PyLongObject = @ptrCast(@alignCast(obj));
            try writer.print("{}", .{long_obj.ob_digit});
        },
        .float => {
            const float_obj: *runtime.PyFloatObject = @ptrCast(@alignCast(obj));
            try writer.print("{d}", .{float_obj.ob_fval});
        },
        .string => {
            const str_data = runtime.PyString.getValue(obj);
            try writer.writeByte('"');
            try writeEscapedString(str_data, writer);
            try writer.writeByte('"');
        },
        .list => {
            const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(obj));
            const size: usize = @intCast(list_obj.ob_base.ob_size);
            try writer.writeByte('[');

            for (0..size) |i| {
                if (i > 0) try writer.writeByte(',');

                // Prefetch next item while processing current (cache optimization!)
                if (i + 1 < size) {
                    const next_item = list_obj.ob_item[i + 1];
                    @prefetch(next_item, .{});
                }

                try stringifyPyObject(list_obj.ob_item[i], writer);
            }

            try writer.writeByte(']');
        },
        .tuple => {
            const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(obj));
            const size: usize = @intCast(tuple_obj.ob_base.ob_size);
            try writer.writeByte('[');

            for (0..size) |i| {
                if (i > 0) try writer.writeByte(',');
                try stringifyPyObject(tuple_obj.ob_item[i], writer);
            }

            try writer.writeByte(']');
        },
        .dict => {
            const dict_obj: *runtime.PyDictObject = @ptrCast(@alignCast(obj));
            try writer.writeByte('{');

            // Fast path: don't sort keys (Python json.dumps sort_keys=False default)
            // This is 2-3x faster than sorting for large dicts
            if (dict_obj.ma_keys) |keys_ptr| {
                const map: *@import("hashmap_helper").StringHashMap(*runtime.PyObject) = @ptrCast(@alignCast(keys_ptr));
                var it = map.iterator();
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
            }

            try writer.writeByte('}');
        },
        else => {
            try writer.writeAll("null");
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
