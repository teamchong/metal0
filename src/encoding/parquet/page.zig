//! Parquet page reader.
//!
//! Reads and decodes pages from column chunks.
//! See: https://parquet.apache.org/docs/file-format/data-pages/

const std = @import("std");
const proto = @import("lanceql.proto");
const ThriftDecoder = proto.ThriftDecoder;
const format = @import("lanceql.format");
const meta = format.parquet_metadata;
const PageHeader = meta.PageHeader;
const PageType = meta.PageType;
const Encoding = meta.Encoding;
const Type = meta.Type;
const CompressionCodec = meta.CompressionCodec;
const plain = @import("plain.zig");
const PlainDecoder = plain.PlainDecoder;
const dictionary = @import("dictionary.zig");
const rle = @import("rle.zig");
const RleDecoder = rle.RleDecoder;
const snappy = @import("snappy.zig");

/// Comptime-specialized bit unpacking for a single group of 8 values
/// All bit offsets and masks computed at compile time
inline fn unpackGroupComptime(
    comptime bit_width: comptime_int,
    comptime T: type,
    group_bytes: []const u8,
    dict: []const T,
    output: []T,
    idx: *usize,
    count: usize,
) PageError!void {
    const mask: u32 = comptime (1 << bit_width) - 1;

    // Read group bytes into u64 (max 8 bytes needed for bit_width <= 8)
    var group_val: u64 = 0;
    inline for (0..@min(8, bit_width)) |b| {
        if (b < group_bytes.len) {
            group_val |= @as(u64, group_bytes[b]) << @intCast(b * 8);
        }
    }

    // Extract 8 values with comptime-known offsets
    inline for (0..8) |v| {
        if (idx.* >= count) return;
        const bit_offset = comptime v * bit_width;
        const dict_idx: u32 = @truncate((group_val >> @intCast(bit_offset)) & mask);
        if (dict_idx >= dict.len) return PageError.InvalidIndex;
        output[idx.*] = dict[dict_idx];
        idx.* += 1;
    }
}

/// Fused RLE decode + dictionary lookup - eliminates intermediate allocation
/// Decodes RLE-encoded indices and looks up dictionary values in one pass
fn decodeDictFused(comptime T: type, data: []const u8, bit_width: usize, dict: []const T, output: []T) PageError!void {
    // Dispatch to comptime-specialized version for common bit widths
    return switch (bit_width) {
        1 => decodeDictFusedComptime(T, 1, data, dict, output),
        2 => decodeDictFusedComptime(T, 2, data, dict, output),
        3 => decodeDictFusedComptime(T, 3, data, dict, output),
        4 => decodeDictFusedComptime(T, 4, data, dict, output),
        5 => decodeDictFusedComptime(T, 5, data, dict, output),
        6 => decodeDictFusedComptime(T, 6, data, dict, output),
        7 => decodeDictFusedComptime(T, 7, data, dict, output),
        8 => decodeDictFusedComptime(T, 8, data, dict, output),
        9 => decodeDictFusedComptime(T, 9, data, dict, output),
        10 => decodeDictFusedComptime(T, 10, data, dict, output),
        11 => decodeDictFusedComptime(T, 11, data, dict, output),
        12 => decodeDictFusedComptime(T, 12, data, dict, output),
        13 => decodeDictFusedComptime(T, 13, data, dict, output),
        14 => decodeDictFusedComptime(T, 14, data, dict, output),
        15 => decodeDictFusedComptime(T, 15, data, dict, output),
        16 => decodeDictFusedComptime(T, 16, data, dict, output),
        17 => decodeDictFusedComptime(T, 17, data, dict, output),
        18 => decodeDictFusedComptime(T, 18, data, dict, output),
        19 => decodeDictFusedComptime(T, 19, data, dict, output),
        20 => decodeDictFusedComptime(T, 20, data, dict, output),
        else => decodeDictFusedGeneric(T, data, bit_width, dict, output),
    };
}

