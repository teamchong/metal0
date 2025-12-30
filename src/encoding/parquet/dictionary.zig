//! Dictionary encoding decoder for Parquet.
//!
//! Dictionary encoding stores unique values in a dictionary page, then
//! references them by index in data pages. Indices are encoded using
//! RLE/bit-packing hybrid encoding.
//!
//! See: https://parquet.apache.org/docs/file-format/data-pages/encodings/#dictionary-encoding-plain_dictionary--2-and-rle_dictionary--8

const std = @import("std");
const rle = @import("rle.zig");
const RleDecoder = rle.RleDecoder;
const plain = @import("plain.zig");
const PlainDecoder = plain.PlainDecoder;

pub const DictionaryError = error{
    UnexpectedEndOfData,
    InvalidEncoding,
    InvalidIndex,
    OutOfMemory,
};

/// Dictionary of INT32 values
pub const Int32Dictionary = struct {
    values: []i32,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create dictionary from PLAIN-encoded data
    pub fn init(data: []const u8, num_values: usize, allocator: std.mem.Allocator) DictionaryError!Self {
        var decoder = PlainDecoder.init(data);
        const values = decoder.readInt32(num_values, allocator) catch |err| {
            return switch (err) {
                error.UnexpectedEndOfData => DictionaryError.UnexpectedEndOfData,
                error.OutOfMemory => DictionaryError.OutOfMemory,
                else => DictionaryError.InvalidEncoding,
            };
        };

        return .{
            .values = values,
            .allocator = allocator,
        };
    }

    /// Look up values by indices
    pub fn lookup(self: Self, indices: []const u32, allocator: std.mem.Allocator) DictionaryError![]i32 {
        const result = try allocator.alloc(i32, indices.len);
        errdefer allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= self.values.len) {
                return DictionaryError.InvalidIndex;
            }
            result[i] = self.values[idx];
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }
};

/// Dictionary of INT64 values
pub const Int64Dictionary = struct {
    values: []i64,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(data: []const u8, num_values: usize, allocator: std.mem.Allocator) DictionaryError!Self {
        var decoder = PlainDecoder.init(data);
        const values = decoder.readInt64(num_values, allocator) catch |err| {
            return switch (err) {
                error.UnexpectedEndOfData => DictionaryError.UnexpectedEndOfData,
                error.OutOfMemory => DictionaryError.OutOfMemory,
                else => DictionaryError.InvalidEncoding,
            };
        };

        return .{
            .values = values,
            .allocator = allocator,
        };
    }

    pub fn lookup(self: Self, indices: []const u32, allocator: std.mem.Allocator) DictionaryError![]i64 {
        const result = try allocator.alloc(i64, indices.len);
        errdefer allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= self.values.len) {
                return DictionaryError.InvalidIndex;
            }
            result[i] = self.values[idx];
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }
};

/// Dictionary of FLOAT values
pub const FloatDictionary = struct {
    values: []f32,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(data: []const u8, num_values: usize, allocator: std.mem.Allocator) DictionaryError!Self {
        var decoder = PlainDecoder.init(data);
        const values = decoder.readFloat(num_values, allocator) catch |err| {
            return switch (err) {
                error.UnexpectedEndOfData => DictionaryError.UnexpectedEndOfData,
                error.OutOfMemory => DictionaryError.OutOfMemory,
                else => DictionaryError.InvalidEncoding,
            };
        };

        return .{
            .values = values,
            .allocator = allocator,
        };
    }

    pub fn lookup(self: Self, indices: []const u32, allocator: std.mem.Allocator) DictionaryError![]f32 {
        const result = try allocator.alloc(f32, indices.len);
        errdefer allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= self.values.len) {
                return DictionaryError.InvalidIndex;
            }
            result[i] = self.values[idx];
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }
};

/// Dictionary of DOUBLE values
pub const DoubleDictionary = struct {
    values: []f64,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(data: []const u8, num_values: usize, allocator: std.mem.Allocator) DictionaryError!Self {
        var decoder = PlainDecoder.init(data);
        const values = decoder.readDouble(num_values, allocator) catch |err| {
            return switch (err) {
                error.UnexpectedEndOfData => DictionaryError.UnexpectedEndOfData,
                error.OutOfMemory => DictionaryError.OutOfMemory,
                else => DictionaryError.InvalidEncoding,
            };
        };

        return .{
            .values = values,
            .allocator = allocator,
        };
    }

    pub fn lookup(self: Self, indices: []const u32, allocator: std.mem.Allocator) DictionaryError![]f64 {
        const result = try allocator.alloc(f64, indices.len);
        errdefer allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= self.values.len) {
                return DictionaryError.InvalidIndex;
            }
            result[i] = self.values[idx];
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }
};

