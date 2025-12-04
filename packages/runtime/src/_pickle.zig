/// _pickle - C accelerator module for pickle
/// Python object serialization
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Pickle protocol versions
pub const HIGHEST_PROTOCOL: u8 = 5;
pub const DEFAULT_PROTOCOL: u8 = 4;

/// Pickle opcodes
pub const Opcode = enum(u8) {
    // Protocol 0 (text mode)
    MARK = '(',
    STOP = '.',
    POP = '0',
    POP_MARK = '1',
    DUP = '2',
    FLOAT = 'F',
    INT = 'I',
    LONG = 'L',
    NONE = 'N',
    REDUCE = 'R',
    STRING = 'S',
    UNICODE = 'V',
    APPEND = 'a',
    BUILD = 'b',
    GLOBAL = 'c',
    DICT = 'd',
    EMPTY_DICT = '}',
    APPENDS = 'e',
    GET = 'g',
    BINGET = 'h',
    LONG_BINGET = 'j',
    LIST = 'l',
    EMPTY_LIST = ']',
    OBJ = 'o',
    PUT = 'p',
    BINPUT = 'q',
    LONG_BINPUT = 'r',
    SETITEM = 's',
    TUPLE = 't',
    EMPTY_TUPLE = ')',
    SETITEMS = 'u',

    // Protocol 1 (binary mode)
    BINFLOAT = 'G',
    BININT = 'J',
    BININT1 = 'K',
    BININT2 = 'M',
    BINSTRING = 'T',
    SHORT_BINSTRING = 'U',

    // Protocol 2
    PROTO = 0x80,
    NEWOBJ = 0x81,
    TUPLE1 = 0x85,
    TUPLE2 = 0x86,
    TUPLE3 = 0x87,
    NEWTRUE = 0x88,
    NEWFALSE = 0x89,
    LONG1 = 0x8a,
    LONG4 = 0x8b,

    // Protocol 3
    BINBYTES = 'B',
    SHORT_BINBYTES = 'C',

    // Protocol 4
    SHORT_BINUNICODE = 0x8c,
    BINUNICODE8 = 0x8d,
    BINBYTES8 = 0x8e,
    EMPTY_SET = 0x8f,
    ADDITEMS = 0x90,
    FROZENSET = 0x91,
    MEMOIZE = 0x94,
    FRAME = 0x95,

    // Protocol 5
    BYTEARRAY8 = 0x96,
    NEXT_BUFFER = 0x97,
    READONLY_BUFFER = 0x98,
};

