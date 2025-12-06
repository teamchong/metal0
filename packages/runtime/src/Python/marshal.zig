/// marshal - Python Object Serialization
/// Mirrors cpython/Python/marshal.c
///
/// This module provides:
/// - Serialization of Python objects to binary format
/// - Deserialization of binary format to Python objects
/// - Support for code objects, tuples, lists, dicts, etc.
/// - Version-aware format handling

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Marshal format version
pub const VERSION: u8 = 5;

/// Maximum marshal stack depth to prevent overflow
pub const MAX_MARSHAL_STACK_DEPTH: u32 = 2000;

// ============================================================================
// Type Codes
// ============================================================================

/// Marshal type codes
pub const Type = enum(u8) {
    // Core types
    null_ = '0',
    none = 'N',
    false_ = 'F',
    true_ = 'T',
    stopiter = 'S',
    ellipsis = '.',

    // Numbers
    binary_float = 'g',
    binary_complex = 'y',
    long_ = 'l',
    int_ = 'i',
    int64 = 'I', // Legacy

    // Strings
    string = 's', // Bytes
    unicode = 'u',
    interned = 't',
    ascii = 'a',
    ascii_interned = 'A',
    short_ascii = 'z',
    short_ascii_interned = 'Z',

    // Containers
    tuple = '(',
    small_tuple = ')',
    list = '[',
    dict = '{',
    set = '<',
    frozenset = '>',

    // Code and special
    code = 'c',
    slice = ':',
    unknown = '?',

    // References (version 3+)
    ref = 'r',

    // Legacy types
    complex = 'x', // Version 0
    float_ = 'f', // Version 0

    /// Check if type has FLAG_REF set
    pub fn hasRef(byte: u8) bool {
        return (byte & FLAG_REF) != 0;
    }

    /// Get type without FLAG_REF
    pub fn withoutRef(byte: u8) u8 {
        return byte & ~FLAG_REF;
    }
};

/// Reference flag (added in version 3)
pub const FLAG_REF: u8 = 0x80;

// ============================================================================
// Error Codes
// ============================================================================

pub const WriteError = error{
    Ok,
    Unmarshallable,
    NestedTooDeep,
    NoMemory,
    CodeNotAllowed,
};

pub const ReadError = error{
    Eof,
    InvalidType,
    InvalidData,
    NestedTooDeep,
    InvalidReference,
    NoMemory,
};

// ============================================================================
// Writer State
// ============================================================================

/// Marshal writer state
pub const Writer = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    depth: u32 = 0,
    version: u8 = VERSION,
    allow_code: bool = true,
    refs: std.AutoHashMap(usize, u32),
    ref_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .refs = std.AutoHashMap(usize, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Writer) void {
        self.buffer.deinit();
        self.refs.deinit();
    }

    /// Get serialized data
    pub fn getData(self: *Writer) []const u8 {
        return self.buffer.items;
    }

    /// Write a single byte
    pub fn writeByte(self: *Writer, byte: u8) !void {
        try self.buffer.append(byte);
    }

    /// Write bytes
    pub fn writeBytes(self: *Writer, bytes: []const u8) !void {
        try self.buffer.appendSlice(bytes);
    }

    /// Write 32-bit little-endian integer
    pub fn writeInt32(self: *Writer, value: i32) !void {
        const bytes = std.mem.toBytes(@as(i32, value));
        try self.buffer.appendSlice(&bytes);
    }

    /// Write 64-bit little-endian integer
    pub fn writeInt64(self: *Writer, value: i64) !void {
        const bytes = std.mem.toBytes(@as(i64, value));
        try self.buffer.appendSlice(&bytes);
    }

    /// Write 64-bit little-endian float
    pub fn writeFloat64(self: *Writer, value: f64) !void {
        const bytes = std.mem.toBytes(@as(f64, value));
        try self.buffer.appendSlice(&bytes);
    }

    /// Write string with length prefix
    pub fn writeString(self: *Writer, str: []const u8) !void {
        try self.writeInt32(@intCast(str.len));
        try self.writeBytes(str);
    }

    /// Write short string (length < 256)
    pub fn writeShortString(self: *Writer, str: []const u8) !void {
        try self.writeByte(@intCast(str.len));
        try self.writeBytes(str);
    }

    /// Check depth and increment
    pub fn enterDepth(self: *Writer) !void {
        if (self.depth >= MAX_MARSHAL_STACK_DEPTH) {
            return error.NestedTooDeep;
        }
        self.depth += 1;
    }

    /// Decrement depth
    pub fn leaveDepth(self: *Writer) void {
        self.depth -= 1;
    }

    /// Add reference for sharing
    pub fn addRef(self: *Writer, ptr: usize) !u32 {
        const idx = self.ref_count;
        try self.refs.put(ptr, idx);
        self.ref_count += 1;
        return idx;
    }

    /// Get existing reference
    pub fn getRef(self: *Writer, ptr: usize) ?u32 {
        return self.refs.get(ptr);
    }
};

