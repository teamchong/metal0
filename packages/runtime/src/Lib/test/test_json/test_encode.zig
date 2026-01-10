//! test.test_json.test_encode - JSON encoder tests
const std = @import("std");

pub const Encoder = struct {
    ensure_ascii: bool = true,
    check_circular: bool = true,
    allow_nan: bool = false,
    sort_keys: bool = false,
    indent: ?usize = null,
    separators: struct { item: []const u8 = ", ", key: []const u8 = ": " } = .{},
    
    pub fn encode(self: @This(), value: Value, writer: anytype) !void {
        switch (value) {
            .null_val => try writer.writeAll("null"),
            .bool_val => |b| try writer.writeAll(if (b) "true" else "false"),
            .int_val => |i| try writer.print("{d}", .{i}),
            .float_val => |f| {
                if (std.math.isNan(f)) {
                    if (self.allow_nan) try writer.writeAll("NaN") else return error.ValueError;
                } else if (std.math.isInf(f)) {
                    if (self.allow_nan) try writer.writeAll(if (f > 0) "Infinity" else "-Infinity") else return error.ValueError;
                } else {
                    try writer.print("{d}", .{f});
                }
            },
            .string_val => |s| {
                try writer.writeByte('"');
                for (s) |c| {
                    switch (c) {
                        '"' => try writer.writeAll("\\\""),
                        '\\' => try writer.writeAll("\\\\"),
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        else => try writer.writeByte(c),
                    }
                }
                try writer.writeByte('"');
            },
            .array_val => |arr| {
                try writer.writeByte('[');
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(self.separators.item);
                    try self.encode(item, writer);
                }
                try writer.writeByte(']');
            },
            .object_val => |obj| {
                try writer.writeByte('{');
                var first = true;
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (!first) try writer.writeAll(self.separators.item);
                    first = false;
                    try writer.print("\"{s}\"{s}", .{entry.key_ptr.*, self.separators.key});
                    try self.encode(entry.value_ptr.*, writer);
                }
                try writer.writeByte('}');
            },
        }
    }
};

pub const Value = union(enum) {
    null_val,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    array_val: std.ArrayList(Value),
    object_val: std.StringHashMap(Value),
};

pub fn dumps(allocator: std.mem.Allocator, value: Value) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    const encoder = Encoder{};
    try encoder.encode(value, list.writer());
    return list.toOwnedSlice();
}

test "encode_null" {
    var buf: [10]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const enc = Encoder{};
    try enc.encode(.null_val, stream.writer());
    try std.testing.expectEqualStrings("null", stream.getWritten());
}

test "encode_bool" {
    var buf: [10]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const enc = Encoder{};
    try enc.encode(.{ .bool_val = true }, stream.writer());
    try std.testing.expectEqualStrings("true", stream.getWritten());
}

test "encode_string_escape" {
    var buf: [50]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const enc = Encoder{};
    try enc.encode(.{ .string_val = "a\nb" }, stream.writer());
    try std.testing.expectEqualStrings("\"a\\nb\"", stream.getWritten());
}
