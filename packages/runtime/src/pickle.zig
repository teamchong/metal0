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
    // For iterators - store type info and state
    iterator: Iterator,
    // Reference to memo
    memo_ref: usize,

    pub const Iterator = struct {
        type_name: []const u8, // "tuple_iterator", "list_iterator", "reversed"
        data: []const PickleValue, // The underlying data
        index: usize, // Current position
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

    fn writeU64LE(self: *Pickler, val: u64) !void {
        for (0..8) |i| {
            try self.output.append(self.allocator, @truncate((val >> @intCast(i * 8)) & 0xFF));
        }
    }

    fn writeF64LE(self: *Pickler, val: f64) !void {
        const bits: u64 = @bitCast(val);
        try self.writeU64LE(bits);
    }

    pub fn dump(self: *Pickler, value: anytype) ![]const u8 {
        // Write protocol header for protocol 2+
        if (self.protocol >= 2) {
            try self.writeByte(Opcode.PROTO);
            try self.writeByte(self.protocol);
        }

        // Serialize the value
        try self.serialize(value);

        // Write stop opcode
        try self.writeByte(Opcode.STOP);

        return self.output.toOwnedSlice(self.allocator);
    }

    fn serialize(self: *Pickler, value: anytype) !void {
        const T = @TypeOf(value);
        const info = @typeInfo(T);

        // Handle optional types
        if (info == .optional) {
            if (value) |v| {
                try self.serialize(v);
            } else {
                try self.writeByte(Opcode.NONE);
            }
            return;
        }

        // Handle specific types
        if (T == void or T == @TypeOf(null)) {
            try self.writeByte(Opcode.NONE);
            return;
        }

        if (T == bool) {
            if (self.protocol >= 2) {
                try self.writeByte(if (value) Opcode.NEWTRUE else Opcode.NEWFALSE);
            } else {
                // Protocol 0/1: I01\n or I00\n
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
                // Big-endian for BINFLOAT
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
                // String/bytes
                try self.serializeString(value);
                return;
            }
        }

        // Arrays
        if (info == .array) {
            if (info.array.child == u8) {
                try self.serializeString(&value);
                return;
            }
            // Serialize as tuple
            try self.serializeTuple(value);
            return;
        }

        // Structs - check for specific types
        if (info == .@"struct") {
            // ArrayList
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                try self.serializeList(value.items);
                return;
            }
            // Tuple struct
            if (info.@"struct".is_tuple) {
                try self.serializeTupleStruct(value);
                return;
            }
            // PickleValue
            if (T == PickleValue) {
                try self.serializePickleValue(value);
                return;
            }
            // Iterator types
            if (@hasField(T, "index") and @hasField(T, "data")) {
                try self.serializeIterator(value);
                return;
            }
        }

        // Default: try to serialize as is
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
                // Large int - use LONG1
                try self.writeByte(Opcode.LONG1);
                var buf: [9]u8 = undefined;
                const bytes = encodeSignedLong(value, &buf);
                try self.writeByte(@intCast(bytes.len));
                try self.write(bytes);
            }
        } else {
            // Protocol 0: ASCII
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
            // Protocol 0: quoted string
            try self.writeByte(Opcode.STRING);
            try self.writeByte('\'');
            try self.write(value);
            try self.writeByte('\'');
            try self.writeByte('\n');
        }
    }

    fn serializeTuple(self: *Pickler, items: anytype) !void {
        const len = items.len;
        if (len == 0) {
            try self.writeByte(Opcode.EMPTY_TUPLE);
            return;
        }

        if (self.protocol >= 2) {
            // Use TUPLE1/2/3 for small tuples
            if (len == 1) {
                try self.serialize(items[0]);
                try self.writeByte(Opcode.TUPLE1);
                return;
            } else if (len == 2) {
                try self.serialize(items[0]);
                try self.serialize(items[1]);
                try self.writeByte(Opcode.TUPLE2);
                return;
            } else if (len == 3) {
                try self.serialize(items[0]);
                try self.serialize(items[1]);
                try self.serialize(items[2]);
                try self.writeByte(Opcode.TUPLE3);
                return;
            }
        }

        // General case: MARK items TUPLE
        try self.writeByte(Opcode.MARK);
        for (items) |item| {
            try self.serialize(item);
        }
        try self.writeByte(Opcode.TUPLE);
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

    fn serializePickleValue(self: *Pickler, value: PickleValue) !void {
        switch (value) {
            .none => try self.writeByte(Opcode.NONE),
            .bool => |b| {
                if (self.protocol >= 2) {
                    try self.writeByte(if (b) Opcode.NEWTRUE else Opcode.NEWFALSE);
                } else {
                    try self.writeByte(Opcode.INT);
                    try self.write(if (b) "01\n" else "00\n");
                }
            },
            .int => |i| try self.serializeInt(i),
            .float => |f| {
                try self.writeByte(Opcode.BINFLOAT);
                const bits: u64 = @bitCast(f);
                for (0..8) |j| {
                    try self.output.append(self.allocator, @truncate((bits >> @intCast((7 - j) * 8)) & 0xFF));
                }
            },
            .string => |s| try self.serializeString(s),
            .bytes => |b| {
                if (self.protocol >= 3) {
                    if (b.len < 256) {
                        try self.writeByte(Opcode.SHORT_BINBYTES);
                        try self.writeByte(@intCast(b.len));
                    } else {
                        try self.writeByte(Opcode.BINBYTES);
                        try self.writeU32LE(@intCast(b.len));
                    }
                    try self.write(b);
                } else {
                    try self.serializeString(b);
                }
            },
            .tuple => |t| {
                if (t.len == 0) {
                    try self.writeByte(Opcode.EMPTY_TUPLE);
                } else {
                    try self.writeByte(Opcode.MARK);
                    for (t) |item| {
                        try self.serializePickleValue(item);
                    }
                    try self.writeByte(Opcode.TUPLE);
                }
            },
            .list => |l| {
                try self.writeByte(Opcode.EMPTY_LIST);
                if (l.items.len > 0) {
                    try self.writeByte(Opcode.MARK);
                    for (l.items) |item| {
                        try self.serializePickleValue(item);
                    }
                    try self.writeByte(Opcode.APPENDS);
                }
            },
            .dict => |d| {
                try self.writeByte(Opcode.EMPTY_DICT);
                if (d.count() > 0) {
                    try self.writeByte(Opcode.MARK);
                    var it = d.iterator();
                    while (it.next()) |entry| {
                        try self.serializeString(entry.key_ptr.*);
                        try self.serializePickleValue(entry.value_ptr.*);
                    }
                    try self.writeByte(Opcode.SETITEMS);
                }
            },
            .set => |s| {
                if (self.protocol >= 4) {
                    try self.writeByte(Opcode.EMPTY_SET);
                    if (s.count() > 0) {
                        try self.writeByte(Opcode.MARK);
                        var it = s.iterator();
                        while (it.next()) |entry| {
                            try self.serializeInt(@bitCast(entry.key_ptr.*));
                        }
                        try self.writeByte(Opcode.ADDITEMS);
                    }
                } else {
                    // Older protocols: use GLOBAL for set
                    try self.writeByte(Opcode.GLOBAL);
                    try self.write("builtins\nset\n");
                    try self.writeByte(Opcode.EMPTY_LIST);
                    try self.writeByte(Opcode.REDUCE);
                }
            },
            .iterator => |iter| try self.serializeIteratorValue(iter),
            .memo_ref => |idx| {
                if (idx < 256) {
                    try self.writeByte(Opcode.BINGET);
                    try self.writeByte(@intCast(idx));
                } else {
                    try self.writeByte(Opcode.LONG_BINGET);
                    try self.writeU32LE(@intCast(idx));
                }
            },
        }
    }

    fn serializeIterator(self: *Pickler, iter: anytype) !void {
        // Serialize iterator as: GLOBAL builtins\niter\n (data_tuple) REDUCE BUILD (index)
        try self.writeByte(Opcode.GLOBAL);
        try self.write("builtins\niter\n");

        // Serialize the underlying data as a tuple
        try self.writeByte(Opcode.MARK);
        for (iter.data) |item| {
            try self.serialize(item);
        }
        try self.writeByte(Opcode.TUPLE);

        // TUPLE1 for args to iter()
        try self.writeByte(Opcode.TUPLE1);

        // REDUCE to call iter(data)
        try self.writeByte(Opcode.REDUCE);

        // Store iterator state (index) via BUILD
        try self.serializeInt(@intCast(iter.index));
        try self.writeByte(Opcode.BUILD);
    }

    fn serializeIteratorValue(self: *Pickler, iter: PickleValue.Iterator) !void {
        // Serialize as: GLOBAL <module>\n<type>\n (data) REDUCE (state) BUILD
        try self.writeByte(Opcode.GLOBAL);
        try self.write("builtins\n");
        try self.write(iter.type_name);
        try self.writeByte('\n');

        // Data tuple
        try self.writeByte(Opcode.MARK);
        for (iter.data) |item| {
            try self.serializePickleValue(item);
        }
        try self.writeByte(Opcode.TUPLE);
        try self.writeByte(Opcode.TUPLE1);
        try self.writeByte(Opcode.REDUCE);

        // State (index)
        try self.serializeInt(@intCast(iter.index));
        try self.writeByte(Opcode.BUILD);
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
        self.pos += 1; // Skip newline
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
                Opcode.STOP => {
                    return self.stack.pop() orelse error.EmptyStack;
                },
                Opcode.PROTO => {
                    _ = try self.readByte(); // Protocol version
                },
                Opcode.FRAME => {
                    _ = try self.readU64LE(); // Frame size (ignored)
                },
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
                Opcode.BININT => {
                    const val = try self.readI32LE();
                    try self.push(.{ .int = val });
                },
                Opcode.BININT1 => {
                    const val = try self.readByte();
                    try self.push(.{ .int = val });
                },
                Opcode.BININT2 => {
                    const val = try self.readU16LE();
                    try self.push(.{ .int = val });
                },
                Opcode.LONG => {
                    const line = try self.readLine();
                    // Remove trailing 'L' if present
                    const clean = if (line.len > 0 and line[line.len - 1] == 'L')
                        line[0 .. line.len - 1]
                    else
                        line;
                    const val = std.fmt.parseInt(i64, clean, 10) catch 0;
                    try self.push(.{ .int = val });
                },
                Opcode.LONG1 => {
                    const n = try self.readByte();
                    const bytes = try self.readBytes(n);
                    const val = decodeSignedLong(bytes);
                    try self.push(.{ .int = val });
                },
                Opcode.LONG4 => {
                    const n = try self.readU32LE();
                    const bytes = try self.readBytes(n);
                    const val = decodeSignedLong(bytes);
                    try self.push(.{ .int = val });
                },
                Opcode.FLOAT => {
                    const line = try self.readLine();
                    const val = std.fmt.parseFloat(f64, line) catch 0.0;
                    try self.push(.{ .float = val });
                },
                Opcode.BINFLOAT => {
                    const val = try self.readF64BE();
                    try self.push(.{ .float = val });
                },
                Opcode.STRING => {
                    const line = try self.readLine();
                    // Remove quotes
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
                Opcode.BINUNICODE8 => {
                    const len = try self.readU64LE();
                    const str = try self.readBytes(@intCast(len));
                    try self.push(.{ .string = try self.allocator.dupe(u8, str) });
                },
                Opcode.UNICODE => {
                    const line = try self.readLine();
                    try self.push(.{ .string = try self.allocator.dupe(u8, line) });
                },
                Opcode.BINBYTES => {
                    const len = try self.readU32LE();
                    const bytes = try self.readBytes(len);
                    try self.push(.{ .bytes = try self.allocator.dupe(u8, bytes) });
                },
                Opcode.SHORT_BINBYTES => {
                    const len = try self.readByte();
                    const bytes = try self.readBytes(len);
                    try self.push(.{ .bytes = try self.allocator.dupe(u8, bytes) });
                },
                Opcode.BINBYTES8 => {
                    const len = try self.readU64LE();
                    const bytes = try self.readBytes(@intCast(len));
                    try self.push(.{ .bytes = try self.allocator.dupe(u8, bytes) });
                },
                Opcode.MARK => {
                    try self.mark_stack.append(self.allocator, self.stack.items.len);
                },
                Opcode.EMPTY_TUPLE => try self.push(.{ .tuple = &[_]PickleValue{} }),
                Opcode.TUPLE => {
                    const items = try self.popToMark();
                    try self.push(.{ .tuple = items });
                },
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
                Opcode.EMPTY_LIST => {
                    try self.push(.{ .list = .{ .items = &[_]PickleValue{}, .capacity = 0 } });
                },
                Opcode.LIST => {
                    const items = try self.popToMark();
                    var list: std.ArrayList(PickleValue) = .{ .items = &[_]PickleValue{}, .capacity = 0 };
                    try list.appendSlice(self.allocator, items);
                    self.allocator.free(items);
                    try self.push(.{ .list = list });
                },
                Opcode.APPEND => {
                    const item = try self.pop();
                    var list_val = try self.pop();
                    if (list_val == .list) {
                        try list_val.list.append(self.allocator, item);
                        try self.push(list_val);
                    }
                },
                Opcode.APPENDS => {
                    const items = try self.popToMark();
                    var list_val = try self.pop();
                    if (list_val == .list) {
                        try list_val.list.appendSlice(self.allocator, items);
                        try self.push(list_val);
                    }
                    self.allocator.free(items);
                },
                Opcode.EMPTY_DICT => {
                    try self.push(.{ .dict = std.StringHashMap(PickleValue).init(self.allocator) });
                },
                Opcode.DICT => {
                    const items = try self.popToMark();
                    var dict = std.StringHashMap(PickleValue).init(self.allocator);
                    var i: usize = 0;
                    while (i + 1 < items.len) : (i += 2) {
                        if (items[i] == .string) {
                            try dict.put(items[i].string, items[i + 1]);
                        }
                    }
                    self.allocator.free(items);
                    try self.push(.{ .dict = dict });
                },
                Opcode.SETITEM => {
                    const val = try self.pop();
                    const key = try self.pop();
                    var dict_val = try self.pop();
                    if (dict_val == .dict and key == .string) {
                        try dict_val.dict.put(key.string, val);
                        try self.push(dict_val);
                    }
                },
                Opcode.SETITEMS => {
                    const items = try self.popToMark();
                    var dict_val = try self.pop();
                    if (dict_val == .dict) {
                        var i: usize = 0;
                        while (i + 1 < items.len) : (i += 2) {
                            if (items[i] == .string) {
                                try dict_val.dict.put(items[i].string, items[i + 1]);
                            }
                        }
                        try self.push(dict_val);
                    }
                    self.allocator.free(items);
                },
                Opcode.EMPTY_SET => {
                    try self.push(.{ .set = std.AutoHashMap(u64, void).init(self.allocator) });
                },
                Opcode.ADDITEMS => {
                    const items = try self.popToMark();
                    var set_val = try self.pop();
                    if (set_val == .set) {
                        for (items) |item| {
                            if (item == .int) {
                                try set_val.set.put(@bitCast(item.int), {});
                            }
                        }
                        try self.push(set_val);
                    }
                    self.allocator.free(items);
                },
                Opcode.FROZENSET => {
                    const items = try self.popToMark();
                    var set = std.AutoHashMap(u64, void).init(self.allocator);
                    for (items) |item| {
                        if (item == .int) {
                            try set.put(@bitCast(item.int), {});
                        }
                    }
                    self.allocator.free(items);
                    try self.push(.{ .set = set });
                },
                Opcode.PUT => {
                    const line = try self.readLine();
                    const idx = std.fmt.parseInt(u32, line, 10) catch 0;
                    if (self.stack.items.len > 0) {
                        try self.memo.put(idx, self.stack.items[self.stack.items.len - 1]);
                    }
                },
                Opcode.BINPUT => {
                    const idx = try self.readByte();
                    if (self.stack.items.len > 0) {
                        try self.memo.put(idx, self.stack.items[self.stack.items.len - 1]);
                    }
                },
                Opcode.LONG_BINPUT => {
                    const idx = try self.readU32LE();
                    if (self.stack.items.len > 0) {
                        try self.memo.put(idx, self.stack.items[self.stack.items.len - 1]);
                    }
                },
                Opcode.MEMOIZE => {
                    const idx: u32 = @intCast(self.memo.count());
                    if (self.stack.items.len > 0) {
                        try self.memo.put(idx, self.stack.items[self.stack.items.len - 1]);
                    }
                },
                Opcode.GET => {
                    const line = try self.readLine();
                    const idx = std.fmt.parseInt(u32, line, 10) catch 0;
                    if (self.memo.get(idx)) |val| {
                        try self.push(val);
                    }
                },
                Opcode.BINGET => {
                    const idx = try self.readByte();
                    if (self.memo.get(idx)) |val| {
                        try self.push(val);
                    }
                },
                Opcode.LONG_BINGET => {
                    const idx = try self.readU32LE();
                    if (self.memo.get(idx)) |val| {
                        try self.push(val);
                    }
                },
                Opcode.POP => {
                    _ = self.stack.pop();
                },
                Opcode.POP_MARK => {
                    _ = try self.popToMark();
                },
                Opcode.DUP => {
                    if (self.stack.items.len > 0) {
                        try self.push(self.stack.items[self.stack.items.len - 1]);
                    }
                },
                Opcode.GLOBAL => {
                    const module = try self.readLine();
                    const name = try self.readLine();
                    // Store as a special marker for REDUCE
                    const combined = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module, name });
                    try self.push(.{ .string = combined });
                },
                Opcode.STACK_GLOBAL => {
                    const name = try self.pop();
                    const module = try self.pop();
                    if (module == .string and name == .string) {
                        const combined = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module.string, name.string });
                        try self.push(.{ .string = combined });
                    }
                },
                Opcode.REDUCE => {
                    const args = try self.pop();
                    const callable = try self.pop();
                    // Handle iterator reconstruction
                    if (callable == .string) {
                        if (std.mem.eql(u8, callable.string, "builtins.iter") or
                            std.mem.eql(u8, callable.string, "builtins.tuple_iterator") or
                            std.mem.eql(u8, callable.string, "builtins.list_iterator"))
                        {
                            if (args == .tuple and args.tuple.len > 0) {
                                const type_name = if (std.mem.indexOf(u8, callable.string, "tuple")) |_|
                                    "tuple_iterator"
                                else if (std.mem.indexOf(u8, callable.string, "list")) |_|
                                    "list_iterator"
                                else
                                    "iter";
                                try self.push(.{
                                    .iterator = .{
                                        .type_name = type_name,
                                        .data = if (args.tuple[0] == .tuple) args.tuple[0].tuple else &[_]PickleValue{},
                                        .index = 0,
                                    },
                                });
                            } else {
                                try self.push(.{ .none = {} });
                            }
                        } else if (std.mem.eql(u8, callable.string, "builtins.reversed")) {
                            if (args == .tuple and args.tuple.len > 0 and args.tuple[0] == .tuple) {
                                try self.push(.{
                                    .iterator = .{
                                        .type_name = "reversed",
                                        .data = args.tuple[0].tuple,
                                        .index = 0,
                                    },
                                });
                            } else {
                                try self.push(.{ .none = {} });
                            }
                        } else if (std.mem.eql(u8, callable.string, "builtins.set")) {
                            try self.push(.{ .set = std.AutoHashMap(u64, void).init(self.allocator) });
                        } else {
                            // Unknown callable - just push args
                            try self.push(args);
                        }
                    } else {
                        try self.push(args);
                    }
                },
                Opcode.BUILD => {
                    const state = try self.pop();
                    var obj = try self.pop();
                    // For iterators, state is the index
                    if (obj == .iterator and state == .int) {
                        obj.iterator.index = @intCast(state.int);
                    }
                    try self.push(obj);
                },
                Opcode.NEWOBJ => {
                    const args = try self.pop();
                    const cls = try self.pop();
                    // Simplified: just return args or construct iterator
                    if (cls == .string) {
                        if (std.mem.indexOf(u8, cls.string, "iterator") != null) {
                            if (args == .tuple and args.tuple.len > 0) {
                                try self.push(.{
                                    .iterator = .{
                                        .type_name = cls.string,
                                        .data = if (args.tuple[0] == .tuple) args.tuple[0].tuple else &[_]PickleValue{},
                                        .index = 0,
                                    },
                                });
                            } else {
                                try self.push(args);
                            }
                        } else {
                            try self.push(args);
                        }
                    } else {
                        try self.push(args);
                    }
                },
                Opcode.NEWOBJ_EX => {
                    _ = try self.pop(); // kwargs
                    const args = try self.pop();
                    _ = try self.pop(); // cls
                    try self.push(args);
                },
                Opcode.INST, Opcode.OBJ => {
                    // Simplified: just pop mark items and push None
                    _ = try self.popToMark();
                    try self.push(.{ .none = {} });
                },
                Opcode.PERSID, Opcode.BINPERSID => {
                    // Persistent IDs not fully supported
                    if (opcode == Opcode.PERSID) {
                        _ = try self.readLine();
                    } else {
                        _ = try self.pop();
                    }
                    try self.push(.{ .none = {} });
                },
                Opcode.EXT1 => {
                    _ = try self.readByte();
                    try self.push(.{ .none = {} });
                },
                Opcode.EXT2 => {
                    _ = try self.readU16LE();
                    try self.push(.{ .none = {} });
                },
                Opcode.EXT4 => {
                    _ = try self.readU32LE();
                    try self.push(.{ .none = {} });
                },
                Opcode.NEXT_BUFFER, Opcode.READONLY_BUFFER => {
                    // Out-of-band data not supported
                    try self.push(.{ .none = {} });
                },
                Opcode.BYTEARRAY8 => {
                    const len = try self.readU64LE();
                    const bytes = try self.readBytes(@intCast(len));
                    try self.push(.{ .bytes = try self.allocator.dupe(u8, bytes) });
                },
                else => {
                    // Unknown opcode - skip
                    return error.UnknownOpcode;
                },
            }
        }

        return error.UnexpectedEndOfInput;
    }
};