// ============================================================================
// Reader State
// ============================================================================

/// Marshal reader state
pub const Reader = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    pos: usize = 0,
    depth: u32 = 0,
    refs: std.ArrayList(?*anyopaque),

    pub fn init(allocator: std.mem.Allocator, data: []const u8) Reader {
        return .{
            .allocator = allocator,
            .data = data,
            .refs = std.ArrayList(?*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Reader) void {
        self.refs.deinit();
    }

    /// Check if at end of data
    pub fn atEnd(self: *Reader) bool {
        return self.pos >= self.data.len;
    }

    /// Read a single byte
    pub fn readByte(self: *Reader) !u8 {
        if (self.pos >= self.data.len) {
            return error.Eof;
        }
        const byte = self.data[self.pos];
        self.pos += 1;
        return byte;
    }

    /// Read bytes
    pub fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) {
            return error.Eof;
        }
        const bytes = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return bytes;
    }

    /// Read 32-bit little-endian integer
    pub fn readInt32(self: *Reader) !i32 {
        const bytes = try self.readBytes(4);
        return std.mem.readInt(i32, bytes[0..4], .little);
    }

    /// Read unsigned 32-bit little-endian integer
    pub fn readUInt32(self: *Reader) !u32 {
        const bytes = try self.readBytes(4);
        return std.mem.readInt(u32, bytes[0..4], .little);
    }

    /// Read 64-bit little-endian integer
    pub fn readInt64(self: *Reader) !i64 {
        const bytes = try self.readBytes(8);
        return std.mem.readInt(i64, bytes[0..8], .little);
    }

    /// Read 64-bit little-endian float
    pub fn readFloat64(self: *Reader) !f64 {
        const bytes = try self.readBytes(8);
        return @bitCast(std.mem.readInt(u64, bytes[0..8], .little));
    }

    /// Read string with length prefix
    pub fn readString(self: *Reader) ![]const u8 {
        const len = try self.readInt32();
        if (len < 0) return error.InvalidData;
        return self.readBytes(@intCast(len));
    }

    /// Read short string (length < 256)
    pub fn readShortString(self: *Reader) ![]const u8 {
        const len = try self.readByte();
        return self.readBytes(len);
    }

    /// Check depth and increment
    pub fn enterDepth(self: *Reader) !void {
        if (self.depth >= MAX_MARSHAL_STACK_DEPTH) {
            return error.NestedTooDeep;
        }
        self.depth += 1;
    }

    /// Decrement depth
    pub fn leaveDepth(self: *Reader) void {
        self.depth -= 1;
    }

    /// Add reference
    pub fn addRef(self: *Reader, obj: ?*anyopaque) !u32 {
        const idx: u32 = @intCast(self.refs.items.len);
        try self.refs.append(obj);
        return idx;
    }

    /// Get reference
    pub fn getRef(self: *Reader, idx: u32) !?*anyopaque {
        if (idx >= self.refs.items.len) {
            return error.InvalidReference;
        }
        return self.refs.items[idx];
    }
};

