/// value_builder - Value Building from Format Strings
/// Mirrors parts of cpython/Python/modsupport.c related to Py_BuildValue
///
/// Provides functions for building Python objects from C-style format strings
/// and variadic arguments. This is used for creating Python objects from native values.

const std = @import("std");

/// Built value types
pub const BuiltValue = union(enum) {
    none: void,
    bool_true: void,
    bool_false: void,
    int: i64,
    uint: u64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    unicode: []const u8,
    object: *anyopaque,
    tuple: []BuiltValue,
    list: []BuiltValue,
    dict: []KeyValue,

    pub const KeyValue = struct {
        key: BuiltValue,
        value: BuiltValue,
    };
};

/// Format characters for Py_BuildValue
pub const FormatChar = enum(u8) {
    // None
    None = 'N',

    // Boolean
    bool_p = 'p',

    // Integer types
    byte = 'b',
    Byte = 'B',
    short = 'h',
    ushort = 'H',
    int = 'i',
    uint = 'I',
    long = 'l',
    ulong = 'k',
    longlong = 'L',
    ulonglong = 'K',
    ssize = 'n',

    // Float types
    float = 'f',
    double = 'd',
    complex = 'D',

    // Character types
    char = 'c',
    unicode_char = 'C',

    // String types
    string = 's',
    string_or_none = 'z',
    string_bytes = 'y',
    unicode = 'u',
    unicode_obj = 'U',
    bytes_obj = 'S',
    bytearray = 'Y',

    // Object
    object = 'O',

    // Container start/end
    tuple_start = '(',
    tuple_end = ')',
    list_start = '[',
    list_end = ']',
    dict_start = '{',
    dict_end = '}',

    _,
};

/// Error type for value building
pub const BuildError = error{
    InvalidFormat,
    NullObject,
    OutOfMemory,
    TypeError,
};