/// Comptime-specialized fused decoder - all bit operations use compile-time constants
fn decodeDictFusedComptime(comptime T: type, comptime bit_width: comptime_int, data: []const u8, dict: []const T, output: []T) PageError!void {
    const mask: u32 = comptime if (bit_width == 32) 0xFFFFFFFF else (1 << bit_width) - 1;
    const byte_width = comptime (bit_width + 7) / 8;
    var pos: usize = 0;
    var idx: usize = 0;
    const count = output.len;

    while (idx < count and pos < data.len) {
        // Read varint indicator
        var indicator: u32 = 0;
        var shift: u5 = 0;
        while (pos < data.len) {
            const byte = data[pos];
            pos += 1;
            indicator |= @as(u32, byte & 0x7F) << shift;
            if (byte & 0x80 == 0) break;
            shift += 7;
        }

        if (indicator & 1 == 0) {
            // RLE run: repeat single value
            const run_len = indicator >> 1;

            if (pos + byte_width > data.len) return PageError.UnexpectedEndOfData;

            // Read the dictionary index with comptime byte_width
            var dict_idx: u32 = 0;
            inline for (0..byte_width) |i| {
                dict_idx |= @as(u32, data[pos + i]) << @intCast(i * 8);
            }
            pos += byte_width;
            dict_idx &= mask;

            if (dict_idx >= dict.len) return PageError.InvalidIndex;
            const value = dict[dict_idx];

            // Fill output with repeated value
            const end = @min(idx + run_len, count);
            @memset(output[idx..end], value);
            idx = end;
        } else {
            // Bit-packed run: decode groups of 8 values
            const num_groups = indicator >> 1;
            const total_bytes = num_groups * bit_width;

            if (pos + total_bytes > data.len) return PageError.UnexpectedEndOfData;

            const group_data = data[pos..][0..total_bytes];
            pos += total_bytes;

            // Comptime-specialized unpacking
            if (comptime bit_width == 8) {
                // Direct byte lookup
                for (group_data) |byte| {
                    if (idx >= count) break;
                    if (byte >= dict.len) return PageError.InvalidIndex;
                    output[idx] = dict[byte];
                    idx += 1;
                }
            } else if (comptime bit_width == 16) {
                // Direct 16-bit lookup
                var i: usize = 0;
                while (i + 1 < group_data.len and idx < count) {
                    const dict_idx = @as(u32, group_data[i]) | (@as(u32, group_data[i + 1]) << 8);
                    if (dict_idx >= dict.len) return PageError.InvalidIndex;
                    output[idx] = dict[dict_idx];
                    idx += 1;
                    i += 2;
                }
            } else if (comptime bit_width <= 8) {
                // Small bit widths: inline for with comptime offsets
                for (0..num_groups) |g| {
                    if (idx >= count) break;
                    const group_start = g * bit_width;
                    const group_bytes = group_data[group_start..][0..bit_width];
                    try unpackGroupComptime(bit_width, T, group_bytes, dict, output, &idx, count);
                }
            } else {
                // Larger bit widths: use u64 reads with comptime mask
                for (0..num_groups) |g| {
                    const group_start = g * bit_width;
                    const group_bytes = group_data[group_start..][0..bit_width];

                    inline for (0..8) |v| {
                        if (idx >= count) break;

                        const bit_offset = comptime v * bit_width;
                        const byte_off = comptime bit_offset / 8;
                        const bit_shift: u6 = comptime bit_offset % 8;

                        // Read u64 at comptime-known byte offset
                        var value: u64 = 0;
                        const bytes_avail = bit_width - byte_off;
                        if (bytes_avail >= 8) {
                            value = std.mem.readInt(u64, group_bytes[byte_off..][0..8], .little);
                        } else {
                            inline for (0..@min(8, bytes_avail)) |b| {
                                value |= @as(u64, group_bytes[byte_off + b]) << @intCast(b * 8);
                            }
                        }

                        const dict_idx: u32 = @truncate((value >> bit_shift) & mask);
                        if (dict_idx >= dict.len) return PageError.InvalidIndex;
                        output[idx] = dict[dict_idx];
                        idx += 1;
                    }
                }
            }
        }
    }
}

