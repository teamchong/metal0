/// marshal/writer - Writer state and serialization operations
/// Mirrors cpython/Python/marshal.c write operations

const std = @import("std");
const types = @import("types.zig");

pub const Type = types.Type;
pub const Value = types.Value;
pub const MAX_MARSHAL_STACK_DEPTH = types.MAX_MARSHAL_STACK_DEPTH;
pub const VERSION = types.VERSION;

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
// Write Operations
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
