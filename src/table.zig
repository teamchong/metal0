//! High-level Table API for reading Lance files.
//!
//! This module provides a convenient interface for reading Lance files,
//! combining file parsing, schema access, and column value decoding.

const std = @import("std");
const format = @import("lanceql.format");
const proto = @import("lanceql.proto");
const encoding = @import("lanceql.encoding");

const LanceFile = format.LanceFile;
const Schema = proto.Schema;
const Field = proto.Field;
const ColumnMetadata = proto.ColumnMetadata;
const PlainDecoder = encoding.PlainDecoder;

/// Errors that can occur when reading a table.
pub const TableError = error{
    NoSchema,
    ColumnNotFound,
    InvalidMetadata,
    UnsupportedType,
    OutOfMemory,
    FileTooSmall,
    InvalidMagic,
    UnsupportedVersion,
    ReadError,
    ColumnOutOfBounds,
    NoPages,
    InvalidBufferIndex,
    IndexOutOfBounds,
};

/// High-level table reader for Lance files.
pub const Table = struct {
    allocator: std.mem.Allocator,
    lance_file: LanceFile,
    schema: ?Schema,

    const Self = @This();

    /// Open a table from a byte slice.
    pub fn init(allocator: std.mem.Allocator, data: []const u8) TableError!Self {
        var lance_file = LanceFile.init(allocator, data) catch |err| {
            return switch (err) {
                error.FileTooSmall => TableError.FileTooSmall,
                error.InvalidMagic => TableError.InvalidMagic,
                error.UnsupportedVersion => TableError.UnsupportedVersion,
                error.InvalidMetadata => TableError.InvalidMetadata,
                error.OutOfMemory => TableError.OutOfMemory,
                else => TableError.ReadError,
            };
        };
        errdefer lance_file.deinit();

        // Parse schema from global buffer 0
        var schema: ?Schema = null;
        if (lance_file.getSchemaBytes()) |schema_bytes| {
            schema = Schema.parse(allocator, schema_bytes) catch null;
        }

        return Self{
            .allocator = allocator,
            .lance_file = lance_file,
            .schema = schema,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.schema) |*s| s.deinit();
        self.lance_file.deinit();
    }

    /// Get the number of columns.
    pub fn numColumns(self: Self) u32 {
        return self.lance_file.numColumns();
    }

    /// Get column names from schema.
    pub fn columnNames(self: Self) TableError![][]const u8 {
        const schema = self.schema orelse return TableError.NoSchema;
        return schema.columnNames(self.allocator) catch return TableError.OutOfMemory;
    }

    /// Get the schema.
    pub fn getSchema(self: Self) ?Schema {
        return self.schema;
    }

    /// Get column index by name (returns field array index).
    pub fn columnIndex(self: Self, name: []const u8) ?usize {
        const schema = self.schema orelse return null;
        return schema.fieldIndex(name);
    }

    /// Get physical column ID by name (for use with column metadata).
    pub fn physicalColumnId(self: Self, name: []const u8) ?u32 {
        const schema = self.schema orelse return null;
        return schema.physicalColumnId(name);
    }

    /// Get field info by column index (array index in schema.fields).
    pub fn getField(self: Self, col_idx: usize) ?Field {
        const schema = self.schema orelse return null;
        if (col_idx >= schema.fields.len) return null;
        return schema.fields[col_idx];
    }

    /// Get field info by physical column ID.
    pub fn getFieldById(self: Self, field_id: u32) ?Field {
        const schema = self.schema orelse return null;
        for (schema.fields) |field| {
            if (field.id >= 0 and @as(u32, @intCast(field.id)) == field_id) {
                return field;
            }
        }
        return null;
    }

    /// Get row count for a column.
    pub fn rowCount(self: Self, col_idx: u32) TableError!u64 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        return col_meta.rowCount();
    }

    // ========================================================================
    // Typed Column Readers
    // ========================================================================

    /// Read all int64 values from a column (reads ALL pages).
    pub fn readInt64Column(self: Self, col_idx: u32) TableError![]i64 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Calculate total values across all pages
        var total_values: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_sizes.len > 0) {
                total_values += page.buffer_sizes[0] / @sizeOf(i64);
            }
        }

        // Allocate result buffer for all pages
        var result = self.allocator.alloc(i64, total_values) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        // Read each page's buffer and decode
        var offset: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_offsets.len == 0 or page.buffer_sizes.len == 0) continue;

            const buffer_offset = page.buffer_offsets[0];
            const buffer_size = page.buffer_sizes[0];

            const buffer_data = self.lance_file.readBytes(buffer_offset, buffer_size) catch {
                return TableError.InvalidMetadata;
            };

            const decoder = PlainDecoder.init(buffer_data);
            const page_values = decoder.readAllInt64(self.allocator) catch return TableError.OutOfMemory;
            defer self.allocator.free(page_values);

            @memcpy(result[offset .. offset + page_values.len], page_values);
            offset += page_values.len;
        }

        return result;
    }

    /// Read all int64 values from a column by name.
    pub fn readInt64ColumnByName(self: Self, name: []const u8) TableError![]i64 {
        const idx = self.columnIndex(name) orelse return TableError.ColumnNotFound;
        return self.readInt64Column(@intCast(idx));
    }

    /// Read all float64 values from a column (reads ALL pages).
    pub fn readFloat64Column(self: Self, col_idx: u32) TableError![]f64 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Calculate total values across all pages
        var total_values: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_sizes.len > 0) {
                total_values += page.buffer_sizes[0] / @sizeOf(f64);
            }
        }

        // Allocate result buffer for all pages
        var result = self.allocator.alloc(f64, total_values) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        // Read each page's buffer and decode
        var offset: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_offsets.len == 0 or page.buffer_sizes.len == 0) continue;

            const buffer_offset = page.buffer_offsets[0];
            const buffer_size = page.buffer_sizes[0];

            const buffer_data = self.lance_file.readBytes(buffer_offset, buffer_size) catch {
                return TableError.InvalidMetadata;
            };

            const decoder = PlainDecoder.init(buffer_data);
            const page_values = decoder.readAllFloat64(self.allocator) catch return TableError.OutOfMemory;
            defer self.allocator.free(page_values);

            @memcpy(result[offset .. offset + page_values.len], page_values);
            offset += page_values.len;
        }

        return result;
    }

    /// Read all float64 values from a column by name.
    pub fn readFloat64ColumnByName(self: Self, name: []const u8) TableError![]f64 {
        const idx = self.columnIndex(name) orelse return TableError.ColumnNotFound;
        return self.readFloat64Column(@intCast(idx));
    }

    /// Read all int32 values from a column (reads ALL pages).
    pub fn readInt32Column(self: Self, col_idx: u32) TableError![]i32 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Calculate total values across all pages
        var total_values: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_sizes.len > 0) {
                total_values += page.buffer_sizes[0] / @sizeOf(i32);
            }
        }

        // Allocate result buffer for all pages
        var result = self.allocator.alloc(i32, total_values) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        // Read each page's buffer and decode
        var offset: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_offsets.len == 0 or page.buffer_sizes.len == 0) continue;

            const buffer_offset = page.buffer_offsets[0];
            const buffer_size = page.buffer_sizes[0];

            const buffer_data = self.lance_file.readBytes(buffer_offset, buffer_size) catch {
                return TableError.InvalidMetadata;
            };

            const decoder = PlainDecoder.init(buffer_data);
            const page_values = decoder.readAllInt32(self.allocator) catch return TableError.OutOfMemory;
            defer self.allocator.free(page_values);

            @memcpy(result[offset .. offset + page_values.len], page_values);
            offset += page_values.len;
        }

        return result;
    }

    /// Read all int32 values from a column by name.
    pub fn readInt32ColumnByName(self: Self, name: []const u8) TableError![]i32 {
        const idx = self.columnIndex(name) orelse return TableError.ColumnNotFound;
        return self.readInt32Column(@intCast(idx));
    }

    /// Read all float32 values from a column (reads ALL pages).
    pub fn readFloat32Column(self: Self, col_idx: u32) TableError![]f32 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Calculate total values across all pages
        var total_values: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_sizes.len > 0) {
                total_values += page.buffer_sizes[0] / @sizeOf(f32);
            }
        }

        // Allocate result buffer for all pages
        var result = self.allocator.alloc(f32, total_values) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        // Read each page's buffer and decode
        var offset: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_offsets.len == 0 or page.buffer_sizes.len == 0) continue;

            const buffer_offset = page.buffer_offsets[0];
            const buffer_size = page.buffer_sizes[0];

            const buffer_data = self.lance_file.readBytes(buffer_offset, buffer_size) catch {
                return TableError.InvalidMetadata;
            };

            const decoder = PlainDecoder.init(buffer_data);
            const page_values = decoder.readAllFloat32(self.allocator) catch return TableError.OutOfMemory;
            defer self.allocator.free(page_values);

            @memcpy(result[offset .. offset + page_values.len], page_values);
            offset += page_values.len;
        }

        return result;
    }

    /// Read all float32 values from a column by name.
    pub fn readFloat32ColumnByName(self: Self, name: []const u8) TableError![]f32 {
        const idx = self.columnIndex(name) orelse return TableError.ColumnNotFound;
        return self.readFloat32Column(@intCast(idx));
    }

    /// Read all boolean values from a column (reads ALL pages).
    pub fn readBoolColumn(self: Self, col_idx: u32) TableError![]bool {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Calculate total rows across all pages
        var total_rows: usize = 0;
        for (col_meta.pages) |page| {
            total_rows += @intCast(page.length);
        }

        // Allocate result buffer for all pages
        var result = self.allocator.alloc(bool, total_rows) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        // Read each page's buffer and decode
        var offset: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_offsets.len == 0 or page.buffer_sizes.len == 0) continue;

            const buffer_offset = page.buffer_offsets[0];
            const buffer_size = page.buffer_sizes[0];
            const page_rows: usize = @intCast(page.length);

            const buffer_data = self.lance_file.readBytes(buffer_offset, buffer_size) catch {
                return TableError.InvalidMetadata;
            };

            const decoder = PlainDecoder.init(buffer_data);
            const page_values = decoder.readAllBool(self.allocator, page_rows) catch return TableError.OutOfMemory;
            defer self.allocator.free(page_values);

            @memcpy(result[offset .. offset + page_values.len], page_values);
            offset += page_values.len;
        }

        return result;
    }

    /// Read all boolean values from a column by name.
    pub fn readBoolColumnByName(self: Self, name: []const u8) TableError![]bool {
        const idx = self.columnIndex(name) orelse return TableError.ColumnNotFound;
        return self.readBoolColumn(@intCast(idx));
    }

    // ========================================================================
    // Read At Indices - Phase 2 API for efficient sparse reads
    // ========================================================================
    // These methods read only specific row indices, enabling efficient
    // column projection after WHERE filtering.
    //
    // Current implementation: reads full column then filters (fallback)
    // Future optimization: direct byte-range reads for fixed-size types

    /// Read int64 values at specific row indices.
    pub fn readInt64AtIndices(self: Self, col_idx: u32, indices: []const u32) TableError![]i64 {
        // Phase 2 implementation: read full column and filter
        // TODO: Optimize with direct byte-range reads (index * 8 bytes)
        const all_data = try self.readInt64Column(col_idx);
        defer self.allocator.free(all_data);

        const result = self.allocator.alloc(i64, indices.len) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= all_data.len) return TableError.IndexOutOfBounds;
            result[i] = all_data[idx];
        }
        return result;
    }

    /// Read float64 values at specific row indices.
    pub fn readFloat64AtIndices(self: Self, col_idx: u32, indices: []const u32) TableError![]f64 {
        const all_data = try self.readFloat64Column(col_idx);
        defer self.allocator.free(all_data);

        const result = self.allocator.alloc(f64, indices.len) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= all_data.len) return TableError.IndexOutOfBounds;
            result[i] = all_data[idx];
        }
        return result;
    }

    /// Read int32 values at specific row indices.
    pub fn readInt32AtIndices(self: Self, col_idx: u32, indices: []const u32) TableError![]i32 {
        const all_data = try self.readInt32Column(col_idx);
        defer self.allocator.free(all_data);

        const result = self.allocator.alloc(i32, indices.len) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= all_data.len) return TableError.IndexOutOfBounds;
            result[i] = all_data[idx];
        }
        return result;
    }

    /// Read float32 values at specific row indices.
    pub fn readFloat32AtIndices(self: Self, col_idx: u32, indices: []const u32) TableError![]f32 {
        const all_data = try self.readFloat32Column(col_idx);
        defer self.allocator.free(all_data);

        const result = self.allocator.alloc(f32, indices.len) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= all_data.len) return TableError.IndexOutOfBounds;
            result[i] = all_data[idx];
        }
        return result;
    }

    /// Read boolean values at specific row indices.
    pub fn readBoolAtIndices(self: Self, col_idx: u32, indices: []const u32) TableError![]bool {
        const all_data = try self.readBoolColumn(col_idx);
        defer self.allocator.free(all_data);

        const result = self.allocator.alloc(bool, indices.len) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= all_data.len) return TableError.IndexOutOfBounds;
            result[i] = all_data[idx];
        }
        return result;
    }

    /// Read string values at specific row indices.
    /// Caller must free both the returned slice and each string.
    pub fn readStringAtIndices(self: Self, col_idx: u32, indices: []const u32) TableError![][]const u8 {
        const all_data = try self.readStringColumn(col_idx);
        defer {
            for (all_data) |s| self.allocator.free(s);
            self.allocator.free(all_data);
        }

        const result = self.allocator.alloc([]const u8, indices.len) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(result);

        for (indices, 0..) |idx, i| {
            if (idx >= all_data.len) return TableError.IndexOutOfBounds;
            result[i] = self.allocator.dupe(u8, all_data[idx]) catch return TableError.OutOfMemory;
        }
        return result;
    }

    /// Read raw column buffer (first page, first buffer).
    /// For multi-page support, use typed column readers (readInt64Column, etc.).
    pub fn getColumnBuffer(self: Self, col_idx: u32) TableError![]const u8 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) {
            return TableError.InvalidMetadata;
        }

        const page = col_meta.pages[0];
        if (page.buffer_offsets.len == 0) {
            return TableError.InvalidMetadata;
        }

        const buffer_offset = page.buffer_offsets[0];
        const buffer_size = page.buffer_sizes[0];

        return self.lance_file.readBytes(buffer_offset, buffer_size) catch {
            return TableError.InvalidMetadata;
        };
    }

    /// Get multiple buffers for a column (needed for variable-length types like strings).
    /// Returns a slice of buffers corresponding to the requested buffer indices.
    fn getColumnBuffers(self: Self, col_idx: u32, buffer_indices: []const usize) TableError![][]const u8 {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;
        const page = col_meta.pages[0];

        var buffers = try self.allocator.alloc([]const u8, buffer_indices.len);
        errdefer self.allocator.free(buffers);

        for (buffer_indices, 0..) |buf_idx, i| {
            if (buf_idx >= page.buffer_offsets.len) return TableError.InvalidBufferIndex;

            const buffer_offset = page.buffer_offsets[buf_idx];
            const buffer_size = page.buffer_sizes[buf_idx];

            buffers[i] = self.lance_file.readBytes(buffer_offset, buffer_size) catch {
                return TableError.InvalidMetadata;
            };
        }

        return buffers;
    }

    /// Get the number of rows in a specific column.
    /// Reads the column metadata and sums the length across all pages.
    fn numRows(self: Self, col_idx: u32) TableError!usize {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        // Sum length across all pages
        var total_rows: usize = 0;
        for (col_meta.pages) |page| {
            total_rows += @intCast(page.length);
        }

        return total_rows;
    }

    /// Read a string column by index (reads ALL pages).
    /// Returns a slice of allocated strings (UTF-8 byte slices).
    /// Caller must free each string AND the slice itself using the same allocator.
    pub fn readStringColumn(self: Self, col_idx: u32) TableError![][]const u8 {
        // Get column metadata
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Calculate total rows across all pages
        var total_rows: usize = 0;
        for (col_meta.pages) |page| {
            total_rows += @intCast(page.length);
        }

        // Allocate result buffer for all pages
        var owned_strings = self.allocator.alloc([]const u8, total_rows) catch {
            return TableError.OutOfMemory;
        };
        errdefer {
            for (owned_strings) |str| {
                if (str.len > 0) self.allocator.free(str);
            }
            self.allocator.free(owned_strings);
        }

        // Read each page
        var result_offset: usize = 0;
        for (col_meta.pages) |page| {
            // Lance stores string columns with TWO separate buffers per page:
            // - Buffer 0: offsets array (uint32 or uint64, marking END positions)
            // - Buffer 1: string data (concatenated UTF-8 bytes)
            if (page.buffer_offsets.len < 2) return TableError.InvalidMetadata;

            // Buffer 0 = offsets array
            const offsets_offset = page.buffer_offsets[0];
            const offsets_size = page.buffer_sizes[0];
            const offsets_buffer = self.lance_file.readBytes(offsets_offset, offsets_size) catch {
                return TableError.InvalidMetadata;
            };

            // Buffer 1 = string data
            const data_offset = page.buffer_offsets[1];
            const data_size = page.buffer_sizes[1];
            const data_buffer = self.lance_file.readBytes(data_offset, data_size) catch {
                return TableError.InvalidMetadata;
            };

            // Decode strings (returns slices into data_buffer, not owned copies)
            const string_slices = PlainDecoder.readAllStrings(offsets_buffer, data_buffer, self.allocator) catch {
                return TableError.InvalidMetadata;
            };
            defer self.allocator.free(string_slices);

            // Copy each string into owned memory
            for (string_slices, 0..) |slice, i| {
                const copy = self.allocator.alloc(u8, slice.len) catch {
                    // Mark how many we successfully allocated for errdefer
                    owned_strings = owned_strings[0 .. result_offset + i];
                    return TableError.OutOfMemory;
                };
                @memcpy(copy, slice);
                owned_strings[result_offset + i] = copy;
            }
            result_offset += string_slices.len;
        }

        return owned_strings;
    }

    /// Read a string column by name.
    pub fn readStringColumnByName(self: Self, name: []const u8) TableError![][]const u8 {
        const idx = self.columnIndex(name) orelse return TableError.ColumnNotFound;
        return self.readStringColumn(@intCast(idx));
    }

    /// String column buffers for zero-copy Arrow export.
    pub const StringBuffers = struct {
        offsets: []const u8, // Raw Lance offsets buffer (int32 end positions)
        data: []const u8, // Raw string data buffer
    };

    /// Get raw string column buffers for zero-copy Arrow export (reads ALL pages).
    /// Returns merged offsets and data buffers.
    /// Caller must free both buffers using the table's allocator.
    pub fn getStringColumnBuffers(self: Self, col_idx: u32) TableError!StringBuffers {
        const col_meta_bytes = self.lance_file.getColumnMetadataBytes(col_idx) catch {
            return TableError.ColumnOutOfBounds;
        };

        var col_meta = ColumnMetadata.parse(self.allocator, col_meta_bytes) catch {
            return TableError.InvalidMetadata;
        };
        defer col_meta.deinit(self.allocator);

        if (col_meta.pages.len == 0) return TableError.NoPages;

        // Single page - return directly (zero-copy)
        if (col_meta.pages.len == 1) {
            const page = col_meta.pages[0];
            if (page.buffer_offsets.len < 2) return TableError.InvalidMetadata;

            const offsets_buffer = self.lance_file.readBytes(page.buffer_offsets[0], page.buffer_sizes[0]) catch {
                return TableError.InvalidMetadata;
            };
            const data_buffer = self.lance_file.readBytes(page.buffer_offsets[1], page.buffer_sizes[1]) catch {
                return TableError.InvalidMetadata;
            };

            return StringBuffers{
                .offsets = offsets_buffer,
                .data = data_buffer,
            };
        }

        // Multiple pages - need to merge offsets and data buffers
        // Calculate total sizes
        var total_offsets_size: usize = 0;
        var total_data_size: usize = 0;
        for (col_meta.pages) |page| {
            if (page.buffer_sizes.len >= 2) {
                total_offsets_size += page.buffer_sizes[0];
                total_data_size += page.buffer_sizes[1];
            }
        }

        // Allocate merged buffers
        const merged_offsets = self.allocator.alloc(u8, total_offsets_size) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(merged_offsets);

        const merged_data = self.allocator.alloc(u8, total_data_size) catch return TableError.OutOfMemory;
        errdefer self.allocator.free(merged_data);

        // Copy data from each page, adjusting offsets
        var offsets_pos: usize = 0;
        var data_pos: usize = 0;
        var data_offset_adjustment: u32 = 0;

        for (col_meta.pages) |page| {
            if (page.buffer_offsets.len < 2) continue;

            // Read page buffers
            const page_offsets = self.lance_file.readBytes(page.buffer_offsets[0], page.buffer_sizes[0]) catch {
                return TableError.InvalidMetadata;
            };
            const page_data = self.lance_file.readBytes(page.buffer_offsets[1], page.buffer_sizes[1]) catch {
                return TableError.InvalidMetadata;
            };

            // Copy and adjust offsets (Lance uses i32 end-offsets)
            const num_offsets = page_offsets.len / @sizeOf(i32);
            const src_offsets = @as([*]const i32, @ptrCast(@alignCast(page_offsets.ptr)))[0..num_offsets];
            const dst_offsets = @as([*]i32, @ptrCast(@alignCast(merged_offsets.ptr + offsets_pos)))[0..num_offsets];

            for (src_offsets, 0..) |offset, i| {
                dst_offsets[i] = offset + @as(i32, @intCast(data_offset_adjustment));
            }

            // Copy data
            @memcpy(merged_data[data_pos .. data_pos + page_data.len], page_data);

            offsets_pos += page_offsets.len;
            data_pos += page_data.len;
            data_offset_adjustment = @intCast(data_pos);
        }

        return StringBuffers{
            .offsets = merged_offsets,
            .data = merged_data,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "table error enum" {
    // Just verify the error set compiles
    const err: TableError = TableError.NoSchema;
    try std.testing.expect(err == TableError.NoSchema);
}
