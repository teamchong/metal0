//! Parquet Table wrapper for CLI
//!
//! Provides a Table-like interface for Parquet files to enable unified
//! query execution across both Lance and Parquet formats.

const std = @import("std");
const format = @import("lanceql.format");
const ParquetFile = format.ParquetFile;
const meta = format.parquet_metadata;
const Type = meta.Type;
const page_mod = @import("lanceql.encoding.parquet");
const PageReader = page_mod.PageReader;

pub const ParquetTableError = error{
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
    UnsupportedType,
    ColumnNotFound,
    NoRowGroups,
};

/// High-level Parquet table reader
pub const ParquetTable = struct {
    allocator: std.mem.Allocator,
    parquet_file: ParquetFile,
    data: []const u8,
    column_names: [][]const u8,

    const Self = @This();

    /// Open a Parquet table from bytes
    pub fn init(allocator: std.mem.Allocator, data: []const u8) ParquetTableError!Self {
        var parquet_file = ParquetFile.init(allocator, data) catch |err| {
            return switch (err) {
                error.FileTooSmall => ParquetTableError.FileTooSmall,
                error.InvalidMagic => ParquetTableError.InvalidMagic,
                error.MetadataTooLarge => ParquetTableError.MetadataTooLarge,
                error.InvalidMetadata => ParquetTableError.InvalidMetadata,
                error.OutOfMemory => ParquetTableError.OutOfMemory,
                error.UnexpectedEndOfData => ParquetTableError.UnexpectedEndOfData,
                error.MalformedVarint => ParquetTableError.MalformedVarint,
                error.InvalidType => ParquetTableError.InvalidType,
                error.InvalidFieldDelta => ParquetTableError.InvalidFieldDelta,
                else => ParquetTableError.InvalidMetadata,
            };
        };
        errdefer parquet_file.deinit();

        const column_names = parquet_file.getColumnNames() catch return ParquetTableError.OutOfMemory;

        return Self{
            .allocator = allocator,
            .parquet_file = parquet_file,
            .data = data,
            .column_names = column_names,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.column_names);
        self.parquet_file.deinit();
    }

    /// Get number of columns
    pub fn numColumns(self: Self) u32 {
        return @intCast(self.parquet_file.getNumColumns());
    }

    /// Get number of rows
    pub fn numRows(self: Self) usize {
        return @intCast(self.parquet_file.getNumRows());
    }

    /// Get column names
    pub fn getColumnNames(self: Self) [][]const u8 {
        return self.column_names;
    }

    /// Get column index by name
    pub fn columnIndex(self: Self, name: []const u8) ?usize {
        for (self.column_names, 0..) |col_name, i| {
            if (std.mem.eql(u8, col_name, name)) {
                return i;
            }
        }
        return null;
    }

    /// Get column type
    pub fn getColumnType(self: Self, col_idx: usize) ?Type {
        var leaf_idx: usize = 0;
        for (self.parquet_file.getSchema()) |elem| {
            if (elem.num_children == null) {
                if (leaf_idx == col_idx) {
                    return elem.type_;
                }
                leaf_idx += 1;
            }
        }
        return null;
    }

    /// Read int64 column data
    pub fn readInt64Column(self: *Self, col_idx: usize) ParquetTableError![]i64 {
        const num_row_groups = self.parquet_file.getNumRowGroups();
        if (num_row_groups == 0) return ParquetTableError.NoRowGroups;

        var all_values = std.ArrayListUnmanaged(i64){};
        errdefer all_values.deinit(self.allocator);

        for (0..num_row_groups) |rg_idx| {
            const chunk = self.parquet_file.getColumnChunk(rg_idx, col_idx) orelse continue;
            const col_meta = chunk.meta_data orelse continue;
            const col_data = self.parquet_file.getColumnData(rg_idx, col_idx) orelse continue;

            var reader = PageReader.init(
                col_data,
                col_meta.type_,
                null, // type_length only needed for fixed_len_byte_array
                col_meta.codec,
                self.allocator,
            );
            defer reader.deinit();

            const decoded = reader.readAll() catch continue;
            defer {
                if (decoded.int64_values) |v| self.allocator.free(v);
            }

            if (decoded.int64_values) |values| {
                all_values.appendSlice(self.allocator, values) catch return ParquetTableError.OutOfMemory;
            }
        }

        return all_values.toOwnedSlice(self.allocator) catch return ParquetTableError.OutOfMemory;
    }

    /// Read int32 column data
    pub fn readInt32Column(self: *Self, col_idx: usize) ParquetTableError![]i32 {
        const num_row_groups = self.parquet_file.getNumRowGroups();
        if (num_row_groups == 0) return ParquetTableError.NoRowGroups;

        var all_values = std.ArrayListUnmanaged(i32){};
        errdefer all_values.deinit(self.allocator);

        for (0..num_row_groups) |rg_idx| {
            const chunk = self.parquet_file.getColumnChunk(rg_idx, col_idx) orelse continue;
            const col_meta = chunk.meta_data orelse continue;
            const col_data = self.parquet_file.getColumnData(rg_idx, col_idx) orelse continue;

            var reader = PageReader.init(
                col_data,
                col_meta.type_,
                null, // type_length only needed for fixed_len_byte_array
                col_meta.codec,
                self.allocator,
            );
            defer reader.deinit();

            const decoded = reader.readAll() catch continue;
            defer {
                if (decoded.int32_values) |v| self.allocator.free(v);
            }

            if (decoded.int32_values) |values| {
                all_values.appendSlice(self.allocator, values) catch return ParquetTableError.OutOfMemory;
            }
        }

        return all_values.toOwnedSlice(self.allocator) catch return ParquetTableError.OutOfMemory;
    }

    /// Read float64 column data
    pub fn readFloat64Column(self: *Self, col_idx: usize) ParquetTableError![]f64 {
        const num_row_groups = self.parquet_file.getNumRowGroups();
        if (num_row_groups == 0) return ParquetTableError.NoRowGroups;

        var all_values = std.ArrayListUnmanaged(f64){};
        errdefer all_values.deinit(self.allocator);

        for (0..num_row_groups) |rg_idx| {
            const chunk = self.parquet_file.getColumnChunk(rg_idx, col_idx) orelse continue;
            const col_meta = chunk.meta_data orelse continue;
            const col_data = self.parquet_file.getColumnData(rg_idx, col_idx) orelse continue;

            var reader = PageReader.init(
                col_data,
                col_meta.type_,
                null, // type_length only needed for fixed_len_byte_array
                col_meta.codec,
                self.allocator,
            );
            defer reader.deinit();

            const decoded = reader.readAll() catch continue;
            defer {
                if (decoded.double_values) |v| self.allocator.free(v);
            }

            if (decoded.double_values) |values| {
                all_values.appendSlice(self.allocator, values) catch return ParquetTableError.OutOfMemory;
            }
        }

        return all_values.toOwnedSlice(self.allocator) catch return ParquetTableError.OutOfMemory;
    }

    /// Read float32 column data
    pub fn readFloat32Column(self: *Self, col_idx: usize) ParquetTableError![]f32 {
        const num_row_groups = self.parquet_file.getNumRowGroups();
        if (num_row_groups == 0) return ParquetTableError.NoRowGroups;

        var all_values = std.ArrayListUnmanaged(f32){};
        errdefer all_values.deinit(self.allocator);

        for (0..num_row_groups) |rg_idx| {
            const chunk = self.parquet_file.getColumnChunk(rg_idx, col_idx) orelse continue;
            const col_meta = chunk.meta_data orelse continue;
            const col_data = self.parquet_file.getColumnData(rg_idx, col_idx) orelse continue;

            var reader = PageReader.init(
                col_data,
                col_meta.type_,
                null, // type_length only needed for fixed_len_byte_array
                col_meta.codec,
                self.allocator,
            );
            defer reader.deinit();

            const decoded = reader.readAll() catch continue;
            defer {
                if (decoded.float_values) |v| self.allocator.free(v);
            }

            if (decoded.float_values) |values| {
                all_values.appendSlice(self.allocator, values) catch return ParquetTableError.OutOfMemory;
            }
        }

        return all_values.toOwnedSlice(self.allocator) catch return ParquetTableError.OutOfMemory;
    }

    /// Read string column data
    pub fn readStringColumn(self: *Self, col_idx: usize) ParquetTableError![][]const u8 {
        const num_row_groups = self.parquet_file.getNumRowGroups();
        if (num_row_groups == 0) return ParquetTableError.NoRowGroups;

        var all_values = std.ArrayListUnmanaged([]const u8){};
        errdefer all_values.deinit(self.allocator);

        for (0..num_row_groups) |rg_idx| {
            const chunk = self.parquet_file.getColumnChunk(rg_idx, col_idx) orelse continue;
            const col_meta = chunk.meta_data orelse continue;
            const col_data = self.parquet_file.getColumnData(rg_idx, col_idx) orelse continue;

            var reader = PageReader.init(
                col_data,
                col_meta.type_,
                null, // type_length only needed for fixed_len_byte_array
                col_meta.codec,
                self.allocator,
            );
            defer reader.deinit();

            const decoded = reader.readAll() catch continue;
            defer {
                if (decoded.binary_values) |v| self.allocator.free(v);
            }

            if (decoded.binary_values) |values| {
                // Copy strings
                for (values) |v| {
                    const copy = self.allocator.dupe(u8, v) catch return ParquetTableError.OutOfMemory;
                    all_values.append(self.allocator, copy) catch return ParquetTableError.OutOfMemory;
                }
            }
        }

        return all_values.toOwnedSlice(self.allocator) catch return ParquetTableError.OutOfMemory;
    }

    /// Read bool column data
    pub fn readBoolColumn(self: *Self, col_idx: usize) ParquetTableError![]bool {
        const num_row_groups = self.parquet_file.getNumRowGroups();
        if (num_row_groups == 0) return ParquetTableError.NoRowGroups;

        var all_values = std.ArrayListUnmanaged(bool){};
        errdefer all_values.deinit(self.allocator);

        for (0..num_row_groups) |rg_idx| {
            const chunk = self.parquet_file.getColumnChunk(rg_idx, col_idx) orelse continue;
            const col_meta = chunk.meta_data orelse continue;
            const col_data = self.parquet_file.getColumnData(rg_idx, col_idx) orelse continue;

            var reader = PageReader.init(
                col_data,
                col_meta.type_,
                null, // type_length only needed for fixed_len_byte_array
                col_meta.codec,
                self.allocator,
            );
            defer reader.deinit();

            const decoded = reader.readAll() catch continue;
            defer {
                if (decoded.bool_values) |v| self.allocator.free(v);
            }

            if (decoded.bool_values) |values| {
                all_values.appendSlice(self.allocator, values) catch return ParquetTableError.OutOfMemory;
            }
        }

        return all_values.toOwnedSlice(self.allocator) catch return ParquetTableError.OutOfMemory;
    }
};
