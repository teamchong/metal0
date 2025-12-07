//! Python 'pickletools' module - Tools for working with pickle data
//!
//! Provides functions to analyze and disassemble pickle data.
//!
//! Mirrors: CPython Lib/pickletools.py

const std = @import("std");

// ============================================================================
// Pickle Opcodes
// ============================================================================

/// Pickle protocol opcodes
pub const Opcode = enum(u8) {
    // Protocol 0/1 (ASCII)
    MARK = '(',
    STOP = '.',
    POP = '0',
    POP_MARK = '1',
    DUP = '2',
    FLOAT = 'F',
    INT = 'I',
    BININT = 'J',
    BININT1 = 'K',
    LONG = 'L',
    BININT2 = 'M',
    NONE = 'N',
    PERSID = 'P',
    BINPERSID = 'Q',
    REDUCE = 'R',
    STRING = 'S',
    BINSTRING = 'T',
    SHORT_BINSTRING = 'U',
    UNICODE = 'V',
    BINUNICODE = 'X',
    APPEND = 'a',
    BUILD = 'b',
    GLOBAL = 'c',
    DICT = 'd',
    EMPTY_DICT = '}',
    APPENDS = 'e',
    GET = 'g',
    BINGET = 'h',
    INST = 'i',
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
    BINFLOAT = 'G',

    // Protocol 2
    PROTO = 0x80,
    NEWOBJ = 0x81,
    EXT1 = 0x82,
    EXT2 = 0x83,
    EXT4 = 0x84,
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
    NEWOBJ_EX = 0x92,
    STACK_GLOBAL = 0x93,
    MEMOIZE = 0x94,
    FRAME = 0x95,

    // Protocol 5
    BYTEARRAY8 = 0x96,
    NEXT_BUFFER = 0x97,
    READONLY_BUFFER = 0x98,

    _,

    pub fn name(self: Opcode) []const u8 {
        return switch (self) {
            .MARK => "MARK",
            .STOP => "STOP",
            .POP => "POP",
            .POP_MARK => "POP_MARK",
            .DUP => "DUP",
            .FLOAT => "FLOAT",
            .INT => "INT",
            .BININT => "BININT",
            .BININT1 => "BININT1",
            .LONG => "LONG",
            .BININT2 => "BININT2",
            .NONE => "NONE",
            .PERSID => "PERSID",
            .BINPERSID => "BINPERSID",
            .REDUCE => "REDUCE",
            .STRING => "STRING",
            .BINSTRING => "BINSTRING",
            .SHORT_BINSTRING => "SHORT_BINSTRING",
            .UNICODE => "UNICODE",
            .BINUNICODE => "BINUNICODE",
            .APPEND => "APPEND",
            .BUILD => "BUILD",
            .GLOBAL => "GLOBAL",
            .DICT => "DICT",
            .EMPTY_DICT => "EMPTY_DICT",
            .APPENDS => "APPENDS",
            .GET => "GET",
            .BINGET => "BINGET",
            .INST => "INST",
            .LONG_BINGET => "LONG_BINGET",
            .LIST => "LIST",
            .EMPTY_LIST => "EMPTY_LIST",
            .OBJ => "OBJ",
            .PUT => "PUT",
            .BINPUT => "BINPUT",
            .LONG_BINPUT => "LONG_BINPUT",
            .SETITEM => "SETITEM",
            .TUPLE => "TUPLE",
            .EMPTY_TUPLE => "EMPTY_TUPLE",
            .SETITEMS => "SETITEMS",
            .BINFLOAT => "BINFLOAT",
            .PROTO => "PROTO",
            .NEWOBJ => "NEWOBJ",
            .EXT1 => "EXT1",
            .EXT2 => "EXT2",
            .EXT4 => "EXT4",
            .TUPLE1 => "TUPLE1",
            .TUPLE2 => "TUPLE2",
            .TUPLE3 => "TUPLE3",
            .NEWTRUE => "NEWTRUE",
            .NEWFALSE => "NEWFALSE",
            .LONG1 => "LONG1",
            .LONG4 => "LONG4",
            .BINBYTES => "BINBYTES",
            .SHORT_BINBYTES => "SHORT_BINBYTES",
            .SHORT_BINUNICODE => "SHORT_BINUNICODE",
            .BINUNICODE8 => "BINUNICODE8",
            .BINBYTES8 => "BINBYTES8",
            .EMPTY_SET => "EMPTY_SET",
            .ADDITEMS => "ADDITEMS",
            .FROZENSET => "FROZENSET",
            .NEWOBJ_EX => "NEWOBJ_EX",
            .STACK_GLOBAL => "STACK_GLOBAL",
            .MEMOIZE => "MEMOIZE",
            .FRAME => "FRAME",
            .BYTEARRAY8 => "BYTEARRAY8",
            .NEXT_BUFFER => "NEXT_BUFFER",
            .READONLY_BUFFER => "READONLY_BUFFER",
            else => "UNKNOWN",
        };
    }

    pub fn doc(self: Opcode) []const u8 {
        return switch (self) {
            .MARK => "Push markobject onto the stack.",
            .STOP => "Stop the unpickling machine.",
            .POP => "Pop the top of the stack, discarding it.",
            .NONE => "Push None on the stack.",
            .NEWTRUE => "Push True on the stack.",
            .NEWFALSE => "Push False on the stack.",
            .INT => "Push an integer.",
            .BININT => "Push a 4-byte signed integer.",
            .BININT1 => "Push a 1-byte unsigned integer.",
            .BININT2 => "Push a 2-byte unsigned integer.",
            .FLOAT => "Push a float.",
            .BINFLOAT => "Push an 8-byte IEEE float.",
            .STRING => "Push a string.",
            .BINSTRING => "Push a counted string.",
            .SHORT_BINSTRING => "Push a short counted string.",
            .UNICODE => "Push a Unicode string.",
            .BINUNICODE => "Push a counted Unicode string.",
            .BINBYTES => "Push a counted bytes object.",
            .SHORT_BINBYTES => "Push a short counted bytes object.",
            .EMPTY_LIST => "Push an empty list.",
            .EMPTY_TUPLE => "Push an empty tuple.",
            .EMPTY_DICT => "Push an empty dict.",
            .EMPTY_SET => "Push an empty set.",
            .LIST => "Build a list from topmost stack items.",
            .TUPLE => "Build a tuple from topmost stack items.",
            .DICT => "Build a dict from stack items.",
            .APPEND => "Append an object to a list.",
            .APPENDS => "Extend a list by a slice of stack objects.",
            .SETITEM => "Add a key+value pair to a dict.",
            .SETITEMS => "Add key+value pairs to a dict.",
            .PROTO => "Protocol version indicator.",
            .FRAME => "Start a new frame.",
            else => "No documentation available.",
        };
    }

    pub fn protocol(self: Opcode) u8 {
        return switch (self) {
            .PROTO, .NEWOBJ, .EXT1, .EXT2, .EXT4, .TUPLE1, .TUPLE2, .TUPLE3, .NEWTRUE, .NEWFALSE, .LONG1, .LONG4 => 2,
            .BINBYTES, .SHORT_BINBYTES => 3,
            .SHORT_BINUNICODE, .BINUNICODE8, .BINBYTES8, .EMPTY_SET, .ADDITEMS, .FROZENSET, .NEWOBJ_EX, .STACK_GLOBAL, .MEMOIZE, .FRAME => 4,
            .BYTEARRAY8, .NEXT_BUFFER, .READONLY_BUFFER => 5,
            else => 0,
        };
    }
};