/// Dictionary of BYTE_ARRAY (string) values
pub const ByteArrayDictionary = struct {
    values: [][]const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(data: []const u8, num_values: usize, allocator: std.mem.Allocator) DictionaryError!Self {
        var decoder = PlainDecoder.init(data);
        const values = decoder.readByteArray(num_values, allocator) catch |err| {
            return switch (err) {
                error.UnexpectedEndOfData => DictionaryError.UnexpectedEndOfData,
                error.OutOfMemory => DictionaryError.OutOfMemory,
                else => DictionaryError.InvalidEncoding,
            };
        };

        return .{
            .values = values,
            .allocator = allocator,
        };
    }

    pub fn lookup(self: Self, indices: []const u32, allocator: std.mem.Allocator) DictionaryError![][]const u8 {
        const result = try allocator.alloc([]const u8, indices.len);
        errdefer allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= self.values.len) {
                return DictionaryError.InvalidIndex;
            }
            result[i] = self.values[idx];
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }
};

/// Decode RLE-encoded dictionary indices
/// First byte is bit_width, followed by RLE-encoded indices
pub fn decodeIndices(
    data: []const u8,
    count: usize,
    allocator: std.mem.Allocator,
) DictionaryError![]u32 {
    if (data.len < 1) {
        return DictionaryError.UnexpectedEndOfData;
    }

    const bit_width: u6 = @intCast(data[0]);
    var decoder = RleDecoder.init(data[1..], bit_width);

    const indices = decoder.decode(count, allocator) catch |err| {
        return switch (err) {
            error.UnexpectedEndOfData => DictionaryError.UnexpectedEndOfData,
            error.InvalidEncoding => DictionaryError.InvalidEncoding,
            error.OutOfMemory => DictionaryError.OutOfMemory,
        };
    };

    return indices;
}

// ============================================================================
// Tests
// ============================================================================

test "int32 dictionary" {
    // Dictionary with values [10, 20, 30]
    const dict_data = [_]u8{
        0x0A, 0x00, 0x00, 0x00, // 10
        0x14, 0x00, 0x00, 0x00, // 20
        0x1E, 0x00, 0x00, 0x00, // 30
    };

    var dict = try Int32Dictionary.init(&dict_data, 3, std.testing.allocator);
    defer dict.deinit();

    // Look up indices [0, 2, 1, 0]
    const indices = [_]u32{ 0, 2, 1, 0 };
    const result = try dict.lookup(&indices, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(i32, 10), result[0]);
    try std.testing.expectEqual(@as(i32, 30), result[1]);
    try std.testing.expectEqual(@as(i32, 20), result[2]);
    try std.testing.expectEqual(@as(i32, 10), result[3]);
}

test "byte_array dictionary" {
    // Dictionary with values ["foo", "bar"]
    const dict_data = [_]u8{
        0x03, 0x00, 0x00, 0x00, // length 3
        'f',  'o',  'o', // "foo"
        0x03, 0x00, 0x00, 0x00, // length 3
        'b',  'a',  'r', // "bar"
    };

    var dict = try ByteArrayDictionary.init(&dict_data, 2, std.testing.allocator);
    defer dict.deinit();

    // Look up indices [1, 0, 1]
    const indices = [_]u32{ 1, 0, 1 };
    const result = try dict.lookup(&indices, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("bar", result[0]);
    try std.testing.expectEqualStrings("foo", result[1]);
    try std.testing.expectEqualStrings("bar", result[2]);
}

test "decode indices" {
    // bit_width=2, then RLE run of 4 values of 1
    // indicator = 4 << 1 = 8
    // value = 1 (1 byte for bit_width=2)
    const data = [_]u8{ 0x02, 0x08, 0x01 };

    const indices = try decodeIndices(&data, 4, std.testing.allocator);
    defer std.testing.allocator.free(indices);

    try std.testing.expectEqual(@as(usize, 4), indices.len);
    for (indices) |idx| {
        try std.testing.expectEqual(@as(u32, 1), idx);
    }
}