/// Generic decoder for uncommon bit widths (>20)
fn decodeDictFusedGeneric(comptime T: type, data: []const u8, bit_width: usize, dict: []const T, output: []T) PageError!void {
    const mask: u32 = if (bit_width == 32) 0xFFFFFFFF else (@as(u32, 1) << @intCast(bit_width)) - 1;
    var pos: usize = 0;
    var idx: usize = 0;
    const count = output.len;

    while (idx < count and pos < data.len) {
        var indicator: u32 = 0;
        var shift: u5 = 0;
        while (pos < data.len) {
            const byte = data[pos];
            pos += 1;
            indicator |= @as(u32, byte & 0x7F) << shift;
            if (byte & 0x80 == 0) break;
            shift += 7;
        }

        if (indicator & 1 == 0) {
            const run_len = indicator >> 1;
            const byte_width = (bit_width + 7) / 8;

            if (pos + byte_width > data.len) return PageError.UnexpectedEndOfData;

            var dict_idx: u32 = 0;
            for (0..byte_width) |i| {
                dict_idx |= @as(u32, data[pos + i]) << @intCast(i * 8);
            }
            pos += byte_width;
            dict_idx &= mask;

            if (dict_idx >= dict.len) return PageError.InvalidIndex;
            const value = dict[dict_idx];
            const end = @min(idx + run_len, count);
            @memset(output[idx..end], value);
            idx = end;
        } else {
            const num_groups = indicator >> 1;
            const total_bytes = num_groups * bit_width;

            if (pos + total_bytes > data.len) return PageError.UnexpectedEndOfData;

            const group_data = data[pos..][0..total_bytes];
            pos += total_bytes;

            for (0..num_groups) |g| {
                const group_start = g * bit_width;
                const group_bytes = group_data[group_start..][0..bit_width];

                for (0..8) |v| {
                    if (idx >= count) break;

                    const bit_offset = v * bit_width;
                    const byte_offset = bit_offset / 8;
                    const bit_shift: u6 = @intCast(bit_offset % 8);

                    var value: u64 = 0;
                    const bytes_left = group_bytes.len - byte_offset;
                    if (bytes_left >= 8) {
                        value = std.mem.readInt(u64, group_bytes[byte_offset..][0..8], .little);
                    } else {
                        for (0..bytes_left) |b| {
                            value |= @as(u64, group_bytes[byte_offset + b]) << @intCast(b * 8);
                        }
                    }

                    const dict_idx: u32 = @truncate((value >> bit_shift) & mask);
                    if (dict_idx >= dict.len) return PageError.InvalidIndex;
                    output[idx] = dict[dict_idx];
                    idx += 1;
                }
            }
        }
    }
}

pub const PageError = error{
    UnexpectedEndOfData,
    InvalidPageHeader,
    UnsupportedEncoding,
    UnsupportedCompression,
    UnsupportedType,
    OutOfMemory,
    MalformedVarint,
    InvalidType,
    InvalidFieldDelta,
    InvalidIndex,
    InvalidEncoding,
    NoDictionary,
    DecompressionError,
};

/// Decoded page data
pub const DecodedPage = struct {
    /// Values from this page
    int32_values: ?[]i32 = null,
    int64_values: ?[]i64 = null,
    float_values: ?[]f32 = null,
    double_values: ?[]f64 = null,
    bool_values: ?[]bool = null,
    binary_values: ?[][]const u8 = null,

    /// Number of values
    num_values: usize = 0,

    /// Decompressed buffer (owned by this struct, must be freed)
    /// Binary values are slices into this buffer
    decompressed_buffer: ?[]u8 = null,

    pub fn deinit(self: *DecodedPage, allocator: std.mem.Allocator) void {
        if (self.int32_values) |v| allocator.free(v);
        if (self.int64_values) |v| allocator.free(v);
        if (self.float_values) |v| allocator.free(v);
        if (self.double_values) |v| allocator.free(v);
        if (self.bool_values) |v| allocator.free(v);
        if (self.binary_values) |v| allocator.free(v);
        if (self.decompressed_buffer) |b| allocator.free(b);
    }
};