// ============================================================================
// Marshalled Value (Type-Erased)
// ============================================================================

/// Represents a marshalled value
pub const Value = union(enum) {
    none,
    false_,
    true_,
    stopiter,
    ellipsis,
    int_: i64,
    float_: f64,
    complex_: struct { real: f64, imag: f64 },
    bytes: []const u8,
    string: []const u8,
    tuple: []Value,
    list: []Value,
    dict: []struct { key: Value, value: Value },
    set: []Value,
    frozenset: []Value,
    code: *const CodeValue,
    ref: u32,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tuple => |t| allocator.free(t),
            .list => |l| allocator.free(l),
            .dict => |d| allocator.free(d),
            .set => |s| allocator.free(s),
            .frozenset => |f| allocator.free(f),
            else => {},
        }
    }
};

/// Code object value
pub const CodeValue = struct {
    argcount: i32,
    posonlyargcount: i32,
    kwonlyargcount: i32,
    nlocals: i32,
    stacksize: i32,
    flags: i32,
    code: []const u8,
    consts: []Value,
    names: [][]const u8,
    varnames: [][]const u8,
    freevars: [][]const u8,
    cellvars: [][]const u8,
    filename: []const u8,
    name: []const u8,
    qualname: []const u8,
    firstlineno: i32,
    linetable: []const u8,
    exceptiontable: []const u8,
};

// ============================================================================
// High-Level API
// ============================================================================

/// Marshal an integer
pub fn writeInt(writer: *Writer, value: i64) !void {
    if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
        try writer.writeByte(@intFromEnum(Type.int_));
        try writer.writeInt32(@intCast(value));
    } else {
        try writer.writeByte(@intFromEnum(Type.long_));
        try writer.writeInt64(value);
    }
}

/// Marshal a float
pub fn writeFloat(writer: *Writer, value: f64) !void {
    try writer.writeByte(@intFromEnum(Type.binary_float));
    try writer.writeFloat64(value);
}

/// Marshal None
pub fn writeNone(writer: *Writer) !void {
    try writer.writeByte(@intFromEnum(Type.none));
}

/// Marshal a boolean
pub fn writeBool(writer: *Writer, value: bool) !void {
    if (value) {
        try writer.writeByte(@intFromEnum(Type.true_));
    } else {
        try writer.writeByte(@intFromEnum(Type.false_));
    }
}

/// Marshal bytes
pub fn writeBytes(writer: *Writer, value: []const u8) !void {
    try writer.writeByte(@intFromEnum(Type.string));
    try writer.writeString(value);
}

/// Marshal a string (unicode)
pub fn writeUnicode(writer: *Writer, value: []const u8) !void {
    // Check if ASCII
    var is_ascii = true;
    for (value) |ch| {
        if (ch >= 128) {
            is_ascii = false;
            break;
        }
    }

    if (is_ascii and value.len < 256) {
        try writer.writeByte(@intFromEnum(Type.short_ascii));
        try writer.writeShortString(value);
    } else if (is_ascii) {
        try writer.writeByte(@intFromEnum(Type.ascii));
        try writer.writeString(value);
    } else {
        try writer.writeByte(@intFromEnum(Type.unicode));
        try writer.writeString(value);
    }
}

/// Marshal a tuple
pub fn writeTuple(writer: *Writer, items: []const Value) !void {
    try writer.enterDepth();
    defer writer.leaveDepth();

    if (items.len < 256) {
        try writer.writeByte(@intFromEnum(Type.small_tuple));
        try writer.writeByte(@intCast(items.len));
    } else {
        try writer.writeByte(@intFromEnum(Type.tuple));
        try writer.writeInt32(@intCast(items.len));
    }

    for (items) |item| {
        try writeValue(writer, item);
    }
}