// ============================================================================
// Disassembly
// ============================================================================

/// Disassembled instruction
pub const OpcodeInfo = struct {
    opcode: Opcode,
    arg: ?Argument,
    pos: usize,
    proto: u8,

    pub const Argument = union(enum) {
        int: i64,
        uint: u64,
        float: f64,
        string: []const u8,
        bytes: []const u8,
        none,
    };
};

/// Disassemble pickle data
pub fn dis(allocator: std.mem.Allocator, pickle: []const u8, file: ?std.fs.File, memo: ?*anyopaque, indentlevel: usize, annotate: bool) !void {
    _ = memo;

    const writer = if (file) |f| f.writer() else std.io.getStdOut().writer();
    const indent = " " ** 4;
    _ = indent;

    var pos: usize = 0;
    var proto: u8 = 0;

    while (pos < pickle.len) {
        const op_byte = pickle[pos];
        const opcode: Opcode = @enumFromInt(op_byte);
        const op_name = opcode.name();

        // Print position
        var buf: [64]u8 = undefined;
        const pos_str = std.fmt.bufPrint(&buf, "{d: >5}: ", .{pos}) catch "";
        try writer.writeAll(pos_str);

        // Print indentation
        for (0..indentlevel) |_| {
            try writer.writeAll("    ");
        }

        // Print opcode name
        try writer.writeAll(op_name);

        // Parse and print argument
        pos += 1;
        var arg: ?[]const u8 = null;

        switch (opcode) {
            .PROTO => {
                if (pos < pickle.len) {
                    proto = pickle[pos];
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{proto}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 1;
                }
            },
            .BININT => {
                if (pos + 4 <= pickle.len) {
                    const val = std.mem.readInt(i32, pickle[pos..][0..4], .little);
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 4;
                }
            },
            .BININT1 => {
                if (pos < pickle.len) {
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{pickle[pos]}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 1;
                }
            },
            .BININT2 => {
                if (pos + 2 <= pickle.len) {
                    const val = std.mem.readInt(u16, pickle[pos..][0..2], .little);
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 2;
                }
            },
            .BINFLOAT => {
                if (pos + 8 <= pickle.len) {
                    const val = @as(f64, @bitCast(std.mem.readInt(u64, pickle[pos..][0..8], .big)));
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 8;
                }
            },
            .SHORT_BINSTRING, .SHORT_BINBYTES, .SHORT_BINUNICODE => {
                if (pos < pickle.len) {
                    const length = pickle[pos];
                    pos += 1;
                    if (pos + length <= pickle.len) {
                        arg = pickle[pos .. pos + length];
                        try writer.writeAll(" '");
                        try writer.writeAll(arg.?);
                        try writer.writeAll("'");
                        pos += length;
                    }
                }
            },
            .BINSTRING, .BINUNICODE, .BINBYTES => {
                if (pos + 4 <= pickle.len) {
                    const length = std.mem.readInt(u32, pickle[pos..][0..4], .little);
                    pos += 4;
                    if (pos + length <= pickle.len) {
                        arg = pickle[pos .. pos + length];
                        try writer.writeAll(" '");
                        if (arg.?.len <= 40) {
                            try writer.writeAll(arg.?);
                        } else {
                            try writer.writeAll(arg.?[0..40]);
                            try writer.writeAll("...");
                        }
                        try writer.writeAll("'");
                        pos += length;
                    }
                }
            },
            .BINGET, .BINPUT => {
                if (pos < pickle.len) {
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{pickle[pos]}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 1;
                }
            },
            .LONG_BINGET, .LONG_BINPUT => {
                if (pos + 4 <= pickle.len) {
                    const val = std.mem.readInt(u32, pickle[pos..][0..4], .little);
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 4;
                }
            },
            else => {},
        }

        // Print annotation
        if (annotate) {
            try writer.writeAll("  # ");
            try writer.writeAll(opcode.doc());
        }

        try writer.writeAll("\n");

        if (opcode == .STOP) break;
    }

    _ = allocator;
}