/// Iterator over variadic arguments (stub - would use actual va_list in C)
pub const ArgIterator = struct {
    int_args: []const i64,
    long_args: []const i64,
    ulong_args: []const u64,
    double_args: []const f64,
    string_args: []const []const u8,
    object_args: []const *anyopaque,
    int_pos: usize = 0,
    long_pos: usize = 0,
    ulong_pos: usize = 0,
    double_pos: usize = 0,
    string_pos: usize = 0,
    object_pos: usize = 0,

    const Self = @This();

    pub fn initEmpty() Self {
        return .{
            .int_args = &.{},
            .long_args = &.{},
            .ulong_args = &.{},
            .double_args = &.{},
            .string_args = &.{},
            .object_args = &.{},
        };
    }

    pub fn nextInt(self: *Self) ?i64 {
        if (self.int_pos < self.int_args.len) {
            const val = self.int_args[self.int_pos];
            self.int_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextLong(self: *Self) ?i64 {
        if (self.long_pos < self.long_args.len) {
            const val = self.long_args[self.long_pos];
            self.long_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextULong(self: *Self) ?u64 {
        if (self.ulong_pos < self.ulong_args.len) {
            const val = self.ulong_args[self.ulong_pos];
            self.ulong_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextDouble(self: *Self) ?f64 {
        if (self.double_pos < self.double_args.len) {
            const val = self.double_args[self.double_pos];
            self.double_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextString(self: *Self) ?[]const u8 {
        if (self.string_pos < self.string_args.len) {
            const val = self.string_args[self.string_pos];
            self.string_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextObject(self: *Self) ?*anyopaque {
        if (self.object_pos < self.object_args.len) {
            const val = self.object_args[self.object_pos];
            self.object_pos += 1;
            return val;
        }
        return null;
    }
};

/// Value builder state
pub const ValueBuilder = struct {
    format: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,
    values: std.ArrayList(BuiltValue),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, format: []const u8) Self {
        return .{
            .format = format,
            .pos = 0,
            .allocator = allocator,
            .values = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit(self.allocator);
    }

    fn peek(self: *const Self) ?u8 {
        if (self.pos < self.format.len) {
            return self.format[self.pos];
        }
        return null;
    }

    fn advance(self: *Self) void {
        if (self.pos < self.format.len) {
            self.pos += 1;
        }
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.format.len) {
            const c = self.format[self.pos];
            if (c != ' ' and c != '\t' and c != ',' and c != ':') break;
            self.pos += 1;
        }
    }

    /// Count items until endchar
    fn countFormat(self: *Self, endchar: u8) BuildError!usize {
        var count: usize = 0;
        var level: usize = 0;
        const start = self.pos;

        while (self.pos < self.format.len) {
            const c = self.format[self.pos];

            if (level == 0 and c == endchar) {
                self.pos = start;
                return count;
            }

            switch (c) {
                '(', '[', '{' => {
                    if (level == 0) count += 1;
                    level += 1;
                },
                ')', ']', '}' => {
                    if (level == 0) {
                        self.pos = start;
                        return BuildError.InvalidFormat;
                    }
                    level -= 1;
                },
                '#', '&', ',', ':', ' ', '\t' => {},
                else => {
                    if (level == 0) count += 1;
                },
            }
            self.pos += 1;
        }

        self.pos = start;
        return BuildError.InvalidFormat;
    }

    /// Build a single value from format and arguments
    pub fn buildOne(self: *Self, args: *ArgIterator) BuildError!?BuiltValue {
        self.skipWhitespace();
        const c = self.peek() orelse return null;

        switch (c) {
            ')', ']', '}' => return null,
            '(' => {
                const result = try self.buildTuple(args);
                return result;
            },
            '[' => {
                const result = try self.buildList(args);
                return result;
            },
            '{' => {
                const result = try self.buildDict(args);
                return result;
            },
            else => {
                self.advance();
                return self.buildSimple(c, args);
            },
        }
    }

    fn buildSimple(self: *Self, c: u8, args: *ArgIterator) BuildError!BuiltValue {
        _ = self;
        return switch (c) {
            'N' => BuiltValue{ .none = {} },
            'p' => {
                const val = args.nextInt() orelse return BuildError.InvalidFormat;
                return if (val != 0) BuiltValue{ .bool_true = {} } else BuiltValue{ .bool_false = {} };
            },
            'b', 'B', 'h', 'H', 'i', 'I', 'n' => {
                const val = args.nextInt() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .int = val };
            },
            'l', 'L' => {
                const val = args.nextLong() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .int = val };
            },
            'k', 'K' => {
                const val = args.nextULong() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .uint = val };
            },
            'f', 'd' => {
                const val = args.nextDouble() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .float = val };
            },
            'c', 'C' => {
                const val = args.nextInt() orelse return BuildError.InvalidFormat;
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(@intCast(val), &buf) catch return BuildError.InvalidFormat;
                return BuiltValue{ .string = buf[0..len] };
            },
            's', 'z' => {
                const str = args.nextString() orelse {
                    if (c == 'z') return BuiltValue{ .none = {} };
                    return BuildError.InvalidFormat;
                };
                return BuiltValue{ .string = str };
            },
            'y' => {
                const str = args.nextString() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .bytes = str };
            },
            'u', 'U' => {
                const str = args.nextString() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .unicode = str };
            },
            'S' => {
                const str = args.nextString() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .bytes = str };
            },
            'O' => {
                const obj = args.nextObject() orelse return BuildError.NullObject;
                return BuiltValue{ .object = obj };
            },
            else => BuildError.InvalidFormat,
        };
    }

    fn buildTuple(self: *Self, args: *ArgIterator) BuildError!BuiltValue {
        self.advance(); // skip '('
        const count = try self.countFormat(')');

        var items: std.ArrayList(BuiltValue) = .{};
        errdefer items.deinit(self.allocator);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const value = try self.buildOne(args) orelse break;
            items.append(self.allocator, value) catch return BuildError.OutOfMemory;
        }

        self.skipWhitespace();
        if (self.peek() == ')') self.advance();

        return BuiltValue{ .tuple = items.toOwnedSlice(self.allocator) catch return BuildError.OutOfMemory };
    }

    fn buildList(self: *Self, args: *ArgIterator) BuildError!BuiltValue {
        self.advance(); // skip '['
        const count = try self.countFormat(']');

        var items: std.ArrayList(BuiltValue) = .{};
        errdefer items.deinit(self.allocator);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const value = try self.buildOne(args) orelse break;
            items.append(self.allocator, value) catch return BuildError.OutOfMemory;
        }

        self.skipWhitespace();
        if (self.peek() == ']') self.advance();

        return BuiltValue{ .list = items.toOwnedSlice(self.allocator) catch return BuildError.OutOfMemory };
    }

    fn buildDict(self: *Self, args: *ArgIterator) BuildError!BuiltValue {
        self.advance(); // skip '{'
        const count = try self.countFormat('}');

        if (count % 2 != 0) {
            return BuildError.InvalidFormat;
        }

        var items: std.ArrayList(BuiltValue.KeyValue) = .{};
        errdefer items.deinit(self.allocator);

        var i: usize = 0;
        while (i < count) : (i += 2) {
            const key = try self.buildOne(args) orelse break;
            const value = try self.buildOne(args) orelse return BuildError.InvalidFormat;
            items.append(self.allocator, .{ .key = key, .value = value }) catch return BuildError.OutOfMemory;
        }

        self.skipWhitespace();
        if (self.peek() == '}') self.advance();

        return BuiltValue{ .dict = items.toOwnedSlice(self.allocator) catch return BuildError.OutOfMemory };
    }

    /// Build all values from format
    pub fn buildAll(self: *Self, args: *ArgIterator) BuildError![]BuiltValue {
        while (try self.buildOne(args)) |value| {
            self.values.append(self.allocator, value) catch return BuildError.OutOfMemory;
        }
        return self.values.toOwnedSlice(self.allocator) catch return BuildError.OutOfMemory;
    }
};

// Tests
test "value builder simple" {
    const allocator = std.testing.allocator;
    var builder = ValueBuilder.init(allocator, "i");
    defer builder.deinit();

    var args = ArgIterator{
        .int_args = &[_]i64{42},
        .long_args = &.{},
        .ulong_args = &.{},
        .double_args = &.{},
        .string_args = &.{},
        .object_args = &.{},
    };

    const value = try builder.buildOne(&args);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(i64, 42), value.?.int);
}

test "value builder tuple" {
    const allocator = std.testing.allocator;
    var builder = ValueBuilder.init(allocator, "(ii)");
    defer builder.deinit();

    var args = ArgIterator{
        .int_args = &[_]i64{ 1, 2 },
        .long_args = &.{},
        .ulong_args = &.{},
        .double_args = &.{},
        .string_args = &.{},
        .object_args = &.{},
    };

    const value = try builder.buildOne(&args);
    try std.testing.expect(value != null);
    const tuple = value.?.tuple;
    defer allocator.free(tuple);
    try std.testing.expectEqual(@as(usize, 2), tuple.len);
}
