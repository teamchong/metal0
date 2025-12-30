//! Parquet file reader.
//!
//! Reads Parquet files by parsing the footer and metadata.
//! See: https://parquet.apache.org/docs/file-format/

const std = @import("std");
const proto = @import("lanceql.proto");
const ThriftDecoder = proto.ThriftDecoder;
const meta = @import("parquet_metadata.zig");

pub const ParquetError = error{
    InvalidMagic,
    FileTooSmall,
    MetadataTooLarge,
    InvalidMetadata,
    UnsupportedVersion,
    OutOfMemory,
    UnexpectedEndOfData,
    MalformedVarint,
    InvalidType,
    InvalidFieldDelta,
};

/// Parquet file reader
pub const ParquetFile = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    metadata: meta.FileMetaData,
    metadata_offset: usize,

    const Self = @This();

    /// Magic bytes at start and end of Parquet file
    const MAGIC: *const [4]u8 = "PAR1";

    /// Minimum file size: magic (4) + metadata_len (4) + magic (4) = 12
    const MIN_FILE_SIZE: usize = 12;

    /// Open a Parquet file from bytes
    pub fn init(allocator: std.mem.Allocator, data: []const u8) ParquetError!Self {
        if (data.len < MIN_FILE_SIZE) {
            return ParquetError.FileTooSmall;
        }

        // Check magic at start
        if (!std.mem.eql(u8, data[0..4], MAGIC)) {
            return ParquetError.InvalidMagic;
        }

        // Check magic at end
        if (!std.mem.eql(u8, data[data.len - 4 ..], MAGIC)) {
            return ParquetError.InvalidMagic;
        }

        // Read metadata length (4 bytes before ending magic, little-endian)
        const metadata_len = std.mem.readInt(u32, data[data.len - 8 ..][0..4], .little);

        if (metadata_len > data.len - MIN_FILE_SIZE) {
            return ParquetError.MetadataTooLarge;
        }

        // Calculate metadata offset
        const metadata_offset = data.len - 8 - metadata_len;
        const metadata_bytes = data[metadata_offset..][0..metadata_len];

        // Parse metadata using Thrift decoder
        var decoder = ThriftDecoder.init(metadata_bytes);
        const file_metadata = meta.FileMetaData.decode(&decoder, allocator) catch |err| {
            return switch (err) {
                error.OutOfMemory => ParquetError.OutOfMemory,
                error.UnexpectedEndOfData => ParquetError.UnexpectedEndOfData,
                error.MalformedVarint => ParquetError.MalformedVarint,
                error.InvalidType => ParquetError.InvalidType,
                error.InvalidFieldDelta => ParquetError.InvalidFieldDelta,
            };
        };

        return Self{
            .allocator = allocator,
            .data = data,
            .metadata = file_metadata,
            .metadata_offset = metadata_offset,
        };
    }

    /// Get Parquet format version
    pub fn getVersion(self: Self) i32 {
        return self.metadata.version;
    }

    /// Get total number of rows
    pub fn getNumRows(self: Self) i64 {
        return self.metadata.num_rows;
    }

    /// Get number of row groups
    pub fn getNumRowGroups(self: Self) usize {
        return self.metadata.row_groups.len;
    }

    /// Get row group by index
    pub fn getRowGroup(self: Self, index: usize) ?meta.RowGroup {
        if (index >= self.metadata.row_groups.len) {
            return null;
        }
        return self.metadata.row_groups[index];
    }

    /// Get number of columns (leaf columns)
    pub fn getNumColumns(self: Self) usize {
        var count: usize = 0;
        for (self.metadata.schema) |elem| {
            // Leaf columns have no children (num_children is null)
            // Group elements (including root) have num_children set
            if (elem.num_children == null) {
                count += 1;
            }
        }
        return count;
    }

    /// Get schema elements
    pub fn getSchema(self: Self) []const meta.SchemaElement {
        return self.metadata.schema;
    }

    /// Get column names (leaf columns only)
    pub fn getColumnNames(self: Self) ![][]const u8 {
        var names = std.ArrayListUnmanaged([]const u8){};
        errdefer names.deinit(self.allocator);

        // Skip first element (root)
        var i: usize = 1;
        while (i < self.metadata.schema.len) : (i += 1) {
            const elem = self.metadata.schema[i];
            if (elem.num_children == null) {
                // Leaf column
                try names.append(self.allocator, elem.name);
            }
        }

        return names.toOwnedSlice(self.allocator);
    }

    /// Get column metadata for a specific column in a row group
    pub fn getColumnChunk(self: Self, row_group_idx: usize, column_idx: usize) ?meta.ColumnChunk {
        if (row_group_idx >= self.metadata.row_groups.len) {
            return null;
        }

        const rg = self.metadata.row_groups[row_group_idx];
        if (column_idx >= rg.columns.len) {
            return null;
        }

        return rg.columns[column_idx];
    }

    /// Get raw page data for a column chunk
    pub fn getColumnData(self: Self, row_group_idx: usize, column_idx: usize) ?[]const u8 {
        const chunk = self.getColumnChunk(row_group_idx, column_idx) orelse return null;
        const col_meta = chunk.meta_data orelse return null;

        // Start offset is the dictionary page or data page offset
        const start_offset: usize = @intCast(col_meta.dictionary_page_offset orelse col_meta.data_page_offset);
        const compressed_size: usize = @intCast(col_meta.total_compressed_size);

        if (start_offset + compressed_size > self.metadata_offset) {
            return null;
        }

        return self.data[start_offset..][0..compressed_size];
    }

    /// Get application that created the file
    pub fn getCreatedBy(self: Self) ?[]const u8 {
        return self.metadata.created_by;
    }

    /// Get key-value metadata
    pub fn getKeyValueMetadata(self: Self) []const meta.KeyValue {
        return self.metadata.key_value_metadata;
    }

    /// Clean up allocated memory
    pub fn deinit(self: *Self) void {
        // Free schema elements
        self.allocator.free(self.metadata.schema);

        // Free row groups and their column chunks
        for (self.metadata.row_groups) |rg| {
            for (rg.columns) |col| {
                if (col.meta_data) |col_meta| {
                    self.allocator.free(col_meta.encodings);
                    self.allocator.free(col_meta.path_in_schema);
                }
            }
            self.allocator.free(rg.columns);
        }
        self.allocator.free(self.metadata.row_groups);

        // Free key-value metadata
        self.allocator.free(self.metadata.key_value_metadata);
    }

    /// Print file summary for debugging
    pub fn printSummary(self: Self, writer: anytype) !void {
        try writer.print("Parquet File Summary:\n", .{});
        try writer.print("  Version: {}\n", .{self.metadata.version});
        try writer.print("  Rows: {}\n", .{self.metadata.num_rows});
        try writer.print("  Row Groups: {}\n", .{self.metadata.row_groups.len});
        try writer.print("  Columns: {}\n", .{self.getNumColumns()});

        if (self.metadata.created_by) |created_by| {
            try writer.print("  Created By: {s}\n", .{created_by});
        }

        try writer.print("\nSchema:\n", .{});
        for (self.metadata.schema, 0..) |elem, i| {
            const indent = if (elem.num_children != null) "  " else "    ";
            try writer.print("{s}{}: {s}", .{ indent, i, elem.name });
            if (elem.type_) |t| {
                try writer.print(" ({s})", .{@tagName(t)});
            }
            if (elem.num_children) |nc| {
                try writer.print(" (group, {} children)", .{nc});
            }
            try writer.print("\n", .{});
        }

        try writer.print("\nRow Groups:\n", .{});
        for (self.metadata.row_groups, 0..) |rg, i| {
            try writer.print("  RG {}: {} rows, {} columns, {} bytes\n", .{
                i,
                rg.num_rows,
                rg.columns.len,
                rg.total_byte_size,
            });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parse minimal parquet file" {
    // This is a minimal valid Parquet file structure for testing
    // In practice, we'd use a real Parquet file fixture
    const allocator = std.testing.allocator;

    // Create a minimal file with just headers
    var file_data = std.ArrayListUnmanaged(u8){};
    defer file_data.deinit(allocator);

    // Magic
    try file_data.appendSlice(allocator, "PAR1");

    // Empty metadata (just STOP)
    const metadata_start = file_data.items.len;
    try file_data.append(allocator, 0x00); // STOP (empty struct)
    const metadata_len = file_data.items.len - metadata_start;

    // Metadata length (little-endian)
    var len_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_bytes, @intCast(metadata_len), .little);
    try file_data.appendSlice(allocator, &len_bytes);

    // Magic
    try file_data.appendSlice(allocator, "PAR1");

    // Try to parse (should succeed with empty metadata)
    var pf = try ParquetFile.init(allocator, file_data.items);
    defer pf.deinit();

    try std.testing.expectEqual(@as(i32, 0), pf.getVersion());
    try std.testing.expectEqual(@as(i64, 0), pf.getNumRows());
    try std.testing.expectEqual(@as(usize, 0), pf.getNumRowGroups());
}

test "reject invalid magic" {
    const allocator = std.testing.allocator;

    // File with wrong magic
    const bad_data = "BADX" ++ "\x00" ++ "\x01\x00\x00\x00" ++ "PAR1";
    const result = ParquetFile.init(allocator, bad_data);
    try std.testing.expectError(ParquetError.InvalidMagic, result);
}

test "reject too small file" {
    const allocator = std.testing.allocator;

    const small_data = "PAR1PAR1";
    const result = ParquetFile.init(allocator, small_data);
    try std.testing.expectError(ParquetError.FileTooSmall, result);
}