/// Pickler - serializes Python objects
pub fn Pickler(comptime protocol: u8) type {
    return struct {
        buffer: std.ArrayList(u8),
        allocator: Allocator,
        memo: std.AutoHashMap(usize, u32),
        memo_count: u32,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .buffer = std.ArrayList(u8).init(allocator),
                .allocator = allocator,
                .memo = std.AutoHashMap(usize, u32).init(allocator),
                .memo_count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
            self.memo.deinit();
        }

        pub fn getBytes(self: Self) []const u8 {
            return self.buffer.items;
        }

        pub fn clear(self: *Self) void {
            self.buffer.clearRetainingCapacity();
            self.memo.clearRetainingCapacity();
            self.memo_count = 0;
        }

        fn write(self: *Self, data: []const u8) !void {
            try self.buffer.appendSlice(self.allocator, data);
        }

        fn writeByte(self: *Self, byte: u8) !void {
            try self.buffer.append(self.allocator, byte);
        }

        /// Write protocol header
        pub fn writeHeader(self: *Self) !void {
            if (protocol >= 2) {
                try self.writeByte(@intFromEnum(Opcode.PROTO));
                try self.writeByte(protocol);
            }
        }

        /// Pickle None
        pub fn dumpNone(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.NONE));
        }

        /// Pickle boolean
        pub fn dumpBool(self: *Self, value: bool) !void {
            if (protocol >= 2) {
                try self.writeByte(if (value) @intFromEnum(Opcode.NEWTRUE) else @intFromEnum(Opcode.NEWFALSE));
            } else {
                try self.writeByte(@intFromEnum(Opcode.INT));
                try self.write(if (value) "01\n" else "00\n");
            }
        }

        /// Pickle integer
        pub fn dumpInt(self: *Self, value: i64) !void {
            if (protocol >= 2) {
                if (value >= 0 and value <= 0xff) {
                    try self.writeByte(@intFromEnum(Opcode.BININT1));
                    try self.writeByte(@intCast(value));
                } else if (value >= 0 and value <= 0xffff) {
                    try self.writeByte(@intFromEnum(Opcode.BININT2));
                    const v: u16 = @intCast(value);
                    try self.write(&std.mem.toBytes(v));
                } else if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
                    try self.writeByte(@intFromEnum(Opcode.BININT));
                    const v: i32 = @intCast(value);
                    try self.write(&std.mem.toBytes(v));
                } else {
                    // LONG1 for larger integers
                    try self.writeByte(@intFromEnum(Opcode.LONG1));
                    try self.write(&std.mem.toBytes(value));
                }
            } else {
                try self.writeByte(@intFromEnum(Opcode.INT));
                var buf: [32]u8 = undefined;
                const len = std.fmt.formatIntBuf(&buf, value, 10, .lower, .{});
                try self.write(buf[0..len]);
                try self.writeByte('\n');
            }
        }

        /// Pickle float
        pub fn dumpFloat(self: *Self, value: f64) !void {
            if (protocol >= 1) {
                try self.writeByte(@intFromEnum(Opcode.BINFLOAT));
                // Big-endian double
                const bits: u64 = @bitCast(value);
                var bytes: [8]u8 = undefined;
                std.mem.writeInt(u64, &bytes, bits, .big);
                try self.write(&bytes);
            } else {
                try self.writeByte(@intFromEnum(Opcode.FLOAT));
                var buf: [32]u8 = undefined;
                const result = std.fmt.bufPrint(&buf, "{d}\n", .{value}) catch return error.FormatError;
                try self.write(result);
            }
        }

        /// Pickle bytes
        pub fn dumpBytes(self: *Self, data: []const u8) !void {
            if (protocol >= 3) {
                if (data.len <= 0xff) {
                    try self.writeByte(@intFromEnum(Opcode.SHORT_BINBYTES));
                    try self.writeByte(@intCast(data.len));
                } else {
                    try self.writeByte(@intFromEnum(Opcode.BINBYTES));
                    const len: u32 = @intCast(data.len);
                    try self.write(&std.mem.toBytes(len));
                }
                try self.write(data);
            } else if (protocol >= 1) {
                if (data.len <= 0xff) {
                    try self.writeByte(@intFromEnum(Opcode.SHORT_BINSTRING));
                    try self.writeByte(@intCast(data.len));
                } else {
                    try self.writeByte(@intFromEnum(Opcode.BINSTRING));
                    const len: u32 = @intCast(data.len);
                    try self.write(&std.mem.toBytes(len));
                }
                try self.write(data);
            } else {
                try self.writeByte(@intFromEnum(Opcode.STRING));
                // Would need to escape string properly
                try self.write(data);
                try self.writeByte('\n');
            }
        }

        /// Pickle string (Unicode)
        pub fn dumpString(self: *Self, data: []const u8) !void {
            if (protocol >= 4 and data.len <= 0xff) {
                try self.writeByte(@intFromEnum(Opcode.SHORT_BINUNICODE));
                try self.writeByte(@intCast(data.len));
                try self.write(data);
            } else if (protocol >= 1) {
                try self.writeByte(@intFromEnum(Opcode.BINUNICODE8));
                const len: u64 = data.len;
                try self.write(&std.mem.toBytes(len));
                try self.write(data);
            } else {
                try self.writeByte(@intFromEnum(Opcode.UNICODE));
                try self.write(data);
                try self.writeByte('\n');
            }
        }

        /// Start a list
        pub fn startList(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.EMPTY_LIST));
            try self.writeByte(@intFromEnum(Opcode.MARK));
        }

        /// End a list (with APPENDS)
        pub fn endList(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.APPENDS));
        }

        /// Start a dict
        pub fn startDict(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.EMPTY_DICT));
            try self.writeByte(@intFromEnum(Opcode.MARK));
        }

        /// End a dict (with SETITEMS)
        pub fn endDict(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.SETITEMS));
        }

        /// Empty tuple
        pub fn dumpEmptyTuple(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.EMPTY_TUPLE));
        }

        /// Tuple with 1 element
        pub fn dumpTuple1(self: *Self) !void {
            if (protocol >= 2) {
                try self.writeByte(@intFromEnum(Opcode.TUPLE1));
            } else {
                try self.writeByte(@intFromEnum(Opcode.TUPLE));
            }
        }

        /// Tuple with 2 elements
        pub fn dumpTuple2(self: *Self) !void {
            if (protocol >= 2) {
                try self.writeByte(@intFromEnum(Opcode.TUPLE2));
            } else {
                try self.writeByte(@intFromEnum(Opcode.TUPLE));
            }
        }

        /// Tuple with 3 elements
        pub fn dumpTuple3(self: *Self) !void {
            if (protocol >= 2) {
                try self.writeByte(@intFromEnum(Opcode.TUPLE3));
            } else {
                try self.writeByte(@intFromEnum(Opcode.TUPLE));
            }
        }

        /// Write STOP opcode
        pub fn stop(self: *Self) !void {
            try self.writeByte(@intFromEnum(Opcode.STOP));
        }
    };
}