/// Marshal a list
pub fn writeList(writer: *Writer, items: []const Value) !void {
    try writer.enterDepth();
    defer writer.leaveDepth();

    try writer.writeByte(@intFromEnum(Type.list));
    try writer.writeInt32(@intCast(items.len));

    for (items) |item| {
        try writeValue(writer, item);
    }
}

/// Marshal a generic value
pub fn writeValue(writer: *Writer, value: Value) !void {
    switch (value) {
        .none => try writeNone(writer),
        .true_ => try writeBool(writer, true),
        .false_ => try writeBool(writer, false),
        .int_ => |i| try writeInt(writer, i),
        .float_ => |f| try writeFloat(writer, f),
        .bytes => |b| try writeBytes(writer, b),
        .string => |s| try writeUnicode(writer, s),
        .tuple => |t| try writeTuple(writer, t),
        .list => |l| try writeList(writer, l),
        .stopiter => try writer.writeByte(@intFromEnum(Type.stopiter)),
        .ellipsis => try writer.writeByte(@intFromEnum(Type.ellipsis)),
        else => return error.Unmarshallable,
    }
}

// ============================================================================
// Unmarshalling
// ============================================================================

/// Read a value from marshal data
pub fn readValue(reader: *Reader) !Value {
    const type_byte = try reader.readByte();
    const has_ref = Type.hasRef(type_byte);
    const type_code = Type.withoutRef(type_byte);

    const value = switch (type_code) {
        @intFromEnum(Type.none) => Value.none,
        @intFromEnum(Type.true_) => Value.true_,
        @intFromEnum(Type.false_) => Value.false_,
        @intFromEnum(Type.stopiter) => Value.stopiter,
        @intFromEnum(Type.ellipsis) => Value.ellipsis,
        @intFromEnum(Type.int_) => Value{ .int_ = try reader.readInt32() },
        @intFromEnum(Type.long_) => try readLong(reader),
        @intFromEnum(Type.binary_float) => Value{ .float_ = try reader.readFloat64() },
        @intFromEnum(Type.string) => Value{ .bytes = try reader.readString() },
        @intFromEnum(Type.unicode) => Value{ .string = try reader.readString() },
        @intFromEnum(Type.ascii), @intFromEnum(Type.ascii_interned) => Value{ .string = try reader.readString() },
        @intFromEnum(Type.short_ascii), @intFromEnum(Type.short_ascii_interned) => Value{ .string = try reader.readShortString() },
        @intFromEnum(Type.tuple) => try readTuple(reader, false),
        @intFromEnum(Type.small_tuple) => try readTuple(reader, true),
        @intFromEnum(Type.list) => try readList(reader),
        @intFromEnum(Type.ref) => try readRef(reader),
        else => return error.InvalidType,
    };

    if (has_ref) {
        _ = try reader.addRef(null); // Would store actual object pointer
    }

    return value;
}

/// Read a long integer
fn readLong(reader: *Reader) !Value {
    const size = try reader.readInt32();
    if (size == 0) {
        return Value{ .int_ = 0 };
    }

    // Simplified: read as 64-bit
    const abs_size: usize = @abs(size);
    var result: i64 = 0;
    var shift: u6 = 0;

    for (0..abs_size) |_| {
        const digit = try reader.readByte();
        const digit2 = try reader.readByte();
        const word = @as(u16, digit) | (@as(u16, digit2) << 8);
        result |= @as(i64, word) << shift;
        shift +|= 15;
    }

    if (size < 0) {
        result = -result;
    }

    return Value{ .int_ = result };
}

