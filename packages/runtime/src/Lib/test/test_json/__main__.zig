//! test.test_json - JSON encoding/decoding tests
const std = @import("std");

pub const JSONValue = union(enum) {
    null_val,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    array_val: std.ArrayList(JSONValue),
    object_val: std.StringHashMap(JSONValue),
};

pub const JSONEncoder = struct {
    indent: ?usize = null,
    sort_keys: bool = false,
    
    pub fn encode(self: @This(), value: JSONValue, writer: anytype) !void {
        _ = self;
        switch (value) {
            .null_val => try writer.writeAll("null"),
            .bool_val => |b| try writer.writeAll(if (b) "true" else "false"),
            .int_val => |i| try writer.print("{d}", .{i}),
            .float_val => |f| try writer.print("{d}", .{f}),
            .string_val => |s| {
                try writer.writeByte('"');
                try writer.writeAll(s);
                try writer.writeByte('"');
            },
            .array_val => |arr| {
                try writer.writeByte('[');
                for (arr.items, 0..) |item, idx| {
                    if (idx > 0) try writer.writeAll(", ");
                    try self.encode(item, writer);
                }
                try writer.writeByte(']');
            },
            .object_val => |obj| {
                try writer.writeByte('{');
                var first = true;
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.print("\"{s}\": ", .{entry.key_ptr.*});
                    try self.encode(entry.value_ptr.*, writer);
                }
                try writer.writeByte('}');
            },
        }
    }
};

pub const JSONDecoder = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
    
    pub fn decode(self: @This(), input: []const u8) !JSONValue {
        var idx: usize = 0;
        return self.parseValue(input, &idx);
    }
    
    fn parseValue(self: @This(), input: []const u8, idx: *usize) !JSONValue {
        self.skipWhitespace(input, idx);
        if (idx.* >= input.len) return error.UnexpectedEnd;
        
        const c = input[idx.*];
        if (c == 'n') return self.parseNull(input, idx);
        if (c == 't' or c == 'f') return self.parseBool(input, idx);
        if (c == '"') return self.parseString(input, idx);
        if (c == '[') return self.parseArray(input, idx);
        if (c == '{') return self.parseObject(input, idx);
        if (c == '-' or (c >= '0' and c <= '9')) return self.parseNumber(input, idx);
        return error.InvalidCharacter;
    }
    
    fn skipWhitespace(_: @This(), input: []const u8, idx: *usize) void {
        while (idx.* < input.len and (input[idx.*] == ' ' or input[idx.*] == '\n' or input[idx.*] == '\t' or input[idx.*] == '\r')) {
            idx.* += 1;
        }
    }
    
    fn parseNull(_: @This(), input: []const u8, idx: *usize) !JSONValue {
        if (idx.* + 4 <= input.len and std.mem.eql(u8, input[idx.*..idx.*+4], "null")) {
            idx.* += 4;
            return .null_val;
        }
        return error.InvalidNull;
    }
    
    fn parseBool(_: @This(), input: []const u8, idx: *usize) !JSONValue {
        if (idx.* + 4 <= input.len and std.mem.eql(u8, input[idx.*..idx.*+4], "true")) {
            idx.* += 4;
            return .{ .bool_val = true };
        }
        if (idx.* + 5 <= input.len and std.mem.eql(u8, input[idx.*..idx.*+5], "false")) {
            idx.* += 5;
            return .{ .bool_val = false };
        }
        return error.InvalidBool;
    }
    
    fn parseString(_: @This(), input: []const u8, idx: *usize) !JSONValue {
        idx.* += 1; // skip opening quote
        const start = idx.*;
        while (idx.* < input.len and input[idx.*] != '"') {
            if (input[idx.*] == '\\') idx.* += 1;
            idx.* += 1;
        }
        const str = input[start..idx.*];
        idx.* += 1; // skip closing quote
        return .{ .string_val = str };
    }
    
    fn parseNumber(_: @This(), input: []const u8, idx: *usize) !JSONValue {
        const start = idx.*;
        var is_float = false;
        if (input[idx.*] == '-') idx.* += 1;
        while (idx.* < input.len and input[idx.*] >= '0' and input[idx.*] <= '9') idx.* += 1;
        if (idx.* < input.len and input[idx.*] == '.') {
            is_float = true;
            idx.* += 1;
            while (idx.* < input.len and input[idx.*] >= '0' and input[idx.*] <= '9') idx.* += 1;
        }
        const num_str = input[start..idx.*];
        if (is_float) {
            return .{ .float_val = std.fmt.parseFloat(f64, num_str) catch 0 };
        }
        return .{ .int_val = std.fmt.parseInt(i64, num_str, 10) catch 0 };
    }
    
    fn parseArray(self: @This(), input: []const u8, idx: *usize) !JSONValue {
        idx.* += 1; // skip [
        var arr = std.ArrayList(JSONValue).init(self.allocator);
        self.skipWhitespace(input, idx);
        if (idx.* < input.len and input[idx.*] == ']') {
            idx.* += 1;
            return .{ .array_val = arr };
        }
        while (true) {
            try arr.append(try self.parseValue(input, idx));
            self.skipWhitespace(input, idx);
            if (idx.* >= input.len) return error.UnexpectedEnd;
            if (input[idx.*] == ']') { idx.* += 1; break; }
            if (input[idx.*] == ',') { idx.* += 1; continue; }
            return error.ExpectedCommaOrBracket;
        }
        return .{ .array_val = arr };
    }
    
    fn parseObject(self: @This(), input: []const u8, idx: *usize) !JSONValue {
        idx.* += 1; // skip {
        var obj = std.StringHashMap(JSONValue).init(self.allocator);
        self.skipWhitespace(input, idx);
        if (idx.* < input.len and input[idx.*] == '}') {
            idx.* += 1;
            return .{ .object_val = obj };
        }
        while (true) {
            self.skipWhitespace(input, idx);
            const key = (try self.parseString(input, idx)).string_val;
            self.skipWhitespace(input, idx);
            if (input[idx.*] != ':') return error.ExpectedColon;
            idx.* += 1;
            const value = try self.parseValue(input, idx);
            try obj.put(key, value);
            self.skipWhitespace(input, idx);
            if (idx.* >= input.len) return error.UnexpectedEnd;
            if (input[idx.*] == '}') { idx.* += 1; break; }
            if (input[idx.*] == ',') { idx.* += 1; continue; }
            return error.ExpectedCommaOrBrace;
        }
        return .{ .object_val = obj };
    }
};

