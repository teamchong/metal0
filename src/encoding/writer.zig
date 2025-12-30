//! Lance file writer - encodes columnar data to Lance format.
//!
//! This module provides functionality to write Lance files in the browser
//! via WASM, supporting INSERT operations with OPFS storage.
//!
//! ## Lance File Layout
//! ```
//! +------------------+
//! | Column Data      |  <- Raw column bytes (page by page)
//! +------------------+
//! | Column Metadata  |  <- Protobuf-encoded column info
//! +------------------+
//! | Column Offsets   |  <- Array of u64 offsets to each column's metadata
//! +------------------+
//! | Global Buffers   |  <- Shared buffers (if any)
//! +------------------+
//! | Footer (40 bytes)|  <- Version, offsets, magic "LANC"
//! +------------------+
//! ```

const std = @import("std");

/// Data types supported for writing
pub const DataType = enum {
    int32,
    int64,
    float32,
    float64,
    string,
    bool,
    vector_f32,
};

/// Column schema definition
pub const ColumnSchema = struct {
    name: []const u8,
    data_type: DataType,
    nullable: bool = true,
    vector_dim: u32 = 0, // For vector types
};

/// A batch of column data to write
pub const ColumnBatch = struct {
    /// Column index
    column_index: u32,
    /// Raw data bytes (already encoded)
    data: []const u8,
    /// Number of rows in this batch
    row_count: u32,
    /// For strings: offsets buffer
    offsets: ?[]const u8 = null,
};

