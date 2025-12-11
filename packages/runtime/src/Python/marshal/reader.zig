/// marshal/reader - Reader state and deserialization operations
/// Mirrors cpython/Python/marshal.c read operations

const std = @import("std");
const types = @import("types.zig");

pub const Type = types.Type;
pub const Value = types.Value;
pub const MAX_MARSHAL_STACK_DEPTH = types.MAX_MARSHAL_STACK_DEPTH;

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
// Read Operations
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