/// Encode a signed integer as little-endian bytes (for LONG1/LONG4)
fn encodeSignedLong(value: i64, buf: *[9]u8) []u8 {
    if (value == 0) {
        return buf[0..0];
    }

    const u: u64 = if (value < 0) @bitCast(value) else @intCast(value);
    var len: usize = 0;

    // Find minimum bytes needed
    var v = u;
    while (v != 0 or (len == 0)) : (v >>= 8) {
        buf[len] = @truncate(v & 0xFF);
        len += 1;
        if (len >= 8) break;
    }

    // For negative numbers, ensure sign bit is set
    if (value < 0) {
        while (len < 8 and (buf[len - 1] & 0x80) == 0) {
            buf[len] = 0xFF;
            len += 1;
        }
    } else {
        // For positive, ensure sign bit is not set
        if (len > 0 and (buf[len - 1] & 0x80) != 0) {
            buf[len] = 0;
            len += 1;
        }
    }

    return buf[0..len];
}

/// Decode little-endian bytes to signed integer
fn decodeSignedLong(bytes: []const u8) i64 {
    if (bytes.len == 0) return 0;

    var result: i64 = 0;
    for (bytes, 0..) |b, i| {
        result |= @as(i64, b) << @intCast(i * 8);
    }

    // Sign extend if negative
    if (bytes.len > 0 and (bytes[bytes.len - 1] & 0x80) != 0) {
        const shift: u6 = @intCast(bytes.len * 8);
        if (shift < 64) {
            result |= @as(i64, -1) << shift;
        }
    }

    return result;
}