/// Plain encoder - encodes values to bytes
pub const PlainEncoder = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .buffer = std.ArrayListUnmanaged(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn getBytes(self: Self) []const u8 {
        return self.buffer.items;
    }

    // ========================================================================
    // Int64 encoding
    // ========================================================================

    pub fn writeInt64(self: *Self, value: i64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(i64, &bytes, value, .little);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    pub fn writeInt64Slice(self: *Self, values: []const i64) !void {
        for (values) |v| {
            try self.writeInt64(v);
        }
    }

    // ========================================================================
    // Int32 encoding
    // ========================================================================

    pub fn writeInt32(self: *Self, value: i32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bytes, value, .little);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    pub fn writeInt32Slice(self: *Self, values: []const i32) !void {
        for (values) |v| {
            try self.writeInt32(v);
        }
    }

    // ========================================================================
    // Float64 encoding
    // ========================================================================

    pub fn writeFloat64(self: *Self, value: f64) !void {
        var bytes: [8]u8 = undefined;
        const bits: u64 = @bitCast(value);
        std.mem.writeInt(u64, &bytes, bits, .little);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    pub fn writeFloat64Slice(self: *Self, values: []const f64) !void {
        for (values) |v| {
            try self.writeFloat64(v);
        }
    }

    // ========================================================================
    // Float32 encoding
    // ========================================================================

    pub fn writeFloat32(self: *Self, value: f32) !void {
        var bytes: [4]u8 = undefined;
        const bits: u32 = @bitCast(value);
        std.mem.writeInt(u32, &bytes, bits, .little);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    pub fn writeFloat32Slice(self: *Self, values: []const f32) !void {
        for (values) |v| {
            try self.writeFloat32(v);
        }
    }

    // ========================================================================
    // String encoding (produces offsets + data buffers)
    // ========================================================================

    pub fn writeStrings(self: *Self, values: []const []const u8, offsets_out: *std.ArrayListUnmanaged(u8), offsets_allocator: std.mem.Allocator) !void {
        var current_offset: u32 = 0;

        for (values) |str| {
            // Write string data
            try self.buffer.appendSlice(self.allocator, str);
            current_offset += @intCast(str.len);

            // Write offset (end position)
            var offset_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &offset_bytes, current_offset, .little);
            try offsets_out.appendSlice(offsets_allocator, &offset_bytes);
        }
    }

    // ========================================================================
    // Boolean encoding (packed bits)
    // ========================================================================

    pub fn writeBools(self: *Self, values: []const bool) !void {
        const byte_count = (values.len + 7) / 8;

        var i: usize = 0;
        while (i < byte_count) : (i += 1) {
            var byte: u8 = 0;
            var bit: u3 = 0;
            while (bit < 8 and i * 8 + bit < values.len) : (bit += 1) {
                if (values[i * 8 + bit]) {
                    byte |= @as(u8, 1) << bit;
                }
            }
            try self.buffer.append(self.allocator, byte);
        }
    }

    // ========================================================================
    // Vector encoding (float32 array)
    // ========================================================================

    pub fn writeVectorF32(self: *Self, values: []const f32) !void {
        try self.writeFloat32Slice(values);
    }
};

/// Footer writer - creates the 40-byte Lance footer
pub const FooterWriter = struct {
    pub fn write(
        column_meta_start: u64,
        column_meta_offsets_start: u64,
        global_buff_offsets_start: u64,
        num_global_buffers: u32,
        num_columns: u32,
        major_version: u16,
        minor_version: u16,
    ) [40]u8 {
        var footer: [40]u8 = undefined;

        std.mem.writeInt(u64, footer[0..8], column_meta_start, .little);
        std.mem.writeInt(u64, footer[8..16], column_meta_offsets_start, .little);
        std.mem.writeInt(u64, footer[16..24], global_buff_offsets_start, .little);
        std.mem.writeInt(u32, footer[24..28], num_global_buffers, .little);
        std.mem.writeInt(u32, footer[28..32], num_columns, .little);
        std.mem.writeInt(u16, footer[32..34], major_version, .little);
        std.mem.writeInt(u16, footer[34..36], minor_version, .little);
        @memcpy(footer[36..40], "LANC");

        return footer;
    }
};

/// Protobuf encoder for column metadata
pub const ProtobufEncoder = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .buffer = std.ArrayListUnmanaged(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn getBytes(self: Self) []const u8 {
        return self.buffer.items;
    }

    /// Write varint (variable-length integer)
    pub fn writeVarint(self: *Self, value: u64) !void {
        var v = value;
        while (v >= 0x80) {
            try self.buffer.append(self.allocator, @as(u8, @truncate(v)) | 0x80);
            v >>= 7;
        }
        try self.buffer.append(self.allocator, @truncate(v));
    }

    /// Write field tag (field number + wire type)
    pub fn writeTag(self: *Self, field_number: u32, wire_type: u3) !void {
        const tag = (@as(u64, field_number) << 3) | wire_type;
        try self.writeVarint(tag);
    }

    /// Write length-delimited bytes (wire type 2)
    pub fn writeBytes(self: *Self, field_number: u32, data: []const u8) !void {
        try self.writeTag(field_number, 2);
        try self.writeVarint(data.len);
        try self.buffer.appendSlice(self.allocator, data);
    }

    /// Write string (same as bytes)
    pub fn writeString(self: *Self, field_number: u32, str: []const u8) !void {
        try self.writeBytes(field_number, str);
    }

    /// Write varint field (wire type 0)
    pub fn writeVarintField(self: *Self, field_number: u32, value: u64) !void {
        try self.writeTag(field_number, 0);
        try self.writeVarint(value);
    }

    /// Write fixed64 field (wire type 1)
    pub fn writeFixed64(self: *Self, field_number: u32, value: u64) !void {
        try self.writeTag(field_number, 1);
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    /// Write fixed32 field (wire type 5)
    pub fn writeFixed32(self: *Self, field_number: u32, value: u32) !void {
        try self.writeTag(field_number, 5);
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }
};

/// Lance file writer
pub const LanceWriter = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayListUnmanaged(u8),
    schema: []const ColumnSchema,
    column_data_offsets: std.ArrayListUnmanaged(u64),
    column_metadata: std.ArrayListUnmanaged([]const u8),
    row_count: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, schema: []const ColumnSchema) Self {
        return Self{
            .allocator = allocator,
            .output = std.ArrayListUnmanaged(u8){},
            .schema = schema,
            .column_data_offsets = std.ArrayListUnmanaged(u64){},
            .column_metadata = std.ArrayListUnmanaged([]const u8){},
            .row_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
        self.column_data_offsets.deinit(self.allocator);
        for (self.column_metadata.items) |meta| {
            self.allocator.free(meta);
        }
        self.column_metadata.deinit(self.allocator);
    }

    /// Write a batch of column data
    pub fn writeColumnBatch(self: *Self, batch: ColumnBatch) !void {
        // Record offset before writing
        try self.column_data_offsets.append(self.allocator, self.output.items.len);

        // Write column data
        try self.output.appendSlice(self.allocator, batch.data);

        // If strings, also write offsets
        if (batch.offsets) |offsets| {
            try self.output.appendSlice(self.allocator, offsets);
        }

        // Track row count
        if (batch.row_count > self.row_count) {
            self.row_count = batch.row_count;
        }
    }

    /// Finalize and return the complete Lance file bytes
    pub fn finalize(self: *Self) ![]const u8 {
        // Record column metadata start
        const column_meta_start = self.output.items.len;

        // Write column metadata for each column
        for (self.schema, 0..) |col, i| {
            var proto = ProtobufEncoder.init(self.allocator);
            defer proto.deinit();

            // Field 1: column name
            try proto.writeString(1, col.name);

            // Field 2: data type (as string for simplicity)
            const type_str = switch (col.data_type) {
                .int32 => "int32",
                .int64 => "int64",
                .float32 => "float32",
                .float64 => "float64",
                .string => "string",
                .bool => "bool",
                .vector_f32 => "vector",
            };
            try proto.writeString(2, type_str);

            // Field 3: nullable
            try proto.writeVarintField(3, if (col.nullable) 1 else 0);

            // Field 4: data offset
            if (i < self.column_data_offsets.items.len) {
                try proto.writeFixed64(4, self.column_data_offsets.items[i]);
            }

            // Field 5: row count
            try proto.writeVarintField(5, self.row_count);

            // Field 6: vector dimension (if applicable)
            if (col.vector_dim > 0) {
                try proto.writeVarintField(6, col.vector_dim);
            }

            // Copy metadata bytes
            const meta = try self.allocator.dupe(u8, proto.getBytes());
            try self.column_metadata.append(self.allocator, meta);
            try self.output.appendSlice(self.allocator, meta);
        }

        // Record column metadata offsets start
        const column_meta_offsets_start = self.output.items.len;

        // Write column metadata offset table (u64 per column)
        var meta_offset: u64 = column_meta_start;
        for (self.column_metadata.items) |meta| {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, meta_offset, .little);
            try self.output.appendSlice(self.allocator, &bytes);
            meta_offset += meta.len;
        }

        // Record global buffers start (empty for now)
        const global_buff_offsets_start = self.output.items.len;

        // Write footer
        const footer = FooterWriter.write(
            column_meta_start,
            column_meta_offsets_start,
            global_buff_offsets_start,
            0, // num_global_buffers
            @intCast(self.schema.len),
            0, // major_version (Lance 2.0)
            3, // minor_version
        );
        try self.output.appendSlice(self.allocator, &footer);

        return self.output.items;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "plain encoder int64" {
    const allocator = std.testing.allocator;

    var encoder = PlainEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeInt64(100);
    try encoder.writeInt64(-200);
    try encoder.writeInt64(300);

    const bytes = encoder.getBytes();
    try std.testing.expectEqual(@as(usize, 24), bytes.len);

    // Verify values
    try std.testing.expectEqual(@as(i64, 100), std.mem.readInt(i64, bytes[0..8], .little));
    try std.testing.expectEqual(@as(i64, -200), std.mem.readInt(i64, bytes[8..16], .little));
    try std.testing.expectEqual(@as(i64, 300), std.mem.readInt(i64, bytes[16..24], .little));
}

test "plain encoder float64" {
    const allocator = std.testing.allocator;

    var encoder = PlainEncoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeFloat64(3.14159);
    try encoder.writeFloat64(-2.71828);

    const bytes = encoder.getBytes();
    try std.testing.expectEqual(@as(usize, 16), bytes.len);
}

test "plain encoder bools" {
    const allocator = std.testing.allocator;

    var encoder = PlainEncoder.init(allocator);
    defer encoder.deinit();

    // Pack 8 bools into 1 byte
    const values = [_]bool{ true, false, false, true, true, false, true, false };
    try encoder.writeBools(&values);

    const bytes = encoder.getBytes();
    try std.testing.expectEqual(@as(usize, 1), bytes.len);
    // Expected: 0b01011001 = 89
    try std.testing.expectEqual(@as(u8, 0b01011001), bytes[0]);
}

test "footer writer" {
    const footer = FooterWriter.write(
        1000, // column_meta_start
        2000, // column_meta_offsets_start
        3000, // global_buff_offsets_start
        5, // num_global_buffers
        10, // num_columns
        0, // major_version
        3, // minor_version
    );

    // Verify magic
    try std.testing.expectEqualSlices(u8, "LANC", footer[36..40]);

    // Verify values
    try std.testing.expectEqual(@as(u64, 1000), std.mem.readInt(u64, footer[0..8], .little));
    try std.testing.expectEqual(@as(u64, 2000), std.mem.readInt(u64, footer[8..16], .little));
    try std.testing.expectEqual(@as(u32, 10), std.mem.readInt(u32, footer[28..32], .little));
}

test "protobuf encoder varint" {
    const allocator = std.testing.allocator;

    var encoder = ProtobufEncoder.init(allocator);
    defer encoder.deinit();

    // Single byte varint (< 128)
    try encoder.writeVarint(100);
    try std.testing.expectEqual(@as(usize, 1), encoder.buffer.items.len);
    try std.testing.expectEqual(@as(u8, 100), encoder.buffer.items[0]);

    encoder.buffer.clearRetainingCapacity();

    // Two byte varint (300 = 0b100101100)
    try encoder.writeVarint(300);
    try std.testing.expectEqual(@as(usize, 2), encoder.buffer.items.len);
    try std.testing.expectEqual(@as(u8, 0xAC), encoder.buffer.items[0]); // 0b10101100
    try std.testing.expectEqual(@as(u8, 0x02), encoder.buffer.items[1]); // 0b00000010
}
