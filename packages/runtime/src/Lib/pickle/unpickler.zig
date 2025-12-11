//! Pickle deserializer
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const opcodes = @import("opcodes.zig");
const types = @import("types.zig");

const Opcode = opcodes.Opcode;
const PickleValue = types.PickleValue;

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
        if (self.pos >= self.data.len) return error.UnexpectedEOF;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Unpickler, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return error.UnexpectedEOF;
        const slice = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return slice;
    }

    fn readLine(self: *Unpickler) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.data.len and self.data[self.pos] != '\n') {
            self.pos += 1;
        }
        if (self.pos >= self.data.len) return error.UnexpectedEOF;
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
        const mark_pos = self.mark_stack.pop() orelse return error.InvalidData;
        const items = try self.allocator.dupe(PickleValue, self.stack.items[mark_pos..]);
        self.stack.shrinkRetainingCapacity(mark_pos);
        return items;
    }

    pub fn load(self: *Unpickler) !PickleValue {
        while (self.pos < self.data.len) {
            const opcode = try self.readByte();

            switch (opcode) {
                Opcode.STOP => {
                    return self.stack.pop() orelse error.StackUnderflow;
                },
                Opcode.PROTO => {
                    _ = try self.readByte();
                },
                Opcode.FRAME => {
                    _ = try self.readU64LE();
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
                    try self.push(.{ .dict = hashmap_helper.StringHashMap(PickleValue).init(self.allocator) });
                },
                Opcode.DICT => {
                    const items = try self.popToMark();
                    var dict = hashmap_helper.StringHashMap(PickleValue).init(self.allocator);
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
                            try self.push(args);
                        }
                    } else {
                        try self.push(args);
                    }
                },
                Opcode.BUILD => {
                    const state = try self.pop();
                    var obj = try self.pop();
                    if (obj == .iterator and state == .int) {
                        obj.iterator.index = @intCast(state.int);
                    }
                    try self.push(obj);
                },
                Opcode.NEWOBJ => {
                    const args = try self.pop();
                    const cls = try self.pop();
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
                    _ = try self.pop();
                    const args = try self.pop();
                    _ = try self.pop();
                    try self.push(args);
                },
                Opcode.INST, Opcode.OBJ => {
                    _ = try self.popToMark();
                    try self.push(.{ .none = {} });
                },
                Opcode.PERSID, Opcode.BINPERSID => {
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
                    try self.push(.{ .none = {} });
                },
                Opcode.BYTEARRAY8 => {
                    const len = try self.readU64LE();
                    const bytes = try self.readBytes(@intCast(len));
                    try self.push(.{ .bytes = try self.allocator.dupe(u8, bytes) });
                },
                else => {
                    return error.InvalidOpcode;
                },
            }
        }

        return error.UnexpectedEOF;
    }
};