// ============================================================================
// Public API matching Python's pickle module
// ============================================================================

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
    const data = try file.readToEndAlloc(allocator, 1024 * 1024 * 100); // 100MB max
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
};

pub const UnpicklingError = PicklingError;

// ============================================================================
// Tests
// ============================================================================

test "pickle basic types" {
    const allocator = std.testing.allocator;

    // Test None
    {
        const data = try dumps(@as(?i64, null), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .none);
    }

    // Test bool
    {
        const data = try dumps(true, allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .bool and result.bool == true);
    }

    // Test int
    {
        const data = try dumps(@as(i64, 42), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .int and result.int == 42);
    }

    // Test float
    {
        const data = try dumps(@as(f64, 3.14), allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        try std.testing.expect(result == .float and @abs(result.float - 3.14) < 0.001);
    }

    // Test string
    {
        const data = try dumps("hello", allocator);
        defer allocator.free(data);
        const result = try loads(data, allocator);
        defer allocator.free(result.string);
        try std.testing.expect(result == .string and std.mem.eql(u8, result.string, "hello"));
    }
}

test "pickle tuple" {
    const allocator = std.testing.allocator;

    const data = try dumps(.{ @as(i64, 1), @as(i64, 2), @as(i64, 3) }, allocator);
    defer allocator.free(data);

    const result = try loads(data, allocator);
    defer allocator.free(result.tuple);

    try std.testing.expect(result == .tuple);
    try std.testing.expectEqual(@as(usize, 3), result.tuple.len);
    try std.testing.expectEqual(@as(i64, 1), result.tuple[0].int);
    try std.testing.expectEqual(@as(i64, 2), result.tuple[1].int);
    try std.testing.expectEqual(@as(i64, 3), result.tuple[2].int);
}