/// Page reader for a column chunk
pub const PageReader = struct {
    data: []const u8,
    pos: usize,
    physical_type: Type,
    type_length: ?i32,
    codec: CompressionCodec,
    allocator: std.mem.Allocator,

    // Dictionary storage
    dict_int32: ?[]i32 = null,
    dict_int64: ?[]i64 = null,
    dict_float: ?[]f32 = null,
    dict_double: ?[]f64 = null,
    dict_binary: ?[][]const u8 = null,

    // Decompressed dictionary buffer (binary values are slices into this)
    dict_decompressed_buf: ?[]u8 = null,

    const Self = @This();

    /// Create a page reader for a column chunk
    pub fn init(
        data: []const u8,
        physical_type: Type,
        type_length: ?i32,
        codec: CompressionCodec,
        allocator: std.mem.Allocator,
    ) Self {
        return .{
            .data = data,
            .pos = 0,
            .physical_type = physical_type,
            .type_length = type_length,
            .codec = codec,
            .allocator = allocator,
        };
    }

    /// Clean up dictionary data
    pub fn deinit(self: *Self) void {
        if (self.dict_int32) |v| self.allocator.free(v);
        if (self.dict_int64) |v| self.allocator.free(v);
        if (self.dict_float) |v| self.allocator.free(v);
        if (self.dict_double) |v| self.allocator.free(v);
        if (self.dict_binary) |v| self.allocator.free(v);
        if (self.dict_decompressed_buf) |b| self.allocator.free(b);
    }

    /// Check if more pages available
    pub fn hasMore(self: Self) bool {
        return self.pos < self.data.len;
    }

    /// Read the next page
    pub fn readPage(self: *Self) PageError!?DecodedPage {
        if (self.pos >= self.data.len) {
            return null;
        }

        // Read page header (Thrift encoded)
        var decoder = ThriftDecoder.init(self.data[self.pos..]);
        const header = PageHeader.decode(&decoder, self.allocator) catch |err| {
            return switch (err) {
                error.OutOfMemory => PageError.OutOfMemory,
                error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                error.MalformedVarint => PageError.MalformedVarint,
                error.InvalidType => PageError.InvalidType,
                error.InvalidFieldDelta => PageError.InvalidFieldDelta,
            };
        };

        // Move past header
        self.pos += decoder.pos;

        // Get page data
        const compressed_size: usize = @intCast(header.compressed_page_size);
        if (self.pos + compressed_size > self.data.len) {
            return PageError.UnexpectedEndOfData;
        }

        const compressed_data = self.data[self.pos..][0..compressed_size];
        self.pos += compressed_size;

        // Decompress if needed
        var decompressed_buf: ?[]u8 = null;
        const page_data: []const u8 = switch (self.codec) {
            .uncompressed => compressed_data,
            .snappy => blk: {
                const decompressed = snappy.decompress(compressed_data, self.allocator) catch |err| {
                    return switch (err) {
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.DecompressionError,
                    };
                };
                decompressed_buf = decompressed;
                break :blk decompressed;
            },
            else => return PageError.UnsupportedCompression,
        };
        errdefer if (decompressed_buf) |b| self.allocator.free(b);

        // Decode based on page type
        return switch (header.type_) {
            .data_page => blk: {
                var page = try self.decodeDataPage(header, page_data);
                page.decompressed_buffer = decompressed_buf;
                break :blk page;
            },
            .data_page_v2 => blk: {
                var page = try self.decodeDataPageV2(header, page_data);
                page.decompressed_buffer = decompressed_buf;
                break :blk page;
            },
            .dictionary_page => {
                try self.loadDictionary(header, page_data);
                // For binary types, keep decompressed buffer (slices reference it)
                // For other types, data is copied so we can free it
                if (self.physical_type == .byte_array or self.physical_type == .fixed_len_byte_array) {
                    self.dict_decompressed_buf = decompressed_buf;
                } else {
                    if (decompressed_buf) |b| self.allocator.free(b);
                }
                // Return null to continue to data pages
                return null;
            },
            else => {
                if (decompressed_buf) |b| self.allocator.free(b);
                return null;
            },
        };
    }

    /// Load dictionary page
    fn loadDictionary(self: *Self, header: PageHeader, data: []const u8) PageError!void {
        const dict_header = header.dictionary_page_header orelse return PageError.InvalidPageHeader;
        const num_values: usize = @intCast(dict_header.num_values);

        // Dictionary is always PLAIN encoded
        var plain_decoder = PlainDecoder.init(data);

        switch (self.physical_type) {
            .int32 => {
                self.dict_int32 = plain_decoder.readInt32(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .int64 => {
                self.dict_int64 = plain_decoder.readInt64(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .float => {
                self.dict_float = plain_decoder.readFloat(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .double => {
                self.dict_double = plain_decoder.readDouble(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .byte_array => {
                self.dict_binary = plain_decoder.readByteArray(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            else => return PageError.UnsupportedType,
        }
    }

    /// Decode a data page (v1)
    fn decodeDataPage(self: *Self, header: PageHeader, data: []const u8) PageError!DecodedPage {
        const data_header = header.data_page_header orelse return PageError.InvalidPageHeader;
        const num_values: usize = @intCast(data_header.num_values);

        // DATA_PAGE v1 format:
        // - repetition levels (if max_rep_level > 0): length-prefixed RLE
        // - definition levels (if max_def_level > 0): length-prefixed RLE
        // - values: encoded data

        // DATA_PAGE v1 may have definition levels even for required columns
        // Definition levels are length-prefixed RLE: 4 bytes length + RLE data
        var values_offset: usize = 0;
        if (data.len >= 4) {
            const level_len = std.mem.readInt(u32, data[0..4], .little);
            const level_len_usize: usize = @intCast(level_len);
            // Check if this looks like a valid level length prefix
            // It must be positive, less than total data, and when combined with header fit in data
            if (level_len_usize > 0 and 4 + level_len_usize <= data.len and level_len_usize < data.len / 2) {
                values_offset = 4 + level_len_usize;
            }
        }

        // Check encoding
        switch (data_header.encoding) {
            .plain => {
                return try self.decodePlain(data[values_offset..], num_values);
            },
            .rle_dictionary, .plain_dictionary => {
                if (values_offset >= data.len) {
                    return PageError.UnexpectedEndOfData;
                }
                return try self.decodeDictionary(data[values_offset..], num_values);
            },
            else => return PageError.UnsupportedEncoding,
        }
    }

    /// Decode a data page v2
    fn decodeDataPageV2(self: *Self, header: PageHeader, data: []const u8) PageError!DecodedPage {
        const data_header = header.data_page_header_v2 orelse return PageError.InvalidPageHeader;
        const num_values: usize = @intCast(data_header.num_values);

        // Skip levels for now (assume required non-nested)
        const rep_levels_size: usize = @intCast(data_header.repetition_levels_byte_length);
        const def_levels_size: usize = @intCast(data_header.definition_levels_byte_length);
        const values_start = rep_levels_size + def_levels_size;

        if (values_start >= data.len) {
            return PageError.UnexpectedEndOfData;
        }

        // Check encoding
        switch (data_header.encoding) {
            .plain => return try self.decodePlain(data[values_start..], num_values),
            .rle_dictionary, .plain_dictionary => return try self.decodeDictionary(data[values_start..], num_values),
            else => return PageError.UnsupportedEncoding,
        }
    }

    /// Decode PLAIN encoded data
    fn decodePlain(self: *Self, data: []const u8, num_values: usize) PageError!DecodedPage {
        var decoder = PlainDecoder.init(data);
        var page = DecodedPage{ .num_values = num_values };

        switch (self.physical_type) {
            .boolean => {
                page.bool_values = decoder.readBooleans(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .int32 => {
                page.int32_values = decoder.readInt32(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .int64 => {
                page.int64_values = decoder.readInt64(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .float => {
                page.float_values = decoder.readFloat(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .double => {
                page.double_values = decoder.readDouble(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .byte_array => {
                page.binary_values = decoder.readByteArray(num_values, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            .fixed_len_byte_array => {
                const type_len: usize = @intCast(self.type_length orelse return PageError.UnsupportedType);
                page.binary_values = decoder.readFixedLenByteArray(num_values, type_len, self.allocator) catch |err| {
                    return switch (err) {
                        error.UnexpectedEndOfData => PageError.UnexpectedEndOfData,
                        error.OutOfMemory => PageError.OutOfMemory,
                        else => PageError.UnsupportedType,
                    };
                };
            },
            else => return PageError.UnsupportedType,
        }

        return page;
    }

    /// Decode dictionary-encoded data (RLE_DICTIONARY) - FUSED version
    /// Decodes RLE and looks up dictionary values in a single pass
    fn decodeDictionary(self: *Self, data: []const u8, num_values: usize) PageError!DecodedPage {
        if (data.len < 1) {
            return PageError.UnexpectedEndOfData;
        }

        const bit_width: usize = data[0];
        const rle_data = data[1..];
        var page = DecodedPage{ .num_values = num_values };

        // Fused decode: RLE decode + dictionary lookup in single pass
        switch (self.physical_type) {
            .int32 => {
                const dict = self.dict_int32 orelse return PageError.NoDictionary;
                const values = try self.allocator.alloc(i32, num_values);
                errdefer self.allocator.free(values);
                try decodeDictFused(i32, rle_data, bit_width, dict, values);
                page.int32_values = values;
            },
            .int64 => {
                const dict = self.dict_int64 orelse return PageError.NoDictionary;
                const values = try self.allocator.alloc(i64, num_values);
                errdefer self.allocator.free(values);
                try decodeDictFused(i64, rle_data, bit_width, dict, values);
                page.int64_values = values;
            },
            .float => {
                const dict = self.dict_float orelse return PageError.NoDictionary;
                const values = try self.allocator.alloc(f32, num_values);
                errdefer self.allocator.free(values);
                try decodeDictFused(f32, rle_data, bit_width, dict, values);
                page.float_values = values;
            },
            .double => {
                const dict = self.dict_double orelse return PageError.NoDictionary;
                const values = try self.allocator.alloc(f64, num_values);
                errdefer self.allocator.free(values);
                try decodeDictFused(f64, rle_data, bit_width, dict, values);
                page.double_values = values;
            },
            .byte_array => {
                const dict = self.dict_binary orelse return PageError.NoDictionary;
                const values = try self.allocator.alloc([]const u8, num_values);
                errdefer self.allocator.free(values);
                try decodeDictFused([]const u8, rle_data, bit_width, dict, values);
                page.binary_values = values;
            },
            else => return PageError.UnsupportedType,
        }

        return page;
    }

    /// Read all pages and concatenate values
    pub fn readAll(self: *Self) PageError!DecodedPage {
        var result = DecodedPage{};
        errdefer result.deinit(self.allocator);

        // Collect all pages
        var pages = std.ArrayListUnmanaged(DecodedPage){};
        defer {
            for (pages.items) |*p| p.deinit(self.allocator);
            pages.deinit(self.allocator);
        }

        // Keep reading until we run out of data
        // readPage returns null for dictionary pages (which we store internally)
        // and for unsupported page types, so we continue until end of data
        while (self.hasMore()) {
            if (try self.readPage()) |page| {
                try pages.append(self.allocator, page);
                result.num_values += page.num_values;
            }
        }

        if (pages.items.len == 0) {
            return result;
        }

        // If single page, just move the pointers
        if (pages.items.len == 1) {
            result = pages.items[0];
            pages.items[0] = DecodedPage{}; // Clear so defer doesn't free
            return result;
        }

        // Multiple pages - concatenate based on type
        switch (self.physical_type) {
            .int32 => {
                const all = try self.allocator.alloc(i32, result.num_values);
                var offset: usize = 0;
                for (pages.items) |p| {
                    if (p.int32_values) |v| {
                        @memcpy(all[offset..][0..v.len], v);
                        offset += v.len;
                    }
                }
                result.int32_values = all;
            },
            .int64 => {
                const all = try self.allocator.alloc(i64, result.num_values);
                var offset: usize = 0;
                for (pages.items) |p| {
                    if (p.int64_values) |v| {
                        @memcpy(all[offset..][0..v.len], v);
                        offset += v.len;
                    }
                }
                result.int64_values = all;
            },
            .float => {
                const all = try self.allocator.alloc(f32, result.num_values);
                var offset: usize = 0;
                for (pages.items) |p| {
                    if (p.float_values) |v| {
                        @memcpy(all[offset..][0..v.len], v);
                        offset += v.len;
                    }
                }
                result.float_values = all;
            },
            .double => {
                const all = try self.allocator.alloc(f64, result.num_values);
                var offset: usize = 0;
                for (pages.items) |p| {
                    if (p.double_values) |v| {
                        @memcpy(all[offset..][0..v.len], v);
                        offset += v.len;
                    }
                }
                result.double_values = all;
            },
            .boolean => {
                const all = try self.allocator.alloc(bool, result.num_values);
                var offset: usize = 0;
                for (pages.items) |p| {
                    if (p.bool_values) |v| {
                        @memcpy(all[offset..][0..v.len], v);
                        offset += v.len;
                    }
                }
                result.bool_values = all;
            },
            .byte_array, .fixed_len_byte_array => {
                const all = try self.allocator.alloc([]const u8, result.num_values);
                var offset: usize = 0;
                for (pages.items) |p| {
                    if (p.binary_values) |v| {
                        @memcpy(all[offset..][0..v.len], v);
                        offset += v.len;
                    }
                }
                result.binary_values = all;
            },
            else => return PageError.UnsupportedType,
        }

        return result;
    }
};
