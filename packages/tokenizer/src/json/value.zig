/// JSON value representation - optimized for direct PyObject conversion
const std = @import("std");
const runtime = @import("../runtime.zig");

/// Minimal intermediate representation - converts to PyObject ASAP
/// This is only used during parsing to build nested structures
pub const JsonValue = union(enum) {
    null_value,
    bool_value: bool,
    number_int: i64,
    number_float: f64,
    string: []const u8, // Points into source JSON (zero-copy)
    array: std.ArrayList(JsonValue),
    object: std.StringHashMap(JsonValue),

    /// Convert JsonValue to PyObject - main conversion point
    pub fn toPyObject(self: *const JsonValue, allocator: std.mem.Allocator) !*runtime.PyObject {
        switch (self.*) {
            .null_value => {
                // Create PyObject for None
                const none = try allocator.create(runtime.PyObject);
                none.* = .{
                    .ref_count = 1,
                    .type_id = .none,
                    .data = undefined,
                };
                return none;
            },
            .bool_value => |b| {
                // Create PyObject for bool
                const bool_obj = try allocator.create(runtime.PyObject);
                bool_obj.* = .{
                    .ref_count = 1,
                    .type_id = .bool,
                    .data = undefined,
                };
                // Store bool as int (0 or 1)
                const data = try allocator.create(runtime.PyInt);
                data.* = .{ .value = if (b) 1 else 0 };
                bool_obj.data = @ptrCast(data);
                return bool_obj;
            },
            .number_int => |n| {
                return try runtime.PyInt.create(allocator, n);
            },
            .number_float => |f| {
                // For now, store floats as ints (truncated)
                // TODO: Add PyFloat type when needed
                return try runtime.PyInt.create(allocator, @intFromFloat(f));
            },
            .string => |s| {
                // PyString.create will dupe the string, so just pass it through
                return try runtime.PyString.create(allocator, s);
            },
            .array => |arr| {
                const list = try runtime.PyList.create(allocator);
                const list_data: *runtime.PyList = @ptrCast(@alignCast(list.data));

                for (arr.items) |*item| {
                    const py_item = try item.toPyObject(allocator);
                    try list_data.items.append(allocator, py_item);
                }
                return list;
            },
            .object => |obj| {
                const dict = try runtime.PyDict.create(allocator);

                var it = obj.iterator();
                while (it.next()) |entry| {
                    const py_value = try entry.value_ptr.toPyObject(allocator);
                    try runtime.PyDict.set(dict, entry.key_ptr.*, py_value);
                    // Note: PyDict.set takes ownership, no decref needed
                }
                return dict;
            },
        }
    }

    /// Free resources for JsonValue
    /// Note: This is used when conversion to PyObject fails or for temporary values
    pub fn deinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| {
                // Free owned string data
                allocator.free(s);
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(allocator);
                }
                arr.deinit(allocator);
            },
            .object => |*obj| {
                // Free keys and values
                var it = obj.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                obj.deinit();
            },
            else => {},
        }
    }

    /// Shallow deinit - only free containers, not contents (used after toPyObject)
    pub fn shallowDeinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |*arr| arr.deinit(allocator),
            .object => |*obj| obj.deinit(),
            else => {},
        }
    }
};

/// Check if character is JSON whitespace
pub inline fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

/// Skip whitespace and return new position
pub fn skipWhitespace(data: []const u8, pos: usize) usize {
    var i = pos;
    while (i < data.len and isWhitespace(data[i])) : (i += 1) {}
    return i;
}

/// Check if we've reached end of input
pub inline fn isEof(data: []const u8, pos: usize) bool {
    return pos >= data.len;
}

/// Peek at current character without consuming
pub inline fn peek(data: []const u8, pos: usize) ?u8 {
    if (pos >= data.len) return null;
    return data[pos];
}

/// Consume current character and advance
pub inline fn consume(data: []const u8, pos: usize) struct { char: u8, next_pos: usize } {
    std.debug.assert(pos < data.len);
    return .{ .char = data[pos], .next_pos = pos + 1 };
}

/// Expect a specific character at current position
pub fn expect(data: []const u8, pos: usize, expected: u8) bool {
    if (pos >= data.len) return false;
    return data[pos] == expected;
}
