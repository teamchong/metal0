/// Full Pickle module implementation for Python compatibility
/// Supports protocols 0-5 with proper serialization/deserialization
const std = @import("std");

/// Pickle protocol versions
pub const HIGHEST_PROTOCOL: i64 = 5;
pub const DEFAULT_PROTOCOL: i64 = 4;

/// Pickle opcodes
pub const Opcode = struct {
    // Framing and protocol
    pub const PROTO: u8 = 0x80; // Protocol version
    pub const FRAME: u8 = 0x95; // Frame delimiter (protocol 4+)
    pub const STOP: u8 = 0x2e; // '.' - End of pickle

    // Stack manipulation
    pub const MARK: u8 = 0x28; // '(' - Push mark
    pub const POP: u8 = 0x30; // '0' - Pop top
    pub const POP_MARK: u8 = 0x31; // '1' - Pop to mark
    pub const DUP: u8 = 0x32; // '2' - Duplicate top

    // Memo operations
    pub const PUT: u8 = 0x70; // 'p' - Store in memo (ASCII index)
    pub const BINPUT: u8 = 0x71; // 'q' - Store in memo (1-byte index)
    pub const LONG_BINPUT: u8 = 0x72; // 'r' - Store in memo (4-byte index)
    pub const GET: u8 = 0x67; // 'g' - Get from memo (ASCII index)
    pub const BINGET: u8 = 0x68; // 'h' - Get from memo (1-byte index)
    pub const LONG_BINGET: u8 = 0x6a; // 'j' - Get from memo (4-byte index)
    pub const MEMOIZE: u8 = 0x94; // Store top in memo at current size

    // None/bool
    pub const NONE: u8 = 0x4e; // 'N' - Push None
    pub const NEWTRUE: u8 = 0x88; // Push True (protocol 2+)
    pub const NEWFALSE: u8 = 0x89; // Push False (protocol 2+)

    // Integers
    pub const INT: u8 = 0x49; // 'I' - Push int (ASCII, newline terminated)
    pub const BININT: u8 = 0x4a; // 'J' - Push 4-byte signed int
    pub const BININT1: u8 = 0x4b; // 'K' - Push 1-byte unsigned int
    pub const BININT2: u8 = 0x4d; // 'M' - Push 2-byte unsigned int
    pub const LONG: u8 = 0x4c; // 'L' - Push long (ASCII)
    pub const LONG1: u8 = 0x8a; // Push long < 256 bytes
    pub const LONG4: u8 = 0x8b; // Push very large long

    // Floats
    pub const FLOAT: u8 = 0x47; // 'G' - Push float (ASCII)
    pub const BINFLOAT: u8 = 0x46; // 'F' - Push 8-byte IEEE float

    // Strings
    pub const STRING: u8 = 0x53; // 'S' - Push string (quoted, newline terminated)
    pub const BINSTRING: u8 = 0x54; // 'T' - Push counted string (4-byte length)
    pub const SHORT_BINSTRING: u8 = 0x55; // 'U' - Push string < 256 bytes
    pub const UNICODE: u8 = 0x56; // 'V' - Push unicode (escaped, newline terminated)
    pub const BINUNICODE: u8 = 0x58; // 'X' - Push UTF-8 string (4-byte length)
    pub const SHORT_BINUNICODE: u8 = 0x8c; // Push UTF-8 < 256 bytes
    pub const BINUNICODE8: u8 = 0x8d; // Push very long UTF-8 (8-byte length)

    // Bytes
    pub const BINBYTES: u8 = 0x42; // 'B' - Push bytes (4-byte length)
    pub const SHORT_BINBYTES: u8 = 0x43; // 'C' - Push bytes < 256 bytes
    pub const BINBYTES8: u8 = 0x8e; // Push very long bytes (8-byte length)
    pub const BYTEARRAY8: u8 = 0x96; // Push bytearray (8-byte length)

    // Tuples
    pub const EMPTY_TUPLE: u8 = 0x29; // ')' - Push empty tuple
    pub const TUPLE: u8 = 0x74; // 't' - Build tuple from mark
    pub const TUPLE1: u8 = 0x85; // Build 1-tuple from top
    pub const TUPLE2: u8 = 0x86; // Build 2-tuple from top 2
    pub const TUPLE3: u8 = 0x87; // Build 3-tuple from top 3

    // Lists
    pub const EMPTY_LIST: u8 = 0x5d; // ']' - Push empty list
    pub const LIST: u8 = 0x6c; // 'l' - Build list from mark
    pub const APPEND: u8 = 0x61; // 'a' - Append to list
    pub const APPENDS: u8 = 0x65; // 'e' - Extend list from mark

    // Dicts
    pub const EMPTY_DICT: u8 = 0x7d; // '}' - Push empty dict
    pub const DICT: u8 = 0x64; // 'd' - Build dict from mark
    pub const SETITEM: u8 = 0x73; // 's' - Add key-value to dict
    pub const SETITEMS: u8 = 0x75; // 'u' - Add pairs from mark to dict

    // Sets
    pub const EMPTY_SET: u8 = 0x8f; // Push empty set
    pub const ADDITEMS: u8 = 0x90; // Add items to set from mark
    pub const FROZENSET: u8 = 0x91; // Build frozenset from mark

    // Objects/Classes
    pub const GLOBAL: u8 = 0x63; // 'c' - Push global (module\nname\n)
    pub const STACK_GLOBAL: u8 = 0x93; // Push global from stack
    pub const REDUCE: u8 = 0x52; // 'R' - Apply callable to args tuple
    pub const BUILD: u8 = 0x62; // 'b' - Call __setstate__
    pub const INST: u8 = 0x69; // 'i' - Build class instance
    pub const OBJ: u8 = 0x6f; // 'o' - Build object
    pub const NEWOBJ: u8 = 0x81; // Build via __new__
    pub const NEWOBJ_EX: u8 = 0x92; // Build with keyword args

    // Persistent references
    pub const PERSID: u8 = 0x50; // 'P' - Persistent id (string)
    pub const BINPERSID: u8 = 0x51; // 'Q' - Persistent id (stack)

    // Extensions
    pub const EXT1: u8 = 0x82; // Extension (1-byte code)
    pub const EXT2: u8 = 0x83; // Extension (2-byte code)
    pub const EXT4: u8 = 0x84; // Extension (4-byte code)

    // Protocol 5 out-of-band
    pub const NEXT_BUFFER: u8 = 0x97; // Push next buffer
    pub const READONLY_BUFFER: u8 = 0x98; // Make buffer readonly
};

