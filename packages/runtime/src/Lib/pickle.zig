//! pickle - Object serialization module
//! Reference: cpython/Lib/pickle.py
//!
//! CPython __all__: PickleError, PicklingError, UnpicklingError, Pickler,
//!                  Unpickler, dump, dumps, load, loads, HIGHEST_PROTOCOL,
//!                  DEFAULT_PROTOCOL
//!
//! The pickle module implements binary protocols for serializing and
//! de-serializing Python object structures.

const std = @import("std");

// ============================================================================
// Protocol Versions
// ============================================================================

/// Highest protocol version supported
pub const HIGHEST_PROTOCOL: u8 = 5;

/// Default protocol version
pub const DEFAULT_PROTOCOL: u8 = 4;

// ============================================================================
// Errors
// ============================================================================

pub const PickleError = error{
    PicklingError,
    UnpicklingError,
    InvalidProtocol,
    InvalidOpcode,
    StackUnderflow,
    UnpicklingNotSupported,
};

pub const PicklingError = error{
    PicklingError,
    NotPicklable,
    RecursionLimit,
};

pub const UnpicklingError = error{
    UnpicklingError,
    InvalidOpcode,
    StackUnderflow,
    UnpicklingNotSupported,
};

// ============================================================================
// Opcodes (pickle protocol)
// ============================================================================

pub const Opcode = enum(u8) {
    // Protocol 0 and 1
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
};

// ============================================================================
// Pickler
// ============================================================================

/// Object for pickling data
pub const Pickler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    protocol: u8,
    buffer: std.ArrayList(u8),
    memo: std.AutoHashMap(usize, u32),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .protocol = DEFAULT_PROTOCOL,
            .buffer = std.ArrayList(u8).init(allocator),
            .memo = std.AutoHashMap(usize, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.memo.deinit();
    }

    /// Pickle an integer
    pub fn pickleInt(self: *Self, value: i64) !void {
        if (value >= 0 and value < 256) {
            try self.buffer.append(@intFromEnum(Opcode.BININT1));
            try self.buffer.append(@intCast(value));
        } else if (value >= 0 and value < 65536) {
            try self.buffer.append(@intFromEnum(Opcode.BININT2));
            try self.buffer.appendSlice(&std.mem.toBytes(@as(u16, @intCast(value))));
        } else {
            try self.buffer.append(@intFromEnum(Opcode.BININT));
            try self.buffer.appendSlice(&std.mem.toBytes(@as(i32, @intCast(value))));
        }
    }

    /// Pickle None
    pub fn pickleNone(self: *Self) !void {
        try self.buffer.append(@intFromEnum(Opcode.NONE));
    }

    /// Pickle a boolean
    pub fn pickleBool(self: *Self, value: bool) !void {
        try self.buffer.append(if (value)
            @intFromEnum(Opcode.NEWTRUE)
        else
            @intFromEnum(Opcode.NEWFALSE));
    }

    /// Get pickled data
    pub fn getBytes(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Clear and reset
    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.memo.clearRetainingCapacity();
    }
};

// ============================================================================
// Unpickler
// ============================================================================

/// Object for unpickling data
pub const Unpickler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: []const u8,
    pos: usize,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) Self {
        return Self{
            .allocator = allocator,
            .data = data,
            .pos = 0,
        };
    }

    fn readByte(self: *Self) !u8 {
        if (self.pos >= self.data.len) {
            return UnpicklingError.StackUnderflow;
        }
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }
};

// ============================================================================
// Top-level functions
// ============================================================================

/// Serialize object to bytes
pub fn dumps(allocator: std.mem.Allocator, obj: anytype, protocol: ?u8) ![]const u8 {
    _ = protocol;
    var pickler = Pickler.init(allocator);
    defer pickler.deinit();

    const T = @TypeOf(obj);
    if (T == void or @typeInfo(T) == .null) {
        try pickler.pickleNone();
    } else if (T == bool) {
        try pickler.pickleBool(obj);
    } else if (@typeInfo(T) == .int) {
        try pickler.pickleInt(@intCast(obj));
    } else {
        return PicklingError.NotPicklable;
    }

    // Add STOP opcode
    try pickler.buffer.append(@intFromEnum(Opcode.STOP));

    return try allocator.dupe(u8, pickler.getBytes());
}

/// Deserialize bytes to object (returns raw bytes for now)
pub fn loads(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    _ = allocator;
    // Basic validation
    if (data.len == 0) {
        return UnpicklingError.UnpicklingNotSupported;
    }
    // For now, just return the data as-is
    // Full unpickling requires runtime type system
    return data;
}

/// Write pickled object to file
pub fn dump(allocator: std.mem.Allocator, obj: anytype, file: std.fs.File, protocol: ?u8) !void {
    const data = try dumps(allocator, obj, protocol);
    defer allocator.free(data);
    try file.writeAll(data);
}

/// Load pickled object from file
pub fn load(allocator: std.mem.Allocator, file: std.fs.File) ![]const u8 {
    const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);
    return loads(allocator, data);
}

// ============================================================================
// Tests
// ============================================================================

test "Pickler basic" {
    const allocator = std.testing.allocator;
    var pickler = Pickler.init(allocator);
    defer pickler.deinit();

    try pickler.pickleNone();
    try pickler.pickleBool(true);
    try pickler.pickleInt(42);

    try std.testing.expect(pickler.getBytes().len > 0);
}

test "dumps int" {
    const allocator = std.testing.allocator;
    const data = try dumps(allocator, @as(i32, 42), null);
    defer allocator.free(data);
    try std.testing.expect(data.len > 0);
}