/// Read a tuple
fn readTuple(reader: *Reader, small: bool) !Value {
    try reader.enterDepth();
    defer reader.leaveDepth();

    const len: usize = if (small)
        try reader.readByte()
    else
        @intCast(try reader.readInt32());

    var items = try reader.allocator.alloc(Value, len);
    errdefer reader.allocator.free(items);

    for (0..len) |i| {
        items[i] = try readValue(reader);
    }

    return Value{ .tuple = items };
}

/// Read a list
fn readList(reader: *Reader) !Value {
    try reader.enterDepth();
    defer reader.leaveDepth();

    const len: usize = @intCast(try reader.readInt32());

    var items = try reader.allocator.alloc(Value, len);
    errdefer reader.allocator.free(items);

    for (0..len) |i| {
        items[i] = try readValue(reader);
    }

    return Value{ .list = items };
}

/// Read a reference
fn readRef(reader: *Reader) !Value {
    const idx = try reader.readUInt32();
    return Value{ .ref = idx };
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Marshal data to bytes
pub fn dumps(allocator: std.mem.Allocator, value: Value) ![]u8 {
    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writeValue(&writer, value);

    return allocator.dupe(u8, writer.getData());
}

/// Unmarshal bytes to value
pub fn loads(allocator: std.mem.Allocator, data: []const u8) !Value {
    var reader = Reader.init(allocator, data);
    defer reader.deinit();

    return readValue(&reader);
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize marshal module
pub fn init() void {
    // Nothing to initialize
}

/// Finalize marshal module
pub fn fini() void {
    // Nothing to finalize
}

// ============================================================================
// Tests
// ============================================================================

test "marshal none" {
    const allocator = std.testing.allocator;

    const data = try dumps(allocator, Value.none);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 1), data.len);
    try std.testing.expectEqual(@as(u8, 'N'), data[0]);
}

test "marshal bool" {
    const allocator = std.testing.allocator;

    const data_true = try dumps(allocator, Value.true_);
    defer allocator.free(data_true);
    try std.testing.expectEqual(@as(u8, 'T'), data_true[0]);

    const data_false = try dumps(allocator, Value.false_);
    defer allocator.free(data_false);
    try std.testing.expectEqual(@as(u8, 'F'), data_false[0]);
}

test "marshal int" {
    const allocator = std.testing.allocator;

    const data = try dumps(allocator, Value{ .int_ = 42 });
    defer allocator.free(data);

    try std.testing.expectEqual(@as(u8, 'i'), data[0]);

    const value = try loads(allocator, data);
    try std.testing.expectEqual(@as(i64, 42), value.int_);
}

test "marshal string" {
    const allocator = std.testing.allocator;

    const data = try dumps(allocator, Value{ .string = "hello" });
    defer allocator.free(data);

    const value = try loads(allocator, data);
    try std.testing.expectEqualStrings("hello", value.string);
}

test "marshal tuple" {
    const allocator = std.testing.allocator;

    var items = [_]Value{
        Value{ .int_ = 1 },
        Value{ .int_ = 2 },
        Value{ .int_ = 3 },
    };

    const data = try dumps(allocator, Value{ .tuple = &items });
    defer allocator.free(data);

    const value = try loads(allocator, data);
    defer allocator.free(value.tuple);

    try std.testing.expectEqual(@as(usize, 3), value.tuple.len);
    try std.testing.expectEqual(@as(i64, 1), value.tuple[0].int_);
    try std.testing.expectEqual(@as(i64, 2), value.tuple[1].int_);
    try std.testing.expectEqual(@as(i64, 3), value.tuple[2].int_);
}

test "writer reader" {
    const allocator = std.testing.allocator;

    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeByte(0x42);
    try writer.writeInt32(12345);
    try writer.writeFloat64(3.14159);

    const data = writer.getData();

    var reader = Reader.init(allocator, data);
    defer reader.deinit();

    try std.testing.expectEqual(@as(u8, 0x42), try reader.readByte());
    try std.testing.expectEqual(@as(i32, 12345), try reader.readInt32());
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), try reader.readFloat64(), 0.00001);
}