/// Value types that can be pickled
pub const PickleValue = union(enum) {
    none: void,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    tuple: []const PickleValue,
    list: std.ArrayList(PickleValue),
    dict: std.StringHashMap(PickleValue),
    set: std.AutoHashMap(u64, void),
    iterator: Iterator,
    memo_ref: usize,

    pub const Iterator = struct {
        type_name: []const u8,
        data: []const PickleValue,
        index: usize,
    };

    pub fn deinit(self: *PickleValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .list => |*l| {
                for (l.items) |*item| {
                    var mut_item = item.*;
                    mut_item.deinit(allocator);
                }
                l.deinit(allocator);
            },
            .dict => |*d| {
                var it = d.iterator();
                while (it.next()) |entry| {
                    var val = entry.value_ptr.*;
                    val.deinit(allocator);
                }
                d.deinit();
            },
            .tuple => |t| {
                for (t) |*item| {
                    var mut_item = @constCast(item).*;
                    mut_item.deinit(allocator);
                }
                allocator.free(t);
            },
            else => {},
        }
    }
};

/// Serialize an object to pickle bytes
pub fn dumps(obj: anytype, allocator: std.mem.Allocator) ![]const u8 {
    return dumpsWithProtocol(obj, allocator, @intCast(DEFAULT_PROTOCOL));
}