test "json_encode_null" {
    var buf: [100]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const encoder = JSONEncoder{};
    try encoder.encode(.null_val, stream.writer());
    try std.testing.expectEqualStrings("null", stream.getWritten());
}

test "json_encode_bool" {
    var buf: [100]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const encoder = JSONEncoder{};
    try encoder.encode(.{ .bool_val = true }, stream.writer());
    try std.testing.expectEqualStrings("true", stream.getWritten());
}

test "json_encode_int" {
    var buf: [100]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const encoder = JSONEncoder{};
    try encoder.encode(.{ .int_val = 42 }, stream.writer());
    try std.testing.expectEqualStrings("42", stream.getWritten());
}

test "json_decode_null" {
    const decoder = JSONDecoder.init(std.testing.allocator);
    const result = try decoder.decode("null");
    try std.testing.expect(result == .null_val);
}

test "json_decode_bool" {
    const decoder = JSONDecoder.init(std.testing.allocator);
    const result = try decoder.decode("true");
    try std.testing.expectEqual(true, result.bool_val);
}

test "json_decode_int" {
    const decoder = JSONDecoder.init(std.testing.allocator);
    const result = try decoder.decode("123");
    try std.testing.expectEqual(@as(i64, 123), result.int_val);
}

test "json_decode_string" {
    const decoder = JSONDecoder.init(std.testing.allocator);
    const result = try decoder.decode("\"hello\"");
    try std.testing.expectEqualStrings("hello", result.string_val);
}