/// Generate optimization opportunities report
pub fn optimize(allocator: std.mem.Allocator, pickle: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var pos: usize = 0;
    var string_count: usize = 0;
    var list_count: usize = 0;
    var dict_count: usize = 0;

    while (pos < pickle.len) {
        const op: Opcode = @enumFromInt(pickle[pos]);
        pos += 1;

        switch (op) {
            .STRING, .SHORT_BINSTRING, .BINSTRING, .UNICODE, .BINUNICODE => {
                string_count += 1;
                // Skip argument
                if (op == .SHORT_BINSTRING or op == .SHORT_BINUNICODE) {
                    if (pos < pickle.len) pos += 1 + pickle[pos];
                } else if (op == .BINSTRING or op == .BINUNICODE) {
                    if (pos + 4 <= pickle.len) {
                        const len = std.mem.readInt(u32, pickle[pos..][0..4], .little);
                        pos += 4 + len;
                    }
                }
            },
            .LIST, .EMPTY_LIST => list_count += 1,
            .DICT, .EMPTY_DICT => dict_count += 1,
            .STOP => break,
            else => {},
        }
    }

    try result.appendSlice("Pickle statistics:\n");
    var buf: [256]u8 = undefined;
    const stats = std.fmt.bufPrint(&buf, "  Strings: {d}\n  Lists: {d}\n  Dicts: {d}\n", .{ string_count, list_count, dict_count }) catch "";
    try result.appendSlice(stats);

    return result.toOwnedSlice();
}

