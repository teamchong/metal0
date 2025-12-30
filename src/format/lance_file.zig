//! Lance file reader - high-level API for reading Lance data files.
//!
//! A Lance data file (.lance) contains:
//! 1. Data pages (column data)
//! 2. Column metadata (protobuf encoded)
//! 3. Offset tables (position, length pairs)
//! 4. Global buffers (schema, statistics)
//! 5. Footer (40 bytes)

const std = @import("std");
const footer_mod = @import("footer.zig");
const io = @import("lanceql.io");
const proto = @import("lanceql.proto");

const Footer = footer_mod.Footer;
const FOOTER_SIZE = footer_mod.FOOTER_SIZE;
const Reader = io.Reader;
const MemoryReader = io.MemoryReader;
const ProtoDecoder = proto.ProtoDecoder;

/// Errors that can occur when reading a Lance file
pub const LanceFileError = error{
    FileTooSmall,
    InvalidMagic,
    UnsupportedVersion,
    InvalidMetadata,
    ReadError,
    OutOfMemory,
    ColumnOutOfBounds,
};

/// Position and length pair from offset tables
pub const OffsetEntry = struct {
    position: u64,
    length: u64,
};

/// High-level Lance file reader
pub const LanceFile = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    footer: Footer,

    /// Column metadata entries (position, length for each column)
    column_meta_entries: []const OffsetEntry,
    /// Global buffer entries
    global_buffer_entries: []const OffsetEntry,

    const Self = @This();

    /// Open a Lance file from a byte slice
    pub fn init(allocator: std.mem.Allocator, data: []const u8) LanceFileError!Self {
        if (data.len < FOOTER_SIZE) {
            return LanceFileError.FileTooSmall;
        }

        // Parse footer
        const footer = Footer.parse(data[data.len - FOOTER_SIZE ..][0..FOOTER_SIZE]) catch {
            return LanceFileError.InvalidMagic;
        };

        if (!footer.isSupported()) {
            return LanceFileError.UnsupportedVersion;
        }

        // Parse column metadata offset table
        // Each entry is (position: u64, length: u64) = 16 bytes
        const num_cols = footer.num_columns;
        const cmo_start: usize = @intCast(footer.column_meta_offsets_start);

        var col_entries = allocator.alloc(OffsetEntry, num_cols) catch return LanceFileError.OutOfMemory;
        errdefer allocator.free(col_entries);

        var i: u32 = 0;
        while (i < num_cols) : (i += 1) {
            const entry_pos = cmo_start + (i * 16); // 16 bytes per entry
            if (entry_pos + 16 > data.len) {
                return LanceFileError.InvalidMetadata;
            }
            col_entries[i] = .{
                .position = std.mem.readInt(u64, data[entry_pos..][0..8], .little),
                .length = std.mem.readInt(u64, data[entry_pos + 8 ..][0..8], .little),
            };
        }

        // Parse global buffer offset table
        const num_global = footer.num_global_buffers;
        const gbo_start: usize = @intCast(footer.global_buff_offsets_start);

        var global_entries = allocator.alloc(OffsetEntry, num_global) catch return LanceFileError.OutOfMemory;
        errdefer allocator.free(global_entries);

        i = 0;
        while (i < num_global) : (i += 1) {
            const entry_pos = gbo_start + (i * 16);
            if (entry_pos + 16 > data.len) {
                return LanceFileError.InvalidMetadata;
            }
            global_entries[i] = .{
                .position = std.mem.readInt(u64, data[entry_pos..][0..8], .little),
                .length = std.mem.readInt(u64, data[entry_pos + 8 ..][0..8], .little),
            };
        }

        return Self{
            .allocator = allocator,
            .data = data,
            .footer = footer,
            .column_meta_entries = col_entries,
            .global_buffer_entries = global_entries,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.column_meta_entries);
        self.allocator.free(self.global_buffer_entries);
    }

    /// Get the number of columns in this file
    pub fn numColumns(self: Self) u32 {
        return self.footer.num_columns;
    }

    /// Get the format version
    pub fn version(self: Self) footer_mod.Version {
        return self.footer.getVersion();
    }

    /// Get raw column metadata bytes for a column
    pub fn getColumnMetadataBytes(self: Self, col_idx: u32) LanceFileError![]const u8 {
        if (col_idx >= self.footer.num_columns) {
            return LanceFileError.ColumnOutOfBounds;
        }

        const entry = self.column_meta_entries[col_idx];
        const pos: usize = @intCast(entry.position);
        const len: usize = @intCast(entry.length);

        if (pos + len > self.data.len) {
            return LanceFileError.InvalidMetadata;
        }

        return self.data[pos..][0..len];
    }

    /// Get a global buffer by index
    pub fn getGlobalBuffer(self: Self, buf_idx: u32) LanceFileError![]const u8 {
        if (buf_idx >= self.footer.num_global_buffers) {
            return LanceFileError.ColumnOutOfBounds;
        }

        const entry = self.global_buffer_entries[buf_idx];
        const pos: usize = @intCast(entry.position);
        const len: usize = @intCast(entry.length);

        if (pos + len > self.data.len) {
            return LanceFileError.InvalidMetadata;
        }

        return self.data[pos..][0..len];
    }

    /// Get the data section (bytes before column metadata)
    pub fn getDataSection(self: Self) []const u8 {
        const meta_start: usize = @intCast(self.footer.column_meta_start);
        // Find actual data start (skip to first non-metadata section)
        // Data typically starts at offset 0
        return self.data[0..meta_start];
    }

    /// Read raw bytes at a specific offset
    pub fn readBytes(self: Self, offset: u64, len: u64) LanceFileError![]const u8 {
        const pos: usize = @intCast(offset);
        const size: usize = @intCast(len);

        if (pos + size > self.data.len) {
            return LanceFileError.InvalidMetadata;
        }

        return self.data[pos..][0..size];
    }

    /// Parse the schema from global buffer 0 (if present)
    pub fn getSchemaBytes(self: Self) ?[]const u8 {
        if (self.footer.num_global_buffers == 0) return null;
        return self.getGlobalBuffer(0) catch null;
    }
};

/// Read a Lance file from disk
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) !LanceFile {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
    errdefer allocator.free(data);

    return LanceFile.init(allocator, data);
}

// ============================================================================
// Tests
// ============================================================================

test "offset entry size" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(OffsetEntry));
}
