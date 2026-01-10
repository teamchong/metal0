//! test.test_json.test_decode - JSON decoder tests
const std = @import("std");

pub const JSONDecodeError = error{
    ExtraData,
    InvalidCharacter,
    UnexpectedEnd,
    InvalidEscape,
    InvalidNumber,
    InvalidString,
    InvalidArray,
    InvalidObject,
    RecursionLimit,
};

pub const Decoder = struct {
    allocator: std.mem.Allocator,
    strict: bool = true,
    parse_float: ?*const fn ([]const u8) f64 = null,
    parse_int: ?*const fn ([]const u8) i64 = null,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
    
    pub fn decode(self: @This(), s: []const u8) !Value {
        var idx: usize = 0;
        return self.parseValue(s, &idx);
    }
    
    fn parseValue(self: @This(), s: []const u8, idx: *usize) !Value {
        self.skipWhitespace(s, idx);
        if (idx.* >= s.len) return error.UnexpectedEnd;
        
        return switch (s[idx.*]) {
            'n' => self.parseNull(s, idx),
            't', 'f' => self.parseBool(s, idx),
            '"' => self.parseString(s, idx),
            '[' => self.parseArray(s, idx),
            '{' => self.parseObject(s, idx),
            '-', '0'...'9' => self.parseNumber(s, idx),
            else => error.InvalidCharacter,
        };
    }
    
    fn skipWhitespace(_: @This(), s: []const u8, idx: *usize) void {
        while (idx.* < s.len and (s[idx.*] == ' ' or s[idx.*] == '\t' or s[idx.*] == '\n' or s[idx.*] == '\r')) {
            idx.* += 1;
        }
    }
    
    fn parseNull(_: @This(), s: []const u8, idx: *usize) !Value {
        if (idx.* + 4 <= s.len and std.mem.eql(u8, s[idx.*..idx.*+4], "null")) {
            idx.* += 4;
            return .null_val;
        }
        return error.InvalidCharacter;
    }
    
    fn parseBool(_: @This(), s: []const u8, idx: *usize) !Value {
        if (idx.* + 4 <= s.len and std.mem.eql(u8, s[idx.*..idx.*+4], "true")) {
            idx.* += 4;
            return .{ .bool_val = true };
        }
        if (idx.* + 5 <= s.len and std.mem.eql(u8, s[idx.*..idx.*+5], "false")) {
            idx.* += 5;
            return .{ .bool_val = false };
        }
        return error.InvalidCharacter;
    }
    
    fn parseString(_: @This(), s: []const u8, idx: *usize) !Value {
        idx.* += 1;
        const start = idx.*;
        while (idx.* < s.len and s[idx.*] != '"') {
            if (s[idx.*] == '\\') idx.* += 1;
            idx.* += 1;
        }
        const str = s[start..idx.*];
        idx.* += 1;
        return .{ .string_val = str };
    }
    
    fn parseNumber(_: @This(), s: []const u8, idx: *usize) !Value {
        const start = idx.*;
        var is_float = false;
        if (s[idx.*] == '-') idx.* += 1;
        while (idx.* < s.len and s[idx.*] >= '0' and s[idx.*] <= '9') idx.* += 1;
        if (idx.* < s.len and s[idx.*] == '.') { is_float = true; idx.* += 1; while (idx.* < s.len and s[idx.*] >= '0' and s[idx.*] <= '9') idx.* += 1; }
        const num = s[start..idx.*];
        if (is_float) return .{ .float_val = std.fmt.parseFloat(f64, num) catch 0 };
        return .{ .int_val = std.fmt.parseInt(i64, num, 10) catch 0 };
    }
    
    fn parseArray(self: @This(), s: []const u8, idx: *usize) !Value {
        idx.* += 1;
        var arr = std.ArrayList(Value).init(self.allocator);
        self.skipWhitespace(s, idx);
        if (s[idx.*] == ']') { idx.* += 1; return .{ .array_val = arr }; }
        while (true) {
            try arr.append(try self.parseValue(s, idx));
            self.skipWhitespace(s, idx);
            if (s[idx.*] == ']') { idx.* += 1; break; }
            if (s[idx.*] == ',') { idx.* += 1; continue; }
            return error.InvalidArray;
        }
        return .{ .array_val = arr };
    }
    
    fn parseObject(self: @This(), s: []const u8, idx: *usize) !Value {
        idx.* += 1;
        var obj = std.StringHashMap(Value).init(self.allocator);
        self.skipWhitespace(s, idx);
        if (s[idx.*] == '}') { idx.* += 1; return .{ .object_val = obj }; }
        while (true) {
            self.skipWhitespace(s, idx);
            const key = (try self.parseString(s, idx)).string_val;
            self.skipWhitespace(s, idx);
            if (s[idx.*] != ':') return error.InvalidObject;
            idx.* += 1;
            try obj.put(key, try self.parseValue(s, idx));
            self.skipWhitespace(s, idx);
            if (s[idx.*] == '}') { idx.* += 1; break; }
            if (s[idx.*] == ',') { idx.* += 1; continue; }
            return error.InvalidObject;
        }
        return .{ .object_val = obj };
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

test "decode_null" {
    const dec = Decoder.init(std.testing.allocator);
    const v = try dec.decode("null");
    try std.testing.expect(v == .null_val);
}

test "decode_bool" {
    const dec = Decoder.init(std.testing.allocator);
    try std.testing.expect((try dec.decode("true")).bool_val);
    try std.testing.expect(!(try dec.decode("false")).bool_val);
}

test "decode_number" {
    const dec = Decoder.init(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 42), (try dec.decode("42")).int_val);
    try std.testing.expectEqual(@as(i64, -10), (try dec.decode("-10")).int_val);
}

test "decode_string" {
    const dec = Decoder.init(std.testing.allocator);
    try std.testing.expectEqualStrings("hello", (try dec.decode("\"hello\"")).string_val);
}