/// Get the protocol version of a pickle
pub fn getProtocol(pickle: []const u8) u8 {
    if (pickle.len >= 2 and pickle[0] == @intFromEnum(Opcode.PROTO)) {
        return pickle[1];
    }
    // Default to protocol 0 for old pickles
    return 0;
}

// ============================================================================
// Genops
// ============================================================================

/// Iterator over pickle opcodes
pub const OpcodeIterator = struct {
    const Self = @This();

    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Self {
        return .{ .data = data, .pos = 0 };
    }

    pub fn next(self: *Self) ?OpcodeInfo {
        if (self.pos >= self.data.len) return null;

        const start_pos = self.pos;
        const op: Opcode = @enumFromInt(self.data[self.pos]);
        self.pos += 1;

        var arg: ?OpcodeInfo.Argument = null;

        // Parse argument based on opcode
        switch (op) {
            .PROTO => {
                if (self.pos < self.data.len) {
                    arg = .{ .uint = self.data[self.pos] };
                    self.pos += 1;
                }
            },
            .BININT1 => {
                if (self.pos < self.data.len) {
                    arg = .{ .uint = self.data[self.pos] };
                    self.pos += 1;
                }
            },
            .BININT2 => {
                if (self.pos + 2 <= self.data.len) {
                    arg = .{ .uint = std.mem.readInt(u16, self.data[self.pos..][0..2], .little) };
                    self.pos += 2;
                }
            },
            .BININT => {
                if (self.pos + 4 <= self.data.len) {
                    arg = .{ .int = std.mem.readInt(i32, self.data[self.pos..][0..4], .little) };
                    self.pos += 4;
                }
            },
            else => {
                arg = .none;
            },
        }

        return OpcodeInfo{
            .opcode = op,
            .arg = arg,
            .pos = start_pos,
            .proto = op.protocol(),
        };
    }
};

/// Generate opcode sequence from pickle data
pub fn genops(data: []const u8) OpcodeIterator {
    return OpcodeIterator.init(data);
}

// ============================================================================
// Tests
// ============================================================================

test "Opcode names" {
    try std.testing.expectEqualStrings("MARK", Opcode.MARK.name());
    try std.testing.expectEqualStrings("STOP", Opcode.STOP.name());
    try std.testing.expectEqualStrings("PROTO", Opcode.PROTO.name());
    try std.testing.expectEqualStrings("NONE", Opcode.NONE.name());
}

test "Opcode protocol versions" {
    try std.testing.expectEqual(@as(u8, 0), Opcode.MARK.protocol());
    try std.testing.expectEqual(@as(u8, 2), Opcode.PROTO.protocol());
    try std.testing.expectEqual(@as(u8, 3), Opcode.BINBYTES.protocol());
    try std.testing.expectEqual(@as(u8, 4), Opcode.FRAME.protocol());
    try std.testing.expectEqual(@as(u8, 5), Opcode.BYTEARRAY8.protocol());
}

test "getProtocol" {
    // Protocol 2 pickle
    const pickle2 = [_]u8{ 0x80, 0x02, '.' };
    try std.testing.expectEqual(@as(u8, 2), getProtocol(&pickle2));

    // Protocol 0 pickle (no PROTO opcode)
    const pickle0 = [_]u8{ 'N', '.' };
    try std.testing.expectEqual(@as(u8, 0), getProtocol(&pickle0));
}

test "OpcodeIterator" {
    const pickle = [_]u8{ 0x80, 0x03, 'N', '.' };
    var iter = genops(&pickle);

    const op1 = iter.next().?;
    try std.testing.expectEqual(Opcode.PROTO, op1.opcode);
    try std.testing.expectEqual(@as(u64, 3), op1.arg.?.uint);

    const op2 = iter.next().?;
    try std.testing.expectEqual(Opcode.NONE, op2.opcode);

    const op3 = iter.next().?;
    try std.testing.expectEqual(Opcode.STOP, op3.opcode);

    try std.testing.expect(iter.next() == null);
}

test "optimize" {
    const allocator = std.testing.allocator;
    const pickle = [_]u8{ 0x80, 0x03, 'N', '.' };
    const result = try optimize(allocator, &pickle);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "statistics") != null);
}