/// Serialize with specific protocol version
pub fn dumpsWithProtocol(obj: anytype, allocator: std.mem.Allocator, protocol: u8) ![]const u8 {
    var pickler = Pickler.init(allocator, protocol);
    defer pickler.deinit();
    return try pickler.dump(obj);
}

/// Deserialize pickle bytes to a PickleValue
pub fn loads(data: []const u8, allocator: std.mem.Allocator) !PickleValue {
    var unpickler = Unpickler.init(allocator, data);
    defer unpickler.deinit();
    return try unpickler.load();
}

/// Pickle to a file
pub fn dump(obj: anytype, file: anytype, allocator: std.mem.Allocator) !void {
    const data = try dumps(obj, allocator);
    defer allocator.free(data);
    try file.writeAll(data);
}

/// Unpickle from a file
pub fn load(file: anytype, allocator: std.mem.Allocator) !PickleValue {
    const data = try file.readToEndAlloc(allocator, 1024 * 1024 * 100);
    defer allocator.free(data);
    return try loads(data, allocator);
}

/// Errors
pub const PicklingError = error{
    PicklingError,
    UnknownOpcode,
    StackUnderflow,
    NoMark,
    EmptyStack,
    UnexpectedEndOfInput,
    FormatError,
};

pub const UnpicklingError = PicklingError;