/// Unpickler - deserializes Python objects
pub const Unpickler = struct {
    data: []const u8,
    pos: usize,
    stack: std.ArrayList(PickleValue),
    memo: std.AutoHashMap(u32, PickleValue),
    allocator: Allocator,

    pub const PickleValue = union(enum) {
        none,
        bool_val: bool,
        int_val: i64,
        float_val: f64,
        bytes_val: []const u8,
        string_val: []const u8,
        list_val: std.ArrayList(PickleValue),
        dict_val: std.StringHashMap(PickleValue),
        tuple_val: []const PickleValue,
        mark,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, data: []const u8) Self {
        return .{
            .data = data,
            .pos = 0,
            .stack = std.ArrayList(PickleValue).init(allocator),
            .memo = std.AutoHashMap(u32, PickleValue).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
        self.memo.deinit();
    }

    fn readByte(self: *Self) !u8 {
        if (self.pos >= self.data.len) return error.UnexpectedEndOfData;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Self, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return error.UnexpectedEndOfData;
        const result = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return result;
    }

    pub fn load(self: *Self) !PickleValue {
        while (self.pos < self.data.len) {
            const opcode_byte = try self.readByte();

            // Handle as raw value first for opcodes not in enum
            switch (opcode_byte) {
                @intFromEnum(Opcode.PROTO) => {
                    _ = try self.readByte(); // protocol version
                },
                @intFromEnum(Opcode.STOP) => {
                    return self.stack.popOrNull() orelse error.EmptyStack;
                },
                @intFromEnum(Opcode.NONE) => {
                    try self.stack.append(self.allocator, .none);
                },
                @intFromEnum(Opcode.NEWTRUE) => {
                    try self.stack.append(self.allocator, .{ .bool_val = true });
                },
                @intFromEnum(Opcode.NEWFALSE) => {
                    try self.stack.append(self.allocator, .{ .bool_val = false });
                },
                @intFromEnum(Opcode.BININT1) => {
                    const v = try self.readByte();
                    try self.stack.append(self.allocator, .{ .int_val = v });
                },
                @intFromEnum(Opcode.BININT2) => {
                    const bytes = try self.readBytes(2);
                    const v = std.mem.readInt(u16, bytes[0..2], .little);
                    try self.stack.append(self.allocator, .{ .int_val = v });
                },
                @intFromEnum(Opcode.BININT) => {
                    const bytes = try self.readBytes(4);
                    const v = std.mem.readInt(i32, bytes[0..4], .little);
                    try self.stack.append(self.allocator, .{ .int_val = v });
                },
                @intFromEnum(Opcode.BINFLOAT) => {
                    const bytes = try self.readBytes(8);
                    const bits = std.mem.readInt(u64, bytes[0..8], .big);
                    const v: f64 = @bitCast(bits);
                    try self.stack.append(self.allocator, .{ .float_val = v });
                },
                @intFromEnum(Opcode.SHORT_BINBYTES) => {
                    const len = try self.readByte();
                    const bytes = try self.readBytes(len);
                    try self.stack.append(self.allocator, .{ .bytes_val = bytes });
                },
                @intFromEnum(Opcode.SHORT_BINUNICODE) => {
                    const len = try self.readByte();
                    const str = try self.readBytes(len);
                    try self.stack.append(self.allocator, .{ .string_val = str });
                },
                @intFromEnum(Opcode.EMPTY_LIST) => {
                    try self.stack.append(self.allocator, .{ .list_val = std.ArrayList(PickleValue).init(self.allocator) });
                },
                @intFromEnum(Opcode.EMPTY_DICT) => {
                    try self.stack.append(self.allocator, .{ .dict_val = std.StringHashMap(PickleValue).init(self.allocator) });
                },
                @intFromEnum(Opcode.EMPTY_TUPLE) => {
                    try self.stack.append(self.allocator, .{ .tuple_val = &[_]PickleValue{} });
                },
                @intFromEnum(Opcode.MARK) => {
                    try self.stack.append(self.allocator, .mark);
                },
                else => {
                    // Unknown opcode - skip for now
                },
            }
        }

        return self.stack.popOrNull() orelse error.EmptyStack;
    }
};

/// Convenience function to pickle a value
pub fn dumps(comptime T: type, value: T, allocator: Allocator) ![]u8 {
    var pickler = Pickler(DEFAULT_PROTOCOL).init(allocator);
    defer pickler.deinit();

    try pickler.writeHeader();

    switch (@typeInfo(T)) {
        .void => try pickler.dumpNone(),
        .bool => try pickler.dumpBool(value),
        .int => try pickler.dumpInt(@intCast(value)),
        .float => try pickler.dumpFloat(@floatCast(value)),
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                try pickler.dumpBytes(value);
            }
        },
        else => return error.UnsupportedType,
    }

    try pickler.stop();

    const result = try allocator.alloc(u8, pickler.getBytes().len);
    @memcpy(result, pickler.getBytes());
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "pickle int" {
    const allocator = std.testing.allocator;

    var pickler = Pickler(4).init(allocator);
    defer pickler.deinit();

    try pickler.writeHeader();
    try pickler.dumpInt(42);
    try pickler.stop();

    const bytes = pickler.getBytes();
    try std.testing.expect(bytes.len > 0);
}

test "pickle float" {
    const allocator = std.testing.allocator;

    var pickler = Pickler(4).init(allocator);
    defer pickler.deinit();

    try pickler.writeHeader();
    try pickler.dumpFloat(3.14159);
    try pickler.stop();

    const bytes = pickler.getBytes();
    try std.testing.expect(bytes.len > 0);
}

test "pickle bool" {
    const allocator = std.testing.allocator;

    var pickler = Pickler(4).init(allocator);
    defer pickler.deinit();

    try pickler.writeHeader();
    try pickler.dumpBool(true);
    try pickler.stop();

    const bytes = pickler.getBytes();
    try std.testing.expect(bytes.len > 0);
    // Should contain NEWTRUE opcode
    try std.testing.expect(std.mem.indexOf(u8, bytes, &[_]u8{@intFromEnum(Opcode.NEWTRUE)}) != null);
}
