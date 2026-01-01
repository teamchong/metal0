//! Pickle serializer
const std = @import("std");
const opcodes = @import("opcodes.zig");
const types = @import("types.zig");
const type_predicates = @import("../../runtime/type_predicates.zig");

const Opcode = opcodes.Opcode;
const PickleValue = types.PickleValue;

/// Encode a signed long integer to minimal bytes (little-endian, two's complement)
fn encodeSignedLong(value: i64, buf: *[9]u8) []const u8 {
    if (value == 0) return buf[0..0];
    
    var v = value;
    var len: usize = 0;
    
    // Write bytes in little-endian order
    while (len < 8) {
        buf[len] = @truncate(@as(u64, @bitCast(v)) & 0xFF);
        v = @divTrunc(v, 256);
        len += 1;
        
        // Check if we can stop
        if (value >= 0) {
            // Positive: stop when remaining is 0 and high bit of last byte is 0
            if (v == 0 and (buf[len - 1] & 0x80) == 0) break;
        } else {
            // Negative: stop when remaining is -1 and high bit of last byte is 1
            if (v == -1 and (buf[len - 1] & 0x80) != 0) break;
        }
    }
    
    return buf[0..len];
}

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
                try self.writeByte(Opcode.INT);
                try self.write(if (value) "01\n" else "00\n");
            }
            return;
        }

        if (type_predicates.isIntInfo(info)) {
            const i: i64 = @intCast(value);
            try self.serializeInt(i);
            return;
        }

        if (type_predicates.isFloatInfo(info)) {
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
            try self.serializeTuple(value);
            return;
        }

        // Structs
        if (info == .@"struct") {
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                try self.serializeList(value.items);
                return;
            }
            if (info.@"struct".is_tuple) {
                try self.serializeTupleStruct(value);
                return;
            }
            if (T == PickleValue) {
                try self.serializePickleValue(value);
                return;
            }
            if (@hasField(T, "index") and @hasField(T, "data")) {
                try self.serializeIterator(value);
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
                try self.writeByte(Opcode.LONG1);
                var buf: [9]u8 = undefined;
                const bytes = encodeSignedLong(value, &buf);
                try self.writeByte(@intCast(bytes.len));
                try self.write(bytes);
            }
        } else {
            try self.writeByte(Opcode.INT);
            var buf: [24]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.OutOfMemory;
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

    fn serializeTuple(self: *Pickler, items: anytype) !void {
        const len = items.len;
        if (len == 0) {
            try self.writeByte(Opcode.EMPTY_TUPLE);
            return;
        }

        if (self.protocol >= 2) {
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
        try self.writeByte(Opcode.GLOBAL);
        try self.write("builtins\niter\n");

        try self.writeByte(Opcode.MARK);
        for (iter.data) |item| {
            try self.serialize(item);
        }
        try self.writeByte(Opcode.TUPLE);
        try self.writeByte(Opcode.TUPLE1);
        try self.writeByte(Opcode.REDUCE);

        try self.serializeInt(@intCast(iter.index));
        try self.writeByte(Opcode.BUILD);
    }

    fn serializeIteratorValue(self: *Pickler, iter: PickleValue.Iterator) !void {
        try self.writeByte(Opcode.GLOBAL);
        try self.write("builtins\n");
        try self.write(iter.type_name);
        try self.writeByte('\n');

        try self.writeByte(Opcode.MARK);
        for (iter.data) |item| {
            try self.serializePickleValue(item);
        }
        try self.writeByte(Opcode.TUPLE);
        try self.writeByte(Opcode.TUPLE1);
        try self.writeByte(Opcode.REDUCE);

        try self.serializeInt(@intCast(iter.index));
        try self.writeByte(Opcode.BUILD);
    }
};