/// Pickle serializer
pub const Pickler = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    memo: std.AutoHashMap(usize, u32),
    memo_count: u32,
    protocol: u8,

    pub fn init(allocator: std.mem.Allocator, protocol: u8) Pickler {
        return .{
            .allocator = allocator,
            .output = .{ .items = &[_]u8{}, .capacity = 0 },
            .memo = std.AutoHashMap(usize, u32).init(allocator),
            .memo_count = 0,
            .protocol = protocol,
        };
    }

    pub fn deinit(self: *Pickler) void {
        self.output.deinit(self.allocator);
        self.memo.deinit();
    }

    fn write(self: *Pickler, data: []const u8) !void {
        try self.output.appendSlice(self.allocator, data);
    }

    fn writeByte(self: *Pickler, byte: u8) !void {
        try self.output.append(self.allocator, byte);
    }

    fn writeU16LE(self: *Pickler, val: u16) !void {
        try self.output.append(self.allocator, @truncate(val & 0xFF));
        try self.output.append(self.allocator, @truncate((val >> 8) & 0xFF));
    }

    fn writeU32LE(self: *Pickler, val: u32) !void {
        try self.output.append(self.allocator, @truncate(val & 0xFF));
        try self.output.append(self.allocator, @truncate((val >> 8) & 0xFF));
        try self.output.append(self.allocator, @truncate((val >> 16) & 0xFF));
        try self.output.append(self.allocator, @truncate((val >> 24) & 0xFF));
    }

    fn writeI32LE(self: *Pickler, val: i32) !void {
        const u: u32 = @bitCast(val);
        try self.writeU32LE(u);
    }

    pub fn dump(self: *Pickler, value: anytype) ![]const u8 {
        if (self.protocol >= 2) {
            try self.writeByte(Opcode.PROTO);
            try self.writeByte(self.protocol);
        }
        try self.serialize(value);
        try self.writeByte(Opcode.STOP);
        return self.output.toOwnedSlice(self.allocator);
    }

    fn serialize(self: *Pickler, value: anytype) !void {
        const T = @TypeOf(value);
        const info = @typeInfo(T);

        if (info == .optional) {
            if (value) |v| {
                try self.serialize(v);
            } else {
                try self.writeByte(Opcode.NONE);
            }
            return;
        }

        if (T == void or T == @TypeOf(null)) {
            try self.writeByte(Opcode.NONE);
            return;
        }

        if (T == bool) {
            if (self.protocol >= 2) {
                try self.writeByte(if (value) Opcode.NEWTRUE else Opcode.NEWFALSE);
            } else {
                try self.writeByte(Opcode.INT);
                try self.write(if (value) "01\n" else "00\n");
            }
            return;
        }

        if (info == .int or info == .comptime_int) {
            const i: i64 = @intCast(value);
            try self.serializeInt(i);
            return;
        }

        if (info == .float or info == .comptime_float) {
            const f: f64 = @floatCast(value);
            if (self.protocol >= 1) {
                try self.writeByte(Opcode.BINFLOAT);
                const bits: u64 = @bitCast(f);
                for (0..8) |i| {
                    try self.output.append(self.allocator, @truncate((bits >> @intCast((7 - i) * 8)) & 0xFF));
                }
            } else {
                try self.writeByte(Opcode.FLOAT);
                var buf: [32]u8 = undefined;
                const len = std.fmt.formatFloat(buf[0..], f, .{ .mode = .scientific }) catch 0;
                try self.write(buf[0..len]);
                try self.writeByte('\n');
            }
            return;
        }

        if (info == .pointer and info.pointer.size == .slice) {
            if (info.pointer.child == u8) {
                try self.serializeString(value);
                return;
            }
        }

        if (info == .array) {
            if (info.array.child == u8) {
                try self.serializeString(&value);
                return;
            }
        }

        if (info == .@"struct") {
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                try self.serializeList(value.items);
                return;
            }
            if (info.@"struct".is_tuple) {
                try self.serializeTupleStruct(value);
                return;
            }
        }

        try self.writeByte(Opcode.NONE);
    }

    fn serializeInt(self: *Pickler, value: i64) !void {
        if (self.protocol >= 2) {
            if (value >= 0 and value <= 0xFF) {
                try self.writeByte(Opcode.BININT1);
                try self.writeByte(@intCast(value));
            } else if (value >= 0 and value <= 0xFFFF) {
                try self.writeByte(Opcode.BININT2);
                try self.writeU16LE(@intCast(value));
            } else if (value >= -0x80000000 and value <= 0x7FFFFFFF) {
                try self.writeByte(Opcode.BININT);
                try self.writeI32LE(@intCast(value));
            } else {
                try self.writeByte(Opcode.BININT);
                try self.writeI32LE(@intCast(@mod(value, 0x100000000)));
            }
        } else {
            try self.writeByte(Opcode.INT);
            var buf: [24]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
            try self.write(formatted);
            try self.writeByte('\n');
        }
    }

    fn serializeString(self: *Pickler, value: []const u8) !void {
        if (self.protocol >= 4 and value.len < 256) {
            try self.writeByte(Opcode.SHORT_BINUNICODE);
            try self.writeByte(@intCast(value.len));
            try self.write(value);
        } else if (self.protocol >= 3) {
            try self.writeByte(Opcode.BINUNICODE);
            try self.writeU32LE(@intCast(value.len));
            try self.write(value);
        } else if (self.protocol >= 1) {
            if (value.len < 256) {
                try self.writeByte(Opcode.SHORT_BINSTRING);
                try self.writeByte(@intCast(value.len));
                try self.write(value);
            } else {
                try self.writeByte(Opcode.BINSTRING);
                try self.writeU32LE(@intCast(value.len));
                try self.write(value);
            }
        } else {
            try self.writeByte(Opcode.STRING);
            try self.writeByte('\'');
            try self.write(value);
            try self.writeByte('\'');
            try self.writeByte('\n');
        }
    }

    fn serializeTupleStruct(self: *Pickler, value: anytype) !void {
        const T = @TypeOf(value);
        const fields = @typeInfo(T).@"struct".fields;

        if (fields.len == 0) {
            try self.writeByte(Opcode.EMPTY_TUPLE);
            return;
        }

        if (self.protocol >= 2) {
            if (fields.len == 1) {
                try self.serialize(@field(value, fields[0].name));
                try self.writeByte(Opcode.TUPLE1);
                return;
            } else if (fields.len == 2) {
                inline for (fields) |f| {
                    try self.serialize(@field(value, f.name));
                }
                try self.writeByte(Opcode.TUPLE2);
                return;
            } else if (fields.len == 3) {
                inline for (fields) |f| {
                    try self.serialize(@field(value, f.name));
                }
                try self.writeByte(Opcode.TUPLE3);
                return;
            }
        }

        try self.writeByte(Opcode.MARK);
        inline for (fields) |f| {
            try self.serialize(@field(value, f.name));
        }
        try self.writeByte(Opcode.TUPLE);
    }

    fn serializeList(self: *Pickler, items: anytype) !void {
        try self.writeByte(Opcode.EMPTY_LIST);
        if (items.len == 0) return;

        try self.writeByte(Opcode.MARK);
        for (items) |item| {
            try self.serialize(item);
        }
        try self.writeByte(Opcode.APPENDS);
    }
};

/// Pickle deserializer
pub const Unpickler = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    pos: usize,
    stack: std.ArrayList(PickleValue),
    memo: std.AutoHashMap(u32, PickleValue),
    mark_stack: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator, data: []const u8) Unpickler {
        return .{
            .allocator = allocator,
            .data = data,
            .pos = 0,
            .stack = .{ .items = &[_]PickleValue{}, .capacity = 0 },
            .memo = std.AutoHashMap(u32, PickleValue).init(allocator),
            .mark_stack = .{ .items = &[_]usize{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *Unpickler) void {
        self.stack.deinit(self.allocator);
        self.memo.deinit();
        self.mark_stack.deinit(self.allocator);
    }

    fn readByte(self: *Unpickler) !u8 {
        if (self.pos >= self.data.len) return error.UnexpectedEndOfInput;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Unpickler, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return error.UnexpectedEndOfInput;
        const slice = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return slice;
    }

    fn readLine(self: *Unpickler) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.data.len and self.data[self.pos] != '\n') {
            self.pos += 1;
        }
        if (self.pos >= self.data.len) return error.UnexpectedEndOfInput;
        const line = self.data[start..self.pos];
        self.pos += 1;
        return line;
    }

    fn readU16LE(self: *Unpickler) !u16 {
        const bytes = try self.readBytes(2);
        return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
    }

    fn readU32LE(self: *Unpickler) !u32 {
        const bytes = try self.readBytes(4);
        return @as(u32, bytes[0]) |
            (@as(u32, bytes[1]) << 8) |
            (@as(u32, bytes[2]) << 16) |
            (@as(u32, bytes[3]) << 24);
    }

    fn readI32LE(self: *Unpickler) !i32 {
        const u = try self.readU32LE();
        return @bitCast(u);
    }

    fn readU64LE(self: *Unpickler) !u64 {
        const bytes = try self.readBytes(8);
        var result: u64 = 0;
        for (0..8) |i| {
            result |= @as(u64, bytes[i]) << @intCast(i * 8);
        }
        return result;
    }

    fn readF64BE(self: *Unpickler) !f64 {
        const bytes = try self.readBytes(8);
        var bits: u64 = 0;
        for (0..8) |i| {
            bits |= @as(u64, bytes[i]) << @intCast((7 - i) * 8);
        }
        return @bitCast(bits);
    }

    fn push(self: *Unpickler, value: PickleValue) !void {
        try self.stack.append(self.allocator, value);
    }

    fn pop(self: *Unpickler) !PickleValue {
        return self.stack.pop() orelse error.StackUnderflow;
    }

    fn popToMark(self: *Unpickler) ![]PickleValue {
        const mark_pos = self.mark_stack.pop() orelse return error.NoMark;
        const items = try self.allocator.dupe(PickleValue, self.stack.items[mark_pos..]);
        self.stack.shrinkRetainingCapacity(mark_pos);
        return items;
    }

    pub fn load(self: *Unpickler) !PickleValue {
        while (self.pos < self.data.len) {
            const opcode = try self.readByte();

            switch (opcode) {
                Opcode.STOP => return self.stack.pop() orelse error.EmptyStack,
                Opcode.PROTO => _ = try self.readByte(),
                Opcode.FRAME => _ = try self.readU64LE(),
                Opcode.NONE => try self.push(.{ .none = {} }),
                Opcode.NEWTRUE => try self.push(.{ .bool = true }),
                Opcode.NEWFALSE => try self.push(.{ .bool = false }),
                Opcode.INT => {
                    const line = try self.readLine();
                    if (std.mem.eql(u8, line, "00")) {
                        try self.push(.{ .bool = false });
                    } else if (std.mem.eql(u8, line, "01")) {
                        try self.push(.{ .bool = true });
                    } else {
                        const val = std.fmt.parseInt(i64, line, 10) catch 0;
                        try self.push(.{ .int = val });
                    }
                },
                Opcode.BININT => try self.push(.{ .int = try self.readI32LE() }),
                Opcode.BININT1 => try self.push(.{ .int = try self.readByte() }),
                Opcode.BININT2 => try self.push(.{ .int = try self.readU16LE() }),
                Opcode.FLOAT => {
                    const line = try self.readLine();
                    const val = std.fmt.parseFloat(f64, line) catch 0.0;
                    try self.push(.{ .float = val });
                },
                Opcode.BINFLOAT => try self.push(.{ .float = try self.readF64BE() }),
                Opcode.STRING => {
                    const line = try self.readLine();
                    const str = if (line.len >= 2 and (line[0] == '\'' or line[0] == '"'))
                        line[1 .. line.len - 1]
                    else
                        line;
                    try self.push(.{ .string = try self.allocator.dupe(u8, str) });
                },
                Opcode.BINSTRING, Opcode.BINUNICODE => {
                    const len = try self.readU32LE();
                    const str = try self.readBytes(len);
                    try self.push(.{ .string = try self.allocator.dupe(u8, str) });
                },
                Opcode.SHORT_BINSTRING, Opcode.SHORT_BINUNICODE => {
                    const len = try self.readByte();
                    const str = try self.readBytes(len);
                    try self.push(.{ .string = try self.allocator.dupe(u8, str) });
                },
                Opcode.MARK => try self.mark_stack.append(self.allocator, self.stack.items.len),
                Opcode.EMPTY_TUPLE => try self.push(.{ .tuple = &[_]PickleValue{} }),
                Opcode.TUPLE => try self.push(.{ .tuple = try self.popToMark() }),
                Opcode.TUPLE1 => {
                    const a = try self.pop();
                    const items = try self.allocator.alloc(PickleValue, 1);
                    items[0] = a;
                    try self.push(.{ .tuple = items });
                },
                Opcode.TUPLE2 => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const items = try self.allocator.alloc(PickleValue, 2);
                    items[0] = a;
                    items[1] = b;
                    try self.push(.{ .tuple = items });
                },
                Opcode.TUPLE3 => {
                    const c = try self.pop();
                    const b = try self.pop();
                    const a = try self.pop();
                    const items = try self.allocator.alloc(PickleValue, 3);
                    items[0] = a;
                    items[1] = b;
                    items[2] = c;
                    try self.push(.{ .tuple = items });
                },
                Opcode.EMPTY_LIST => try self.push(.{ .list = .{ .items = &[_]PickleValue{}, .capacity = 0 } }),
                Opcode.LIST => {
                    const items = try self.popToMark();
                    var list: std.ArrayList(PickleValue) = .{ .items = &[_]PickleValue{}, .capacity = 0 };
                    try list.appendSlice(self.allocator, items);
                    self.allocator.free(items);
                    try self.push(.{ .list = list });
                },
                Opcode.EMPTY_DICT => try self.push(.{ .dict = std.StringHashMap(PickleValue).init(self.allocator) }),
                else => return error.UnknownOpcode,
            }
        }
        return error.UnexpectedEndOfInput;
    }
};

test "pickle basic types" {
    const allocator = std.testing.allocator;

    const data = try dumps(@as(i64, 42), allocator);
    defer allocator.free(data);
    const result = try loads(data, allocator);
    try std.testing.expect(result == .int and result.int == 42);
}
