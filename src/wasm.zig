//! WASM entry point for LanceQL.
//!
//! This module provides exported functions that can be called from JavaScript
//! in the browser. Uses direct byte manipulation for WASM compatibility.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

const FOOTER_SIZE: usize = 40;
const LANCE_MAGIC = "LANC";

// ============================================================================
// Simple bump allocator for WASM (no std.heap.wasm_allocator dependency)
// ============================================================================

var heap: [1024 * 1024]u8 = undefined; // 1MB heap
var heap_offset: usize = 0;

fn wasmAlloc(len: usize) ?[*]u8 {
    // Get current address and align it to 8 bytes
    const heap_base = @intFromPtr(&heap[0]);
    const current_addr = heap_base + heap_offset;
    const aligned_addr = (current_addr + 7) & ~@as(usize, 7);
    const padding = aligned_addr - current_addr;

    heap_offset += padding;

    const aligned_len = (len + 7) & ~@as(usize, 7); // 8-byte align length too
    if (heap_offset + aligned_len > heap.len) return null;
    const ptr: [*]u8 = @ptrCast(&heap[heap_offset]);
    heap_offset += aligned_len;
    return ptr;
}

fn wasmReset() void {
    heap_offset = 0;
}

// ============================================================================
// Global state
// ============================================================================

var file_data: ?[]const u8 = null;
var num_columns: u32 = 0;
var column_meta_offsets_start: u64 = 0;

// ============================================================================
// Exported Memory Management
// ============================================================================

export fn alloc(len: usize) ?[*]u8 {
    return wasmAlloc(len);
}

export fn free(ptr: [*]u8, len: usize) void {
    _ = ptr;
    _ = len;
    // Bump allocator doesn't support individual frees
}

export fn resetHeap() void {
    wasmReset();
    file_data = null;
    num_columns = 0;
}

// ============================================================================
// Footer Parsing Helpers
// ============================================================================

fn readU64LE(data: []const u8, offset: usize) u64 {
    if (offset + 8 > data.len) return 0;
    return std.mem.readInt(u64, data[offset..][0..8], .little);
}

fn readU32LE(data: []const u8, offset: usize) u32 {
    if (offset + 4 > data.len) return 0;
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

fn readU16LE(data: []const u8, offset: usize) u16 {
    if (offset + 2 > data.len) return 0;
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn readI64LE(data: []const u8, offset: usize) i64 {
    if (offset + 8 > data.len) return 0;
    return std.mem.readInt(i64, data[offset..][0..8], .little);
}

fn readI32LE(data: []const u8, offset: usize) i32 {
    if (offset + 4 > data.len) return 0;
    return std.mem.readInt(i32, data[offset..][0..4], .little);
}

fn readI16LE(data: []const u8, offset: usize) i16 {
    if (offset + 2 > data.len) return 0;
    return std.mem.readInt(i16, data[offset..][0..2], .little);
}

fn readI8(data: []const u8, offset: usize) i8 {
    if (offset >= data.len) return 0;
    return @bitCast(data[offset]);
}

fn readU8(data: []const u8, offset: usize) u8 {
    if (offset >= data.len) return 0;
    return data[offset];
}

fn readF64LE(data: []const u8, offset: usize) f64 {
    const bits = readU64LE(data, offset);
    return @bitCast(bits);
}

fn readF32LE(data: []const u8, offset: usize) f32 {
    const bits = readU32LE(data, offset);
    return @bitCast(bits);
}

// ============================================================================
// Footer Parsing
// ============================================================================

export fn isValidLanceFile(data: [*]const u8, len: usize) u32 {
    if (len < FOOTER_SIZE) return 0;

    // Check magic at end
    const magic_offset = len - 4;
    if (data[magic_offset] != 'L' or data[magic_offset + 1] != 'A' or
        data[magic_offset + 2] != 'N' or data[magic_offset + 3] != 'C')
    {
        return 0;
    }
    return 1;
}

export fn parseFooterGetColumns(data: [*]const u8, len: usize) u32 {
    if (isValidLanceFile(data, len) == 0) return 0;
    const footer_start = len - FOOTER_SIZE;
    return readU32LE(data[0..len], footer_start + 28);
}

export fn parseFooterGetMajorVersion(data: [*]const u8, len: usize) u16 {
    if (isValidLanceFile(data, len) == 0) return 0;
    const footer_start = len - FOOTER_SIZE;
    return readU16LE(data[0..len], footer_start + 32);
}

export fn parseFooterGetMinorVersion(data: [*]const u8, len: usize) u16 {
    if (isValidLanceFile(data, len) == 0) return 0;
    const footer_start = len - FOOTER_SIZE;
    return readU16LE(data[0..len], footer_start + 34);
}

export fn getColumnMetaStart(data: [*]const u8, len: usize) u64 {
    if (isValidLanceFile(data, len) == 0) return 0;
    const footer_start = len - FOOTER_SIZE;
    return readU64LE(data[0..len], footer_start + 0);
}

export fn getColumnMetaOffsetsStart(data: [*]const u8, len: usize) u64 {
    if (isValidLanceFile(data, len) == 0) return 0;
    const footer_start = len - FOOTER_SIZE;
    return readU64LE(data[0..len], footer_start + 8);
}

export fn getVersion() u32 {
    return 0x000100; // v0.1.0
}

// ============================================================================
// File Operations
// ============================================================================

export fn openFile(data: [*]const u8, len: usize) u32 {
    if (isValidLanceFile(data, len) == 0) return 0;

    file_data = data[0..len];

    const footer_start = len - FOOTER_SIZE;
    num_columns = readU32LE(data[0..len], footer_start + 28);
    column_meta_offsets_start = readU64LE(data[0..len], footer_start + 8);

    return 1;
}

export fn closeFile() void {
    file_data = null;
    num_columns = 0;
    column_meta_offsets_start = 0;
}

export fn getNumColumns() u32 {
    return num_columns;
}

// ============================================================================
// Column Metadata Parsing
// ============================================================================

fn getColumnOffsetEntry(col_idx: u32) struct { pos: u64, len: u64 } {
    const data = file_data orelse return .{ .pos = 0, .len = 0 };
    if (col_idx >= num_columns) return .{ .pos = 0, .len = 0 };

    const entry_offset: usize = @intCast(column_meta_offsets_start + col_idx * 16);
    if (entry_offset + 16 > data.len) return .{ .pos = 0, .len = 0 };

    return .{
        .pos = readU64LE(data, entry_offset),
        .len = readU64LE(data, entry_offset + 8),
    };
}

// Parse varint from protobuf data
fn readVarint(data: []const u8, offset: *usize) u64 {
    var result: u64 = 0;
    var shift: u6 = 0;

    while (offset.* < data.len) {
        const byte = data[offset.*];
        offset.* += 1;
        result |= @as(u64, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift +|= 7;
    }
    return result;
}

// Get page buffer info from column metadata protobuf
fn getPageBufferInfo(col_meta: []const u8) struct { offset: u64, size: u64, rows: u64 } {
    var pos: usize = 0;
    var page_offset: u64 = 0;
    var page_size: u64 = 0;
    var page_rows: u64 = 0;

    while (pos < col_meta.len) {
        const tag = readVarint(col_meta, &pos);
        const field_num = tag >> 3;
        const wire_type: u3 = @truncate(tag);

        switch (field_num) {
            1 => { // encoding (length-delimited) - skip it
                if (wire_type == 2) {
                    const skip_len = readVarint(col_meta, &pos);
                    pos += @as(usize, @intCast(skip_len));
                }
            },
            2 => { // pages (length-delimited)
                if (wire_type != 2) break;
                const page_len = readVarint(col_meta, &pos);
                const page_end = pos + @as(usize, @intCast(page_len));

                // Parse page message
                while (pos < page_end and pos < col_meta.len) {
                    const page_tag = readVarint(col_meta, &pos);
                    const page_field = page_tag >> 3;
                    const page_wire: u3 = @truncate(page_tag);

                    switch (page_field) {
                        1 => { // buffer_offsets (packed repeated uint64)
                            if (page_wire == 2) {
                                const packed_len = readVarint(col_meta, &pos);
                                const packed_end = pos + @as(usize, @intCast(packed_len));
                                // Read first offset only
                                if (pos < packed_end) {
                                    page_offset = readVarint(col_meta, &pos);
                                }
                                // Skip rest
                                pos = packed_end;
                            } else {
                                page_offset = readVarint(col_meta, &pos);
                            }
                        },
                        2 => { // buffer_sizes (packed repeated uint64)
                            if (page_wire == 2) {
                                const packed_len = readVarint(col_meta, &pos);
                                const packed_end = pos + @as(usize, @intCast(packed_len));
                                // Read first size only
                                if (pos < packed_end) {
                                    page_size = readVarint(col_meta, &pos);
                                }
                                // Skip rest
                                pos = packed_end;
                            } else {
                                page_size = readVarint(col_meta, &pos);
                            }
                        },
                        3 => { // length (rows)
                            page_rows = readVarint(col_meta, &pos);
                        },
                        else => {
                            // Skip field
                            if (page_wire == 0) {
                                _ = readVarint(col_meta, &pos);
                            } else if (page_wire == 2) {
                                const skip_len = readVarint(col_meta, &pos);
                                pos += @as(usize, @intCast(skip_len));
                            } else if (page_wire == 5) {
                                pos += 4; // 32-bit fixed
                            } else if (page_wire == 1) {
                                pos += 8; // 64-bit fixed
                            }
                        },
                    }
                }
                // Only read first page
                return .{ .offset = page_offset, .size = page_size, .rows = page_rows };
            },
            else => {
                // Skip field
                if (wire_type == 0) {
                    _ = readVarint(col_meta, &pos);
                } else if (wire_type == 2) {
                    const skip_len = readVarint(col_meta, &pos);
                    pos += @as(usize, @intCast(skip_len));
                } else if (wire_type == 5) {
                    pos += 4; // 32-bit fixed
                } else if (wire_type == 1) {
                    pos += 8; // 64-bit fixed
                }
            },
        }
    }

    return .{ .offset = page_offset, .size = page_size, .rows = page_rows };
}

export fn getRowCount(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);
    return info.rows;
}

// Debug: get buffer offset for column
export fn getColumnBufferOffset(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);
    return info.offset;
}

// Debug: get buffer size for column
export fn getColumnBufferSize(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);
    return info.size;
}

// ============================================================================
// Column Reading
// ============================================================================

export fn readInt64Column(col_idx: u32, out_ptr: [*]i64, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 8, max_len);
    for (0..count) |i| {
        out_ptr[i] = readI64LE(data, buf_start + i * 8);
    }
    return count;
}

export fn readFloat64Column(col_idx: u32, out_ptr: [*]f64, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 8, max_len);
    for (0..count) |i| {
        out_ptr[i] = readF64LE(data, buf_start + i * 8);
    }
    return count;
}

export fn allocInt64Buffer(count: usize) ?[*]i64 {
    const ptr = wasmAlloc(count * 8) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

export fn freeInt64Buffer(ptr: [*]i64, count: usize) void {
    _ = ptr;
    _ = count;
}

export fn allocFloat64Buffer(count: usize) ?[*]f64 {
    const ptr = wasmAlloc(count * 8) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

export fn freeFloat64Buffer(ptr: [*]f64, count: usize) void {
    _ = ptr;
    _ = count;
}

// ============================================================================
// Query Execution (Simple filter/projection for WASM)
// ============================================================================

/// Filter result indices where column value matches condition
/// op: 0=eq, 1=ne, 2=lt, 3=le, 4=gt, 5=ge
export fn filterInt64Column(
    col_idx: u32,
    op: u32,
    value: i64,
    out_indices: [*]u32,
    max_indices: usize,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    var out_count: usize = 0;

    for (0..row_count) |i| {
        if (out_count >= max_indices) break;

        const col_val = readI64LE(data, buf_start + i * 8);
        const matches = switch (op) {
            0 => col_val == value, // eq
            1 => col_val != value, // ne
            2 => col_val < value, // lt
            3 => col_val <= value, // le
            4 => col_val > value, // gt
            5 => col_val >= value, // ge
            else => false,
        };

        if (matches) {
            out_indices[out_count] = @intCast(i);
            out_count += 1;
        }
    }

    return out_count;
}

/// Filter float64 column
export fn filterFloat64Column(
    col_idx: u32,
    op: u32,
    value: f64,
    out_indices: [*]u32,
    max_indices: usize,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    var out_count: usize = 0;

    for (0..row_count) |i| {
        if (out_count >= max_indices) break;

        const col_val = readF64LE(data, buf_start + i * 8);
        const matches = switch (op) {
            0 => col_val == value, // eq
            1 => col_val != value, // ne
            2 => col_val < value, // lt
            3 => col_val <= value, // le
            4 => col_val > value, // gt
            5 => col_val >= value, // ge
            else => false,
        };

        if (matches) {
            out_indices[out_count] = @intCast(i);
            out_count += 1;
        }
    }

    return out_count;
}

/// Read int64 values at specific indices
export fn readInt64AtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]i64,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const max_idx = buf_size / 8;

    for (0..num_indices) |i| {
        const idx = indices[i];
        if (idx >= max_idx) {
            out_ptr[i] = 0;
        } else {
            out_ptr[i] = readI64LE(data, buf_start + idx * 8);
        }
    }

    return num_indices;
}

/// Read float64 values at specific indices
export fn readFloat64AtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]f64,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const max_idx = buf_size / 8;

    for (0..num_indices) |i| {
        const idx = indices[i];
        if (idx >= max_idx) {
            out_ptr[i] = 0;
        } else {
            out_ptr[i] = readF64LE(data, buf_start + idx * 8);
        }
    }

    return num_indices;
}

/// Allocate index buffer
export fn allocIndexBuffer(count: usize) ?[*]u32 {
    const ptr = wasmAlloc(count * 4) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

// ============================================================================
// Additional Numeric Type Column Reading
// ============================================================================

/// Read int32 column
export fn readInt32Column(col_idx: u32, out_ptr: [*]i32, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 4, max_len);
    for (0..count) |i| {
        out_ptr[i] = readI32LE(data, buf_start + i * 4);
    }
    return count;
}

/// Read int16 column
export fn readInt16Column(col_idx: u32, out_ptr: [*]i16, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 2, max_len);
    for (0..count) |i| {
        out_ptr[i] = readI16LE(data, buf_start + i * 2);
    }
    return count;
}

/// Read int8 column
export fn readInt8Column(col_idx: u32, out_ptr: [*]i8, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size, max_len);
    for (0..count) |i| {
        out_ptr[i] = readI8(data, buf_start + i);
    }
    return count;
}

/// Read uint64 column
export fn readUint64Column(col_idx: u32, out_ptr: [*]u64, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 8, max_len);
    for (0..count) |i| {
        out_ptr[i] = readU64LE(data, buf_start + i * 8);
    }
    return count;
}

/// Read uint32 column
export fn readUint32Column(col_idx: u32, out_ptr: [*]u32, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 4, max_len);
    for (0..count) |i| {
        out_ptr[i] = readU32LE(data, buf_start + i * 4);
    }
    return count;
}

/// Read uint16 column
export fn readUint16Column(col_idx: u32, out_ptr: [*]u16, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 2, max_len);
    for (0..count) |i| {
        out_ptr[i] = readU16LE(data, buf_start + i * 2);
    }
    return count;
}

/// Read uint8 column
export fn readUint8Column(col_idx: u32, out_ptr: [*]u8, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size, max_len);
    @memcpy(out_ptr[0..count], data[buf_start..][0..count]);
    return count;
}

/// Read float32 column
export fn readFloat32Column(col_idx: u32, out_ptr: [*]f32, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const count = @min(buf_size / 4, max_len);
    for (0..count) |i| {
        out_ptr[i] = readF32LE(data, buf_start + i * 4);
    }
    return count;
}

/// Read boolean column (stored as bit-packed in Lance)
export fn readBoolColumn(col_idx: u32, out_ptr: [*]u8, max_len: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    // Boolean values are bit-packed (8 values per byte)
    const num_bools: usize = @intCast(info.rows);
    const count = @min(num_bools, max_len);

    for (0..count) |i| {
        const byte_idx = i / 8;
        const bit_idx: u3 = @intCast(i % 8);
        if (byte_idx < buf_size) {
            const byte = data[buf_start + byte_idx];
            out_ptr[i] = if ((byte >> bit_idx) & 1 == 1) 1 else 0;
        } else {
            out_ptr[i] = 0;
        }
    }
    return count;
}

/// Allocate int32 buffer
export fn allocInt32Buffer(count: usize) ?[*]i32 {
    const ptr = wasmAlloc(count * 4) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Allocate int16 buffer
export fn allocInt16Buffer(count: usize) ?[*]i16 {
    const ptr = wasmAlloc(count * 2) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Allocate int8 buffer
export fn allocInt8Buffer(count: usize) ?[*]i8 {
    return @ptrCast(wasmAlloc(count));
}

/// Allocate uint64 buffer
export fn allocUint64Buffer(count: usize) ?[*]u64 {
    const ptr = wasmAlloc(count * 8) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Allocate uint16 buffer
export fn allocUint16Buffer(count: usize) ?[*]u16 {
    const ptr = wasmAlloc(count * 2) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Read int32 values at specific indices
export fn readInt32AtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]i32,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const max_idx = buf_size / 4;

    for (0..num_indices) |i| {
        const idx = indices[i];
        if (idx >= max_idx) {
            out_ptr[i] = 0;
        } else {
            out_ptr[i] = readI32LE(data, buf_start + idx * 4);
        }
    }

    return num_indices;
}

/// Read float32 values at specific indices
export fn readFloat32AtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]f32,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const max_idx = buf_size / 4;

    for (0..num_indices) |i| {
        const idx = indices[i];
        if (idx >= max_idx) {
            out_ptr[i] = 0;
        } else {
            out_ptr[i] = readF32LE(data, buf_start + idx * 4);
        }
    }

    return num_indices;
}

/// Read uint8 values at specific indices
export fn readUint8AtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]u8,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    for (0..num_indices) |i| {
        const idx = indices[i];
        if (idx >= buf_size) {
            out_ptr[i] = 0;
        } else {
            out_ptr[i] = data[buf_start + idx];
        }
    }

    return num_indices;
}

/// Read bool values at specific indices
export fn readBoolAtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]u8,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const num_bools: usize = @intCast(info.rows);

    for (0..num_indices) |i| {
        const idx = indices[i];
        if (idx >= num_bools) {
            out_ptr[i] = 0;
        } else {
            const byte_idx = idx / 8;
            const bit_idx: u3 = @intCast(idx % 8);
            if (byte_idx < buf_size) {
                const byte = data[buf_start + byte_idx];
                out_ptr[i] = if ((byte >> bit_idx) & 1 == 1) 1 else 0;
            } else {
                out_ptr[i] = 0;
            }
        }
    }

    return num_indices;
}

// ============================================================================
// Aggregation Functions
// ============================================================================

/// Sum int64 column
export fn sumInt64Column(col_idx: u32) i64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    var sum: i64 = 0;

    for (0..row_count) |i| {
        sum += readI64LE(data, buf_start + i * 8);
    }

    return sum;
}

/// Sum float64 column
export fn sumFloat64Column(col_idx: u32) f64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    var sum: f64 = 0;

    for (0..row_count) |i| {
        sum += readF64LE(data, buf_start + i * 8);
    }

    return sum;
}

/// Min int64 column
export fn minInt64Column(col_idx: u32) i64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    if (row_count == 0) return 0;

    var min_val: i64 = readI64LE(data, buf_start);
    for (1..row_count) |i| {
        const val = readI64LE(data, buf_start + i * 8);
        if (val < min_val) min_val = val;
    }

    return min_val;
}

/// Max int64 column
export fn maxInt64Column(col_idx: u32) i64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    if (row_count == 0) return 0;

    var max_val: i64 = readI64LE(data, buf_start);
    for (1..row_count) |i| {
        const val = readI64LE(data, buf_start + i * 8);
        if (val > max_val) max_val = val;
    }

    return max_val;
}

/// Average float64 column
export fn avgFloat64Column(col_idx: u32) f64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    const buf_start: usize = @intCast(info.offset);
    const buf_size: usize = @intCast(info.size);
    if (buf_start + buf_size > data.len) return 0;

    const row_count = buf_size / 8;
    if (row_count == 0) return 0;

    var sum: f64 = 0;
    for (0..row_count) |i| {
        sum += readF64LE(data, buf_start + i * 8);
    }

    return sum / @as(f64, @floatFromInt(row_count));
}

// ============================================================================
// String Column Support
// ============================================================================

/// Get string buffer info from column metadata (for variable-length data)
/// Lance stores strings with:
///   - buffer[0]: offsets (int32 or int64)
///   - buffer[1]: data (UTF-8 bytes)
fn getStringBufferInfo(col_meta: []const u8) struct {
    offsets_start: u64,
    offsets_size: u64,
    data_start: u64,
    data_size: u64,
    rows: u64,
} {
    var pos: usize = 0;
    var buffer_offsets: [2]u64 = .{ 0, 0 };
    var buffer_sizes: [2]u64 = .{ 0, 0 };
    var page_rows: u64 = 0;
    var buf_idx: usize = 0;

    while (pos < col_meta.len) {
        const tag = readVarint(col_meta, &pos);
        const field_num = tag >> 3;
        const wire_type: u3 = @truncate(tag);

        switch (field_num) {
            1 => { // encoding (length-delimited) - skip it
                if (wire_type == 2) {
                    const skip_len = readVarint(col_meta, &pos);
                    pos += @as(usize, @intCast(skip_len));
                }
            },
            2 => { // pages (length-delimited)
                if (wire_type != 2) break;
                const page_len = readVarint(col_meta, &pos);
                const page_end = pos + @as(usize, @intCast(page_len));

                // Parse page message
                while (pos < page_end and pos < col_meta.len) {
                    const page_tag = readVarint(col_meta, &pos);
                    const page_field = page_tag >> 3;
                    const page_wire: u3 = @truncate(page_tag);

                    switch (page_field) {
                        1 => { // buffer_offsets (packed repeated uint64)
                            if (page_wire == 2) {
                                const packed_len = readVarint(col_meta, &pos);
                                const packed_end = pos + @as(usize, @intCast(packed_len));
                                buf_idx = 0;
                                while (pos < packed_end and buf_idx < 2) {
                                    buffer_offsets[buf_idx] = readVarint(col_meta, &pos);
                                    buf_idx += 1;
                                }
                                pos = packed_end;
                            } else {
                                if (buf_idx < 2) {
                                    buffer_offsets[buf_idx] = readVarint(col_meta, &pos);
                                    buf_idx += 1;
                                }
                            }
                        },
                        2 => { // buffer_sizes (packed repeated uint64)
                            if (page_wire == 2) {
                                const packed_len = readVarint(col_meta, &pos);
                                const packed_end = pos + @as(usize, @intCast(packed_len));
                                buf_idx = 0;
                                while (pos < packed_end and buf_idx < 2) {
                                    buffer_sizes[buf_idx] = readVarint(col_meta, &pos);
                                    buf_idx += 1;
                                }
                                pos = packed_end;
                            } else {
                                if (buf_idx < 2) {
                                    buffer_sizes[buf_idx] = readVarint(col_meta, &pos);
                                    buf_idx += 1;
                                }
                            }
                        },
                        3 => { // length (rows)
                            page_rows = readVarint(col_meta, &pos);
                        },
                        else => {
                            if (page_wire == 0) {
                                _ = readVarint(col_meta, &pos);
                            } else if (page_wire == 2) {
                                const skip_len = readVarint(col_meta, &pos);
                                pos += @as(usize, @intCast(skip_len));
                            } else if (page_wire == 5) {
                                pos += 4;
                            } else if (page_wire == 1) {
                                pos += 8;
                            }
                        },
                    }
                }
                return .{
                    .offsets_start = buffer_offsets[0],
                    .offsets_size = buffer_sizes[0],
                    .data_start = buffer_offsets[1],
                    .data_size = buffer_sizes[1],
                    .rows = page_rows,
                };
            },
            else => {
                if (wire_type == 0) {
                    _ = readVarint(col_meta, &pos);
                } else if (wire_type == 2) {
                    const skip_len = readVarint(col_meta, &pos);
                    pos += @as(usize, @intCast(skip_len));
                } else if (wire_type == 5) {
                    pos += 4;
                } else if (wire_type == 1) {
                    pos += 8;
                }
            },
        }
    }

    return .{
        .offsets_start = 0,
        .offsets_size = 0,
        .data_start = 0,
        .data_size = 0,
        .rows = 0,
    };
}

/// Debug: Get string column buffer info
/// Returns packed: high32=offsets_size, low32=data_size (both 0 if not a string column)
export fn debugStringColInfo(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getStringBufferInfo(col_meta);

    // Return packed: high 32 bits = offsets_size, low 32 bits = data_size
    return (info.offsets_size << 32) | (info.data_size & 0xFFFFFFFF);
}

/// Get number of strings in column
/// Returns 0 if not a string column (string columns have 2 buffers: offsets + data)
export fn getStringCount(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getStringBufferInfo(col_meta);

    // String columns have 2 buffers (offsets + data), non-string columns have 1
    // If data_size is 0, this is not a string column
    if (info.data_size == 0) return 0;

    return info.rows;
}

/// Debug: Get detailed string read info for a specific row
/// Returns packed debug info for troubleshooting
export fn debugReadStringInfo(col_idx: u32, row_idx: u32) u64 {
    const data = file_data orelse return 0xDEAD0001; // No file data
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0xDEAD0002; // No column entry

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0xDEAD0003; // Col meta out of bounds

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getStringBufferInfo(col_meta);

    if (info.offsets_size == 0 or info.data_size == 0) return 0xDEAD0004; // Not a string column
    if (row_idx >= info.rows) return 0xDEAD0005; // Row out of bounds

    const offset_size = info.offsets_size / info.rows;
    if (offset_size != 4 and offset_size != 8) return 0xDEAD0006; // Invalid offset size

    const offsets_start: usize = @intCast(info.offsets_start);
    _ = info.data_start; // Used in actual read

    var str_start: usize = 0;
    var str_end: usize = 0;

    if (offset_size == 4) {
        str_end = readU32LE(data, offsets_start + row_idx * 4);
        if (row_idx > 0) {
            str_start = readU32LE(data, offsets_start + (row_idx - 1) * 4);
        }
    } else {
        str_end = @intCast(readU64LE(data, offsets_start + row_idx * 8));
        if (row_idx > 0) {
            str_start = @intCast(readU64LE(data, offsets_start + (row_idx - 1) * 8));
        }
    }

    // Return: high 32 = str_start, low 32 = str_len
    const str_len = if (str_end >= str_start) str_end - str_start else 0;
    return (@as(u64, @intCast(str_start)) << 32) | @as(u64, @intCast(str_len));
}

/// Debug: Get data_start position for string column
export fn debugStringDataStart(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getStringBufferInfo(col_meta);

    // Return data_start and file length in packed format for debug
    // High 32 = data_start, low 32 = file_len (capped)
    const ds: u32 = @intCast(@min(info.data_start, 0xFFFFFFFF));
    const fl: u32 = @intCast(@min(data.len, 0xFFFFFFFF));
    return (@as(u64, ds) << 32) | @as(u64, fl);
}

/// Read a single string at index into output buffer
/// Returns actual string length (may exceed out_max if truncated)
export fn readStringAt(col_idx: u32, row_idx: u32, out_ptr: [*]u8, out_max: usize) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getStringBufferInfo(col_meta);

    if (info.offsets_size == 0 or info.data_size == 0) return 0;
    if (row_idx >= info.rows) return 0;

    const offsets_start: usize = @intCast(info.offsets_start);
    const data_start: usize = @intCast(info.data_start);

    // Lance v2 uses N offsets for N strings (end positions, not N+1 start/end pairs)
    // Check if using 32-bit or 64-bit offsets: offsets_size / rows
    const offset_size = info.offsets_size / info.rows;
    if (offset_size != 4 and offset_size != 8) return 0;

    var str_start: usize = 0;
    var str_end: usize = 0;

    if (offset_size == 4) {
        // 32-bit offsets - each offset is the END position of that string
        str_end = readU32LE(data, offsets_start + row_idx * 4);
        if (row_idx > 0) {
            str_start = readU32LE(data, offsets_start + (row_idx - 1) * 4);
        }
    } else {
        // 64-bit offsets
        str_end = @intCast(readU64LE(data, offsets_start + row_idx * 8));
        if (row_idx > 0) {
            str_start = @intCast(readU64LE(data, offsets_start + (row_idx - 1) * 8));
        }
    }

    if (str_end < str_start) return 0;
    const str_len = str_end - str_start;

    // Check bounds
    if (data_start + str_end > data.len) return 0;

    // Copy string to output buffer
    const copy_len = @min(str_len, out_max);
    const str_data = data[data_start + str_start ..][0..copy_len];
    @memcpy(out_ptr[0..copy_len], str_data);

    return str_len;
}

/// Read multiple strings at indices
/// Returns total bytes written to out_ptr
/// out_lengths receives the length of each string
export fn readStringsAtIndices(
    col_idx: u32,
    indices: [*]const u32,
    num_indices: usize,
    out_ptr: [*]u8,
    out_max: usize,
    out_lengths: [*]u32,
) usize {
    var total_written: usize = 0;

    for (0..num_indices) |i| {
        const remaining = if (total_written < out_max) out_max - total_written else 0;
        const len = readStringAt(col_idx, indices[i], out_ptr + total_written, remaining);
        out_lengths[i] = @intCast(len);
        total_written += @min(len, remaining);
    }

    return total_written;
}

/// Allocate string buffer
export fn allocStringBuffer(size: usize) ?[*]u8 {
    return wasmAlloc(size);
}

/// Allocate u32 buffer for lengths
export fn allocU32Buffer(count: usize) ?[*]u32 {
    const ptr = wasmAlloc(count * 4) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

// ============================================================================
// Vector Column Support (Fixed-size float arrays for embeddings)
// ============================================================================

/// Get vector info from column: dimension and count
/// Vectors are stored as fixed-size arrays of float32
export fn getVectorInfo(col_idx: u32) u64 {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    // Return packed: high 32 bits = rows, low 32 bits = estimated dimension
    // Dimension = buffer_size / (rows * 4) for float32
    if (info.rows == 0) return 0;
    const dim = info.size / (info.rows * 4);
    return (info.rows << 32) | dim;
}

/// Read a single vector at index
/// Returns number of floats written
export fn readVectorAt(
    col_idx: u32,
    row_idx: u32,
    out_ptr: [*]f32,
    max_dim: usize,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    if (info.rows == 0) return 0;
    if (row_idx >= info.rows) return 0;

    const dim: usize = @intCast(info.size / (info.rows * 4));
    if (dim == 0) return 0;

    const buf_start: usize = @intCast(info.offset);
    const vec_start = buf_start + @as(usize, row_idx) * dim * 4;

    const actual_dim = @min(dim, max_dim);
    for (0..actual_dim) |i| {
        out_ptr[i] = readF32LE(data, vec_start + i * 4);
    }

    return actual_dim;
}

/// Allocate float32 buffer for vectors
export fn allocFloat32Buffer(count: usize) ?[*]f32 {
    const ptr = wasmAlloc(count * 4) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

/// Compute cosine similarity between two vectors
/// Returns similarity score (-1 to 1, higher is more similar)
export fn cosineSimilarity(
    vec_a: [*]const f32,
    vec_b: [*]const f32,
    dim: usize,
) f32 {
    var dot: f32 = 0;
    var norm_a: f32 = 0;
    var norm_b: f32 = 0;

    for (0..dim) |i| {
        const a = vec_a[i];
        const b = vec_b[i];
        dot += a * b;
        norm_a += a * a;
        norm_b += b * b;
    }

    const denom = @sqrt(norm_a) * @sqrt(norm_b);
    if (denom == 0) return 0;
    return dot / denom;
}

// ============================================================================
// SIMD-Optimized Vector Operations
// ============================================================================

const Vec4 = @Vector(4, f32);

/// SIMD dot product for f32 vectors (4-wide)
fn simdDotProduct(a_ptr: [*]const f32, b_ptr: [*]const f32, dim: usize) f32 {
    var sum: Vec4 = @splat(0);
    var i: usize = 0;

    // Process 4 elements at a time
    while (i + 4 <= dim) : (i += 4) {
        const va: Vec4 = .{ a_ptr[i], a_ptr[i + 1], a_ptr[i + 2], a_ptr[i + 3] };
        const vb: Vec4 = .{ b_ptr[i], b_ptr[i + 1], b_ptr[i + 2], b_ptr[i + 3] };
        sum += va * vb;
    }

    // Horizontal sum
    var result = @reduce(.Add, sum);

    // Handle remainder
    while (i < dim) : (i += 1) {
        result += a_ptr[i] * b_ptr[i];
    }

    return result;
}

/// SIMD L2 norm squared
fn simdNormSquared(ptr: [*]const f32, dim: usize) f32 {
    var sum: Vec4 = @splat(0);
    var i: usize = 0;

    while (i + 4 <= dim) : (i += 4) {
        const v: Vec4 = .{ ptr[i], ptr[i + 1], ptr[i + 2], ptr[i + 3] };
        sum += v * v;
    }

    var result = @reduce(.Add, sum);

    while (i < dim) : (i += 1) {
        result += ptr[i] * ptr[i];
    }

    return result;
}

/// SIMD cosine similarity for pre-normalized vectors (just dot product)
export fn simdCosineSimilarityNormalized(
    vec_a: [*]const f32,
    vec_b: [*]const f32,
    dim: usize,
) f32 {
    return simdDotProduct(vec_a, vec_b, dim);
}

/// SIMD cosine similarity for un-normalized vectors
export fn simdCosineSimilarity(
    vec_a: [*]const f32,
    vec_b: [*]const f32,
    dim: usize,
) f32 {
    const dot = simdDotProduct(vec_a, vec_b, dim);
    const norm_a = @sqrt(simdNormSquared(vec_a, dim));
    const norm_b = @sqrt(simdNormSquared(vec_b, dim));
    const denom = norm_a * norm_b;
    if (denom == 0) return 0;
    return dot / denom;
}

/// Batch compute similarities between query and multiple vectors
/// Much faster than calling simdCosineSimilarity in a loop
/// vectors_ptr: flattened array of [num_vectors * dim] f32
/// out_scores: array of [num_vectors] f32
export fn batchCosineSimilarity(
    query_ptr: [*]const f32,
    vectors_ptr: [*]const f32,
    dim: usize,
    num_vectors: usize,
    out_scores: [*]f32,
    normalized: u32,
) void {
    // Pre-compute query norm if not normalized
    const query_norm = if (normalized == 0) @sqrt(simdNormSquared(query_ptr, dim)) else 1.0;

    for (0..num_vectors) |i| {
        const vec_ptr = vectors_ptr + i * dim;
        const dot = simdDotProduct(query_ptr, vec_ptr, dim);

        if (normalized != 0) {
            // Vectors are L2-normalized, dot product = cosine similarity
            out_scores[i] = dot;
        } else {
            const vec_norm = @sqrt(simdNormSquared(vec_ptr, dim));
            const denom = query_norm * vec_norm;
            out_scores[i] = if (denom == 0) 0 else dot / denom;
        }
    }
}

/// Find top-k from pre-computed scores
/// Uses partial selection for better performance than full sort
fn findTopK(
    scores: [*]const f32,
    num_scores: usize,
    top_k: usize,
    out_indices: [*]u32,
    out_scores: [*]f32,
) usize {
    const actual_k = @min(top_k, num_scores);

    // Initialize with worst scores
    for (0..actual_k) |i| {
        out_indices[i] = 0;
        out_scores[i] = -2.0;
    }

    // Simple insertion sort into top-k (good for small k)
    for (0..num_scores) |i| {
        const score = scores[i];

        if (score > out_scores[actual_k - 1]) {
            // Find insertion point
            var insert_pos: usize = actual_k - 1;
            while (insert_pos > 0 and score > out_scores[insert_pos - 1]) {
                insert_pos -= 1;
            }

            // Shift elements down
            var j: usize = actual_k - 1;
            while (j > insert_pos) {
                out_indices[j] = out_indices[j - 1];
                out_scores[j] = out_scores[j - 1];
                j -= 1;
            }

            // Insert
            out_indices[insert_pos] = @intCast(i);
            out_scores[insert_pos] = score;
        }
    }

    return actual_k;
}

/// Find top-k most similar vectors to query (SIMD optimized)
/// Returns number of results written
/// out_indices: row indices of top matches
/// out_scores: similarity scores
export fn vectorSearchTopK(
    col_idx: u32,
    query_ptr: [*]const f32,
    query_dim: usize,
    top_k: usize,
    out_indices: [*]u32,
    out_scores: [*]f32,
) usize {
    const data = file_data orelse return 0;
    const entry = getColumnOffsetEntry(col_idx);
    if (entry.len == 0) return 0;

    const col_meta_start: usize = @intCast(entry.pos);
    const col_meta_len: usize = @intCast(entry.len);
    if (col_meta_start + col_meta_len > data.len) return 0;

    const col_meta = data[col_meta_start..][0..col_meta_len];
    const info = getPageBufferInfo(col_meta);

    if (info.rows == 0) return 0;

    const dim: usize = @intCast(info.size / (info.rows * 4));
    if (dim != query_dim) return 0;

    const buf_start: usize = @intCast(info.offset);
    const num_rows: usize = @intCast(info.rows);
    const actual_k = @min(top_k, num_rows);

    // Initialize with worst scores
    for (0..actual_k) |i| {
        out_indices[i] = 0;
        out_scores[i] = -2.0;
    }

    // Pre-compute query norm (assume vectors may not be normalized)
    const query_norm = @sqrt(simdNormSquared(query_ptr, query_dim));

    // Scan all vectors using SIMD
    for (0..num_rows) |row| {
        const vec_start = buf_start + row * dim * 4;

        // Get pointer to vector data (may be unaligned)
        const vec_ptr: [*]const f32 = @ptrCast(@alignCast(data.ptr + vec_start));

        // SIMD dot product
        const dot = simdDotProduct(query_ptr, vec_ptr, dim);
        const vec_norm = @sqrt(simdNormSquared(vec_ptr, dim));
        const denom = query_norm * vec_norm;
        const score: f32 = if (denom == 0) 0 else dot / denom;

        // Insert into top-k if better than worst
        if (score > out_scores[actual_k - 1]) {
            var insert_pos: usize = actual_k - 1;
            while (insert_pos > 0 and score > out_scores[insert_pos - 1]) {
                insert_pos -= 1;
            }

            var j: usize = actual_k - 1;
            while (j > insert_pos) {
                out_indices[j] = out_indices[j - 1];
                out_scores[j] = out_scores[j - 1];
                j -= 1;
            }

            out_indices[insert_pos] = @intCast(row);
            out_scores[insert_pos] = score;
        }
    }

    return actual_k;
}

/// Vector search on raw buffer (for worker-based processing)
/// Searches vectors directly from a provided buffer, not from file_data
/// normalized: 1 if vectors are L2-normalized (skip norm computation)
export fn vectorSearchBuffer(
    vectors_ptr: [*]const f32,
    num_vectors: usize,
    dim: usize,
    query_ptr: [*]const f32,
    top_k: usize,
    out_indices: [*]u32,
    out_scores: [*]f32,
    normalized: u32,
    start_index: u32,
) usize {
    const actual_k = @min(top_k, num_vectors);

    // Initialize with worst scores
    for (0..actual_k) |i| {
        out_indices[i] = 0;
        out_scores[i] = -2.0;
    }

    // Pre-compute query norm if not normalized
    const query_norm = if (normalized == 0) @sqrt(simdNormSquared(query_ptr, dim)) else 1.0;

    // Scan all vectors using SIMD
    for (0..num_vectors) |row| {
        const vec_ptr = vectors_ptr + row * dim;

        const dot = simdDotProduct(query_ptr, vec_ptr, dim);

        var score: f32 = undefined;
        if (normalized != 0) {
            // For L2-normalized vectors, dot product = cosine similarity
            score = dot;
        } else {
            const vec_norm = @sqrt(simdNormSquared(vec_ptr, dim));
            const denom = query_norm * vec_norm;
            score = if (denom == 0) 0 else dot / denom;
        }

        // Insert into top-k if better than worst
        if (score > out_scores[actual_k - 1]) {
            var insert_pos: usize = actual_k - 1;
            while (insert_pos > 0 and score > out_scores[insert_pos - 1]) {
                insert_pos -= 1;
            }

            var j: usize = actual_k - 1;
            while (j > insert_pos) {
                out_indices[j] = out_indices[j - 1];
                out_scores[j] = out_scores[j - 1];
                j -= 1;
            }

            // Store global index (start_index + local row)
            out_indices[insert_pos] = start_index + @as(u32, @intCast(row));
            out_scores[insert_pos] = score;
        }
    }

    return actual_k;
}

/// Merge multiple top-k results into final top-k
/// Used by main thread to combine results from workers
export fn mergeTopK(
    indices_arrays: [*]const [*]const u32,
    scores_arrays: [*]const [*]const f32,
    num_arrays: usize,
    k_per_array: usize,
    final_k: usize,
    out_indices: [*]u32,
    out_scores: [*]f32,
) usize {
    const actual_k = @min(final_k, num_arrays * k_per_array);

    // Initialize
    for (0..actual_k) |i| {
        out_indices[i] = 0;
        out_scores[i] = -2.0;
    }

    // Merge all results
    for (0..num_arrays) |arr_idx| {
        const indices = indices_arrays[arr_idx];
        const scores = scores_arrays[arr_idx];

        for (0..k_per_array) |i| {
            const score = scores[i];
            if (score <= -2.0) continue; // Skip invalid

            if (score > out_scores[actual_k - 1]) {
                var insert_pos: usize = actual_k - 1;
                while (insert_pos > 0 and score > out_scores[insert_pos - 1]) {
                    insert_pos -= 1;
                }

                var j: usize = actual_k - 1;
                while (j > insert_pos) {
                    out_indices[j] = out_indices[j - 1];
                    out_scores[j] = out_scores[j - 1];
                    j -= 1;
                }

                out_indices[insert_pos] = indices[i];
                out_scores[insert_pos] = score;
            }
        }
    }

    return actual_k;
}

// ============================================================================
// CLIP Text Encoder
// ============================================================================

// CLIP model constants (ViT-B/32)
const CLIP_VOCAB_SIZE: usize = 49408;
const CLIP_MAX_SEQ_LEN: usize = 77;
const CLIP_EMBED_DIM: usize = 512;
const CLIP_NUM_HEADS: usize = 8;
const CLIP_NUM_LAYERS: usize = 12;
const CLIP_MLP_DIM: usize = 2048;
const CLIP_HEAD_DIM: usize = CLIP_EMBED_DIM / CLIP_NUM_HEADS; // 64

// SIMD width for vectorized operations (WASM SIMD 128-bit = 4x f32)
const SIMD_WIDTH: usize = 4;

// Comptime assertions for SIMD alignment
comptime {
    if (CLIP_EMBED_DIM % SIMD_WIDTH != 0) @compileError("CLIP_EMBED_DIM must be divisible by SIMD_WIDTH");
    if (CLIP_HEAD_DIM % SIMD_WIDTH != 0) @compileError("CLIP_HEAD_DIM must be divisible by SIMD_WIDTH");
    if (CLIP_MLP_DIM % SIMD_WIDTH != 0) @compileError("CLIP_MLP_DIM must be divisible by SIMD_WIDTH");
}

// CLIP state
var clip_initialized: bool = false;
var clip_model_loaded: bool = false;

// Buffers for CLIP
var clip_text_buffer: [1024]u8 = undefined;
var clip_output_buffer: [CLIP_EMBED_DIM]f32 = undefined;

// Model weights storage (allocated from model buffer)
var clip_model_buffer: ?[*]u8 = null;
var clip_model_size: usize = 0;

// Weight tensor indices (set after model load)
var token_embedding_idx: ?usize = null;
var position_embedding_idx: ?usize = null;
var ln_final_weight_idx: ?usize = null;
var ln_final_bias_idx: ?usize = null;
var text_projection_idx: ?usize = null;

// Per-layer weight indices (12 layers)
var layer_ln1_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_ln1_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_q_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_q_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_k_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_k_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_v_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_v_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_out_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_attn_out_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_ln2_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_ln2_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_mlp_fc1_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_mlp_fc1_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_mlp_fc2_weight_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;
var layer_mlp_fc2_bias_idx: [CLIP_NUM_LAYERS]?usize = [_]?usize{null} ** CLIP_NUM_LAYERS;

// Tokenizer vocab (simplified - just store raw tokens)
var vocab_tokens: ?[*]const u8 = null;
var vocab_offsets: ?[*]const u32 = null;
var vocab_count: usize = 0;

// Scratch buffers for inference (statically allocated)
var scratch_hidden: [CLIP_MAX_SEQ_LEN * CLIP_EMBED_DIM]f32 = undefined;
var scratch_q: [CLIP_MAX_SEQ_LEN * CLIP_EMBED_DIM]f32 = undefined;
var scratch_k: [CLIP_MAX_SEQ_LEN * CLIP_EMBED_DIM]f32 = undefined;
var scratch_v: [CLIP_MAX_SEQ_LEN * CLIP_EMBED_DIM]f32 = undefined;
var scratch_attn: [CLIP_NUM_HEADS * CLIP_MAX_SEQ_LEN * CLIP_MAX_SEQ_LEN]f32 = undefined;
var scratch_mlp: [CLIP_MAX_SEQ_LEN * CLIP_MLP_DIM]f32 = undefined;
var scratch_ln: [CLIP_MAX_SEQ_LEN * CLIP_EMBED_DIM]f32 = undefined;

/// Initialize CLIP module
export fn clip_init() i32 {
    clip_initialized = true;
    clip_model_loaded = false;

    // Clear output buffer
    for (&clip_output_buffer) |*v| {
        v.* = 0;
    }

    return 0;
}

/// Get pointer to text input buffer
export fn clip_get_text_buffer() [*]u8 {
    return &clip_text_buffer;
}

/// Get size of text input buffer
export fn clip_get_text_buffer_size() usize {
    return clip_text_buffer.len;
}

/// Get pointer to output embedding buffer
export fn clip_get_output_buffer() [*]f32 {
    return &clip_output_buffer;
}

/// Get output embedding dimension
export fn clip_get_output_dim() usize {
    return CLIP_EMBED_DIM;
}

/// Allocate buffer for model weights using WASM memory growth
export fn clip_alloc_model_buffer(size: usize) usize {
    // For large allocations like CLIP model (100MB+), grow WASM memory directly
    // WASM pages are 64KB each
    const page_size: usize = 65536;
    const pages_needed = (size + page_size - 1) / page_size;

    // Get current memory size in pages
    const current_pages = @wasmMemorySize(0);
    const current_size = current_pages * page_size;

    // Try to grow memory
    const result = @wasmMemoryGrow(0, pages_needed);
    if (result == @as(usize, @bitCast(@as(isize, -1)))) {
        // Growth failed
        return 0;
    }

    // The new memory starts at the old end
    const ptr: [*]u8 = @ptrFromInt(current_size);
    clip_model_buffer = ptr;
    clip_model_size = size;
    return current_size;
}

/// Check if model weights are loaded
export fn clip_weights_loaded() i32 {
    return if (clip_model_loaded) 1 else 0;
}

// GGUF parsing helpers
const GGUF_TYPE_STRING: u32 = 8;
const GGUF_TYPE_ARRAY: u32 = 9;
const GGUF_TYPE_UINT32: u32 = 4;
const GGUF_TYPE_FLOAT32: u32 = 6;
const GGUF_TYPE_BOOL: u32 = 7;
const GGUF_TYPE_UINT64: u32 = 10;

const GGML_TYPE_F32: u32 = 0;
const GGML_TYPE_F16: u32 = 1;

// Tensor info storage
const MAX_TENSORS: usize = 256;
var tensor_names: [MAX_TENSORS][64]u8 = undefined;
var tensor_name_lens: [MAX_TENSORS]usize = undefined;
var tensor_offsets: [MAX_TENSORS]u64 = undefined;
var tensor_types: [MAX_TENSORS]u32 = undefined;
var tensor_dims: [MAX_TENSORS][4]u64 = undefined;
var tensor_n_dims: [MAX_TENSORS]u32 = undefined;
var n_tensors_loaded: usize = 0;
var gguf_data_offset: usize = 0;

// Tokenizer storage
var vocab_data: ?[*]const u8 = null;
var vocab_string_offsets: [CLIP_VOCAB_SIZE + 1]u32 = undefined;

fn ggufReadString(data: []const u8, pos: *usize) []const u8 {
    if (pos.* + 8 > data.len) return "";
    const len: usize = @intCast(readU64LE(data, pos.*));
    pos.* += 8;
    if (pos.* + len > data.len) return "";
    const str = data[pos.* .. pos.* + len];
    pos.* += len;
    return str;
}

fn ggufSkipValue(data: []const u8, pos: *usize, vtype: u32) void {
    switch (vtype) {
        GGUF_TYPE_STRING => {
            _ = ggufReadString(data, pos);
        },
        GGUF_TYPE_UINT32, GGUF_TYPE_FLOAT32 => {
            pos.* += 4;
        },
        GGUF_TYPE_BOOL => {
            pos.* += 1;
        },
        GGUF_TYPE_UINT64 => {
            pos.* += 8;
        },
        GGUF_TYPE_ARRAY => {
            if (pos.* + 12 > data.len) return;
            const atype = readU32LE(data, pos.*);
            pos.* += 4;
            const alen: usize = @intCast(readU64LE(data, pos.*));
            pos.* += 8;
            for (0..alen) |_| {
                ggufSkipValue(data, pos, atype);
            }
        },
        else => {},
    }
}

fn strEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

fn findTensor(name: []const u8) ?usize {
    for (0..n_tensors_loaded) |i| {
        if (strEql(tensor_names[i][0..tensor_name_lens[i]], name)) {
            return i;
        }
    }
    return null;
}

fn getTensorF32Ptr(idx: usize) ?[*]const f32 {
    const model_data = clip_model_buffer orelse return null;
    const offset: usize = gguf_data_offset + @as(usize, @intCast(tensor_offsets[idx]));

    if (tensor_types[idx] == GGML_TYPE_F32) {
        return @ptrCast(@alignCast(model_data + offset));
    }
    return null;
}

fn getTensorF16Ptr(idx: usize) ?[*]const u16 {
    const model_data = clip_model_buffer orelse return null;
    const offset: usize = gguf_data_offset + @as(usize, @intCast(tensor_offsets[idx]));

    if (tensor_types[idx] == GGML_TYPE_F16) {
        return @ptrCast(@alignCast(model_data + offset));
    }
    return null;
}

fn getTensorPtr(idx: usize) ?[*]const u8 {
    const model_data = clip_model_buffer orelse return null;
    const offset: usize = gguf_data_offset + @as(usize, @intCast(tensor_offsets[idx]));
    return model_data + offset;
}

// Read a single weight value, handling F16 conversion
fn readWeight(idx: usize, i: usize) f32 {
    const model_data = clip_model_buffer orelse return 0;
    const offset: usize = gguf_data_offset + @as(usize, @intCast(tensor_offsets[idx]));

    if (tensor_types[idx] == GGML_TYPE_F16) {
        const ptr: [*]const u16 = @ptrCast(@alignCast(model_data + offset));
        return f16ToF32(ptr[i]);
    } else {
        const ptr: [*]const f32 = @ptrCast(@alignCast(model_data + offset));
        return ptr[i];
    }
}

// SIMD dot product of two slices (must be multiple of 4)
inline fn simdDot(comptime N: usize, a: *const [N]f32, b: *const [N]f32) f32 {
    comptime {
        if (N % SIMD_WIDTH != 0) @compileError("N must be divisible by SIMD_WIDTH");
    }
    var acc: Vec4 = @splat(0);
    inline for (0..N / SIMD_WIDTH) |i| {
        const va: Vec4 = a[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
        const vb: Vec4 = b[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
        acc += va * vb;
    }
    return @reduce(.Add, acc);
}

// SIMD vector add: dst += src
inline fn simdAdd(comptime N: usize, dst: *[N]f32, src: *const [N]f32) void {
    comptime {
        if (N % SIMD_WIDTH != 0) @compileError("N must be divisible by SIMD_WIDTH");
    }
    inline for (0..N / SIMD_WIDTH) |i| {
        const vd: Vec4 = dst[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
        const vs: Vec4 = src[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
        dst[i * SIMD_WIDTH ..][0..SIMD_WIDTH].* = vd + vs;
    }
}

// SIMD scalar multiply and add: dst += scalar * src
inline fn simdScalarMulAdd(comptime N: usize, dst: *[N]f32, scalar: f32, src: *const [N]f32) void {
    comptime {
        if (N % SIMD_WIDTH != 0) @compileError("N must be divisible by SIMD_WIDTH");
    }
    const vs: Vec4 = @splat(scalar);
    inline for (0..N / SIMD_WIDTH) |i| {
        const vd: Vec4 = dst[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
        const vsrc: Vec4 = src[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
        dst[i * SIMD_WIDTH ..][0..SIMD_WIDTH].* = vd + vs * vsrc;
    }
}

// SIMD zero array
inline fn simdZero(comptime N: usize, dst: *[N]f32) void {
    comptime {
        if (N % SIMD_WIDTH != 0) @compileError("N must be divisible by SIMD_WIDTH");
    }
    const zero: Vec4 = @splat(0);
    inline for (0..N / SIMD_WIDTH) |i| {
        dst[i * SIMD_WIDTH ..][0..SIMD_WIDTH].* = zero;
    }
}

// SIMD copy
inline fn simdCopy(comptime N: usize, dst: *[N]f32, src: *const [N]f32) void {
    comptime {
        if (N % SIMD_WIDTH != 0) @compileError("N must be divisible by SIMD_WIDTH");
    }
    inline for (0..N / SIMD_WIDTH) |i| {
        dst[i * SIMD_WIDTH ..][0..SIMD_WIDTH].* = src[i * SIMD_WIDTH ..][0..SIMD_WIDTH].*;
    }
}

// Batch read weights into buffer (for SIMD operations)
// Returns pointer to start of row in weight matrix
fn getWeightRowF32(idx: usize, row: usize, row_len: usize, buf: []f32) void {
    const model_data = clip_model_buffer orelse return;
    const offset: usize = gguf_data_offset + @as(usize, @intCast(tensor_offsets[idx]));
    const row_offset = row * row_len;

    if (tensor_types[idx] == GGML_TYPE_F16) {
        const ptr: [*]const u16 = @ptrCast(@alignCast(model_data + offset));
        // Convert F16 row to F32 using SIMD
        var i: usize = 0;
        while (i + 4 <= row_len) : (i += 4) {
            buf[i] = f16ToF32(ptr[row_offset + i]);
            buf[i + 1] = f16ToF32(ptr[row_offset + i + 1]);
            buf[i + 2] = f16ToF32(ptr[row_offset + i + 2]);
            buf[i + 3] = f16ToF32(ptr[row_offset + i + 3]);
        }
        while (i < row_len) : (i += 1) {
            buf[i] = f16ToF32(ptr[row_offset + i]);
        }
    } else {
        const ptr: [*]const f32 = @ptrCast(@alignCast(model_data + offset));
        @memcpy(buf[0..row_len], ptr[row_offset .. row_offset + row_len]);
    }
}

// Linear layer with SIMD: out = in @ W^T + b
// W is [out_dim, in_dim], stored row-major
fn linearLayerSimd(
    comptime in_dim: usize,
    comptime out_dim: usize,
    input: *const [in_dim]f32,
    w_idx: usize,
    b_idx: usize,
    output: *[out_dim]f32,
    weight_buf: *[in_dim]f32,
) void {
    for (0..out_dim) |i| {
        // Load weight row i into buffer
        getWeightRowF32(w_idx, i, in_dim, weight_buf);
        // SIMD dot product
        output[i] = readWeight(b_idx, i) + simdDot(in_dim, input, weight_buf);
    }
}

fn getTensorF16AsF32(idx: usize, out: []f32) bool {
    const model_data = clip_model_buffer orelse return false;
    const offset: usize = gguf_data_offset + @as(usize, @intCast(tensor_offsets[idx]));

    if (tensor_types[idx] != GGML_TYPE_F16) return false;

    // Calculate total elements
    var total: usize = 1;
    for (0..tensor_n_dims[idx]) |d| {
        total *= @intCast(tensor_dims[idx][d]);
    }

    if (total > out.len) return false;

    // Convert F16 to F32
    const f16_ptr: [*]const u16 = @ptrCast(@alignCast(model_data + offset));
    for (0..total) |i| {
        out[i] = f16ToF32(f16_ptr[i]);
    }
    return true;
}

fn f16ToF32(h: u16) f32 {
    const sign: u32 = @as(u32, h >> 15) << 31;
    const exp: u32 = (h >> 10) & 0x1F;
    const mant: u32 = h & 0x3FF;

    if (exp == 0) {
        if (mant == 0) {
            return @bitCast(sign);
        }
        // Subnormal
        var e: u32 = 0;
        var m = mant;
        while ((m & 0x400) == 0) {
            m <<= 1;
            e += 1;
        }
        const new_exp = (127 - 15 - e) << 23;
        const new_mant = (m & 0x3FF) << 13;
        return @bitCast(sign | new_exp | new_mant);
    } else if (exp == 31) {
        // Inf/NaN
        return @bitCast(sign | 0x7F800000 | (mant << 13));
    }

    const new_exp = (exp + 127 - 15) << 23;
    const new_mant = mant << 13;
    return @bitCast(sign | new_exp | new_mant);
}

/// Load GGUF model from buffer
export fn clip_load_model(size: usize) i32 {
    const model_data = clip_model_buffer orelse return -1;
    if (size < 128) return -2;

    const data = model_data[0..size];

    // Check GGUF magic
    if (data[0] != 'G' or data[1] != 'G' or data[2] != 'U' or data[3] != 'F') {
        return -3;
    }

    // GGUF version
    const version = readU32LE(data, 4);
    if (version < 2 or version > 3) {
        return -4;
    }

    // Number of tensors and metadata KV pairs
    const n_tensors: usize = @intCast(readU64LE(data, 8));
    const n_kv: usize = @intCast(readU64LE(data, 16));

    var pos: usize = 24;

    // Parse KV pairs to find tokenizer
    for (0..n_kv) |_| {
        const key = ggufReadString(data, &pos);
        if (pos + 4 > data.len) return -5;
        const vtype = readU32LE(data, pos);
        pos += 4;

        if (strEql(key, "tokenizer.ggml.tokens")) {
            // This is the vocab array
            if (vtype != GGUF_TYPE_ARRAY) {
                ggufSkipValue(data, &pos, vtype);
                continue;
            }
            if (pos + 12 > data.len) return -6;
            const atype = readU32LE(data, pos);
            pos += 4;
            const alen: usize = @intCast(readU64LE(data, pos));
            pos += 8;

            if (atype == GGUF_TYPE_STRING and alen <= CLIP_VOCAB_SIZE) {
                vocab_data = data.ptr + pos;
                vocab_count = alen;

                // Build string offset table
                var str_pos: u32 = 0;
                for (0..alen) |i| {
                    vocab_string_offsets[i] = str_pos;
                    const slen: u32 = @intCast(readU64LE(data, pos));
                    pos += 8;
                    str_pos += slen + 8; // Include length prefix
                    pos += slen;
                }
                vocab_string_offsets[alen] = str_pos;
            } else {
                ggufSkipValue(data, &pos, vtype);
            }
        } else {
            ggufSkipValue(data, &pos, vtype);
        }
    }

    // Parse tensor info
    n_tensors_loaded = @min(n_tensors, MAX_TENSORS);
    for (0..n_tensors_loaded) |i| {
        const name = ggufReadString(data, &pos);
        const name_len = @min(name.len, 63);
        @memcpy(tensor_names[i][0..name_len], name[0..name_len]);
        tensor_name_lens[i] = name_len;

        if (pos + 4 > data.len) return -7;
        const n_dims = readU32LE(data, pos);
        pos += 4;
        tensor_n_dims[i] = n_dims;

        for (0..@min(n_dims, 4)) |d| {
            if (pos + 8 > data.len) return -8;
            tensor_dims[i][d] = readU64LE(data, pos);
            pos += 8;
        }

        if (pos + 12 > data.len) return -9;
        tensor_types[i] = readU32LE(data, pos);
        pos += 4;
        tensor_offsets[i] = readU64LE(data, pos);
        pos += 8;
    }

    // Calculate data offset (aligned to 32 bytes)
    gguf_data_offset = (pos + 31) & ~@as(usize, 31);

    // Store tensor indices for key tensors
    token_embedding_idx = findTensor("t.token_embd.weight");
    position_embedding_idx = findTensor("t.position_embd.weight");
    ln_final_weight_idx = findTensor("t.post_ln.weight");
    ln_final_bias_idx = findTensor("t.post_ln.bias");
    text_projection_idx = findTensor("text_projection.weight");

    // Store per-layer tensor indices
    for (0..CLIP_NUM_LAYERS) |layer| {
        var name_buf: [64]u8 = undefined;

        const ln1_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ln1.weight", .{layer}) catch continue;
        layer_ln1_weight_idx[layer] = findTensor(ln1_w);

        const ln1_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ln1.bias", .{layer}) catch continue;
        layer_ln1_bias_idx[layer] = findTensor(ln1_b);

        const q_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_q.weight", .{layer}) catch continue;
        layer_attn_q_weight_idx[layer] = findTensor(q_w);

        const q_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_q.bias", .{layer}) catch continue;
        layer_attn_q_bias_idx[layer] = findTensor(q_b);

        const k_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_k.weight", .{layer}) catch continue;
        layer_attn_k_weight_idx[layer] = findTensor(k_w);

        const k_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_k.bias", .{layer}) catch continue;
        layer_attn_k_bias_idx[layer] = findTensor(k_b);

        const v_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_v.weight", .{layer}) catch continue;
        layer_attn_v_weight_idx[layer] = findTensor(v_w);

        const v_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_v.bias", .{layer}) catch continue;
        layer_attn_v_bias_idx[layer] = findTensor(v_b);

        const out_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_out.weight", .{layer}) catch continue;
        layer_attn_out_weight_idx[layer] = findTensor(out_w);

        const out_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.attn_out.bias", .{layer}) catch continue;
        layer_attn_out_bias_idx[layer] = findTensor(out_b);

        const ln2_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ln2.weight", .{layer}) catch continue;
        layer_ln2_weight_idx[layer] = findTensor(ln2_w);

        const ln2_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ln2.bias", .{layer}) catch continue;
        layer_ln2_bias_idx[layer] = findTensor(ln2_b);

        const fc1_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ffn_down.weight", .{layer}) catch continue;
        layer_mlp_fc1_weight_idx[layer] = findTensor(fc1_w);

        const fc1_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ffn_down.bias", .{layer}) catch continue;
        layer_mlp_fc1_bias_idx[layer] = findTensor(fc1_b);

        const fc2_w = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ffn_up.weight", .{layer}) catch continue;
        layer_mlp_fc2_weight_idx[layer] = findTensor(fc2_w);

        const fc2_b = std.fmt.bufPrint(&name_buf, "t.blk.{d}.ffn_up.bias", .{layer}) catch continue;
        layer_mlp_fc2_bias_idx[layer] = findTensor(fc2_b);
    }

    // Verify essential weights loaded
    if (token_embedding_idx == null) return -10;
    if (position_embedding_idx == null) return -11;
    if (ln_final_weight_idx == null) return -12;
    if (text_projection_idx == null) return -13;

    clip_model_loaded = true;
    return 0;
}

// Layer normalization
fn layerNorm(input: []const f32, weight: []const f32, bias: []const f32, output: []f32) void {
    const dim = weight.len;
    const eps: f32 = 1e-5;

    // Compute mean
    var mean: f32 = 0;
    for (input[0..dim]) |v| {
        mean += v;
    }
    mean /= @floatFromInt(dim);

    // Compute variance
    var variance: f32 = 0;
    for (input[0..dim]) |v| {
        const diff = v - mean;
        variance += diff * diff;
    }
    variance /= @floatFromInt(dim);

    // Normalize
    const inv_std = 1.0 / @sqrt(variance + eps);
    for (0..dim) |i| {
        output[i] = (input[i] - mean) * inv_std * weight[i] + bias[i];
    }
}

// Matrix multiply: output[M,N] = input[M,K] @ weight[K,N]
fn matmul(input: []const f32, weight: []const f32, bias: ?[]const f32, output: []f32, M: usize, K: usize, N: usize) void {
    for (0..M) |m| {
        for (0..N) |n| {
            var sum: f32 = if (bias) |b| b[n] else 0;
            for (0..K) |k| {
                sum += input[m * K + k] * weight[k * N + n];
            }
            output[m * N + n] = sum;
        }
    }
}

// Error function (erf) approximation using Abramowitz and Stegun formula 7.1.26
// Maximum error: 1.5e-7
fn erf(x: f32) f32 {
    // Constants for the approximation
    const a1: f32 = 0.254829592;
    const a2: f32 = -0.284496736;
    const a3: f32 = 1.421413741;
    const a4: f32 = -1.453152027;
    const a5: f32 = 1.061405429;
    const p: f32 = 0.3275911;

    // Save the sign of x
    const sign: f32 = if (x < 0) -1.0 else 1.0;
    const abs_x = @abs(x);

    // A&S formula 7.1.26
    const t = 1.0 / (1.0 + p * abs_x);
    const t2 = t * t;
    const t3 = t2 * t;
    const t4 = t3 * t;
    const t5 = t4 * t;

    const y = 1.0 - (a1 * t + a2 * t2 + a3 * t3 + a4 * t4 + a5 * t5) * @exp(-abs_x * abs_x);

    return sign * y;
}

// Standard GELU activation (exact, using erf)
// GELU(x) = x * 0.5 * (1 + erf(x / sqrt(2)))
fn gelu(x: f32) f32 {
    const sqrt2_inv: f32 = 0.7071067811865476; // 1 / sqrt(2)
    return x * 0.5 * (1.0 + erf(x * sqrt2_inv));
}

// Softmax over last dimension
fn softmax(data: []f32, seq_len: usize) void {
    for (0..seq_len) |i| {
        const row = data[i * seq_len .. (i + 1) * seq_len];

        // Find max for numerical stability
        var max_val: f32 = row[0];
        for (row[1..]) |v| {
            if (v > max_val) max_val = v;
        }

        // Exp and sum
        var sum: f32 = 0;
        for (row) |*v| {
            v.* = @exp(v.* - max_val);
            sum += v.*;
        }

        // Normalize
        for (row) |*v| {
            v.* /= sum;
        }
    }
}

// Get vocab token at index
fn getVocabToken(idx: usize) []const u8 {
    if (vocab_data == null or idx >= vocab_count) return "";
    const start = vocab_string_offsets[idx];
    const vdata = vocab_data.?;
    // Read length as little-endian u64
    const len: usize = @intCast(
        @as(u64, vdata[start]) |
            (@as(u64, vdata[start + 1]) << 8) |
            (@as(u64, vdata[start + 2]) << 16) |
            (@as(u64, vdata[start + 3]) << 24) |
            (@as(u64, vdata[start + 4]) << 32) |
            (@as(u64, vdata[start + 5]) << 40) |
            (@as(u64, vdata[start + 6]) << 48) |
            (@as(u64, vdata[start + 7]) << 56),
    );
    return vdata[start + 8 .. start + 8 + len];
}

// Check if text starts with token (case-insensitive for letters)
fn startsWithToken(text: []const u8, token: []const u8) bool {
    if (token.len == 0 or token.len > text.len) return false;
    for (0..token.len) |i| {
        var tc = token[i];
        var xc = text[i];
        // Lowercase both
        if (tc >= 'A' and tc <= 'Z') tc = tc + 32;
        if (xc >= 'A' and xc <= 'Z') xc = xc + 32;
        if (tc != xc) return false;
    }
    return true;
}

// BPE tokenize - greedy longest match
fn tokenize(text: []const u8, tokens: []u32) usize {
    var n_tokens: usize = 0;
    var text_pos: usize = 0;

    // Start token
    tokens[n_tokens] = 49406;
    n_tokens += 1;

    while (text_pos < text.len and n_tokens < CLIP_MAX_SEQ_LEN - 1) {
        if (text[text_pos] == 0) break;

        // Skip leading spaces and add space token
        if (text[text_pos] == ' ') {
            text_pos += 1;
            continue;
        }

        // Find longest matching token
        var best_len: usize = 0;
        var best_id: u32 = 0;

        // Search vocab for longest match
        for (0..vocab_count) |i| {
            const tok = getVocabToken(i);
            if (tok.len > 0 and tok.len > best_len) {
                // Check for </w> suffix (word ending marker)
                var tok_text = tok;
                var is_word_end = false;
                if (tok.len >= 4 and tok[tok.len - 4] == '<' and tok[tok.len - 3] == '/' and tok[tok.len - 2] == 'w' and tok[tok.len - 1] == '>') {
                    tok_text = tok[0 .. tok.len - 4];
                    is_word_end = true;
                }

                if (startsWithToken(text[text_pos..], tok_text)) {
                    // For word-end tokens, check next char is space/end
                    if (is_word_end) {
                        const next_pos = text_pos + tok_text.len;
                        if (next_pos >= text.len or text[next_pos] == ' ' or text[next_pos] == 0) {
                            best_len = tok_text.len;
                            best_id = @intCast(i);
                        }
                    } else {
                        best_len = tok_text.len;
                        best_id = @intCast(i);
                    }
                }
            }
        }

        if (best_len > 0) {
            tokens[n_tokens] = best_id;
            n_tokens += 1;
            text_pos += best_len;
        } else {
            // Unknown char, skip
            text_pos += 1;
        }
    }

    // End token
    tokens[n_tokens] = 49407;
    n_tokens += 1;

    // Pad with end token
    const final_len = n_tokens;
    while (n_tokens < CLIP_MAX_SEQ_LEN) {
        tokens[n_tokens] = 49407;
        n_tokens += 1;
    }

    return final_len;
}

// Scratch buffer for weight row loading (reused across calls)
var weight_row_buf: [CLIP_MLP_DIM]f32 = undefined; // MLP_DIM is largest

// Multi-head self-attention with SIMD optimization
// input: normalized hidden states
// residual: original hidden states to add output to
fn multiHeadAttention(
    input: []f32,
    residual: []f32,
    seq_len: usize,
    layer: usize,
    q_out: []f32,
    k_out: []f32,
    v_out: []f32,
    attn_out: []f32,
) void {
    const q_w_idx = layer_attn_q_weight_idx[layer] orelse return;
    const q_b_idx = layer_attn_q_bias_idx[layer] orelse return;
    const k_w_idx = layer_attn_k_weight_idx[layer] orelse return;
    const k_b_idx = layer_attn_k_bias_idx[layer] orelse return;
    const v_w_idx = layer_attn_v_weight_idx[layer] orelse return;
    const v_b_idx = layer_attn_v_bias_idx[layer] orelse return;
    const out_w_idx = layer_attn_out_weight_idx[layer] orelse return;
    const out_b_idx = layer_attn_out_bias_idx[layer] orelse return;

    const scale: f32 = 1.0 / @sqrt(@as(f32, CLIP_HEAD_DIM));

    // Compute Q, K, V using SIMD linear layers
    for (0..seq_len) |pos| {
        const h: *const [CLIP_EMBED_DIM]f32 = @ptrCast(input[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        const q: *[CLIP_EMBED_DIM]f32 = @ptrCast(q_out[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        const k: *[CLIP_EMBED_DIM]f32 = @ptrCast(k_out[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        const v: *[CLIP_EMBED_DIM]f32 = @ptrCast(v_out[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);

        linearLayerSimd(CLIP_EMBED_DIM, CLIP_EMBED_DIM, h, q_w_idx, q_b_idx, q, weight_row_buf[0..CLIP_EMBED_DIM]);
        linearLayerSimd(CLIP_EMBED_DIM, CLIP_EMBED_DIM, h, k_w_idx, k_b_idx, k, weight_row_buf[0..CLIP_EMBED_DIM]);
        linearLayerSimd(CLIP_EMBED_DIM, CLIP_EMBED_DIM, h, v_w_idx, v_b_idx, v, weight_row_buf[0..CLIP_EMBED_DIM]);
    }

    // Compute attention scores with SIMD dot products
    for (0..CLIP_NUM_HEADS) |head| {
        const head_offset = head * CLIP_HEAD_DIM;

        for (0..seq_len) |i| {
            const qi: *const [CLIP_HEAD_DIM]f32 = @ptrCast(q_out[i * CLIP_EMBED_DIM + head_offset ..][0..CLIP_HEAD_DIM]);

            for (0..seq_len) |j| {
                // Causal mask: only attend to previous positions
                if (j > i) {
                    attn_out[head * seq_len * seq_len + i * seq_len + j] = -1e9;
                } else {
                    const kj: *const [CLIP_HEAD_DIM]f32 = @ptrCast(k_out[j * CLIP_EMBED_DIM + head_offset ..][0..CLIP_HEAD_DIM]);
                    attn_out[head * seq_len * seq_len + i * seq_len + j] = simdDot(CLIP_HEAD_DIM, qi, kj) * scale;
                }
            }
        }

        // Softmax per row (SIMD for exp and normalization)
        for (0..seq_len) |i| {
            const row_start = head * seq_len * seq_len + i * seq_len;

            // Find max
            var max_val: f32 = attn_out[row_start];
            for (1..seq_len) |j| {
                if (attn_out[row_start + j] > max_val) max_val = attn_out[row_start + j];
            }

            // Exp and sum
            var sum: f32 = 0;
            for (0..seq_len) |j| {
                attn_out[row_start + j] = @exp(attn_out[row_start + j] - max_val);
                sum += attn_out[row_start + j];
            }

            // Normalize
            const inv_sum = 1.0 / sum;
            for (0..seq_len) |j| {
                attn_out[row_start + j] *= inv_sum;
            }
        }
    }

    // Compute attention output with SIMD
    var attn_output: [CLIP_MAX_SEQ_LEN * CLIP_EMBED_DIM]f32 = undefined;

    for (0..seq_len) |pos| {
        const out_vec: *[CLIP_EMBED_DIM]f32 = @ptrCast(attn_output[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        simdZero(CLIP_EMBED_DIM, out_vec);

        for (0..CLIP_NUM_HEADS) |head| {
            const head_offset = head * CLIP_HEAD_DIM;
            const head_out: *[CLIP_HEAD_DIM]f32 = @ptrCast(attn_output[pos * CLIP_EMBED_DIM + head_offset ..][0..CLIP_HEAD_DIM]);

            for (0..seq_len) |j| {
                const attn_weight = attn_out[head * seq_len * seq_len + pos * seq_len + j];
                const vj: *const [CLIP_HEAD_DIM]f32 = @ptrCast(v_out[j * CLIP_EMBED_DIM + head_offset ..][0..CLIP_HEAD_DIM]);
                simdScalarMulAdd(CLIP_HEAD_DIM, head_out, attn_weight, vj);
            }
        }

        // Output projection with SIMD
        const attn_vec: *const [CLIP_EMBED_DIM]f32 = @ptrCast(attn_output[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        var proj_out: [CLIP_EMBED_DIM]f32 = undefined;
        linearLayerSimd(CLIP_EMBED_DIM, CLIP_EMBED_DIM, attn_vec, out_w_idx, out_b_idx, &proj_out, weight_row_buf[0..CLIP_EMBED_DIM]);

        // Add to residual
        const res: *[CLIP_EMBED_DIM]f32 = @ptrCast(residual[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        simdAdd(CLIP_EMBED_DIM, res, &proj_out);
    }
}

// MLP block with SIMD: FFN(x) = GELU(x @ W1^T + b1) @ W2^T + b2
// input: normalized hidden states
// residual: original hidden states to add output to
fn mlpBlock(input: []f32, residual: []f32, seq_len: usize, layer: usize) void {
    const fc1_w_idx = layer_mlp_fc1_weight_idx[layer] orelse return;
    const fc1_b_idx = layer_mlp_fc1_bias_idx[layer] orelse return;
    const fc2_w_idx = layer_mlp_fc2_weight_idx[layer] orelse return;
    const fc2_b_idx = layer_mlp_fc2_bias_idx[layer] orelse return;

    for (0..seq_len) |pos| {
        const h: *const [CLIP_EMBED_DIM]f32 = @ptrCast(input[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);

        // First linear: embed_dim -> mlp_dim using SIMD
        var mlp_hidden: [CLIP_MLP_DIM]f32 = undefined;
        linearLayerSimd(CLIP_EMBED_DIM, CLIP_MLP_DIM, h, fc1_w_idx, fc1_b_idx, &mlp_hidden, weight_row_buf[0..CLIP_EMBED_DIM]);

        // Standard GELU activation (exact, using erf)
        // GELU(x) = x * 0.5 * (1 + erf(x / sqrt(2)))
        // This matches PyTorch's GELU(approximate='none')
        const sqrt2_inv: f32 = 1.0 / @sqrt(2.0); // 0.7071067811865476
        var i: usize = 0;
        while (i < CLIP_MLP_DIM) : (i += SIMD_WIDTH) {
            const x: Vec4 = mlp_hidden[i..][0..SIMD_WIDTH].*;
            // Compute erf(x / sqrt(2)) element-wise
            var erf_val: Vec4 = undefined;
            inline for (0..SIMD_WIDTH) |k| {
                erf_val[k] = erf(x[k] * sqrt2_inv);
            }
            // GELU = x * 0.5 * (1 + erf_val)
            const half: Vec4 = @splat(0.5);
            const one: Vec4 = @splat(1.0);
            mlp_hidden[i..][0..SIMD_WIDTH].* = x * half * (one + erf_val);
        }

        // Debug: save fc1 output (after GELU) for layer 0, pos 0
        if (layer == 0 and pos == 0) {
            @memcpy(&debug_after_fc1, mlp_hidden[0..8]);
        }

        // Second linear: mlp_dim -> embed_dim using SIMD
        var fc2_out: [CLIP_EMBED_DIM]f32 = undefined;
        linearLayerSimd(CLIP_MLP_DIM, CLIP_EMBED_DIM, &mlp_hidden, fc2_w_idx, fc2_b_idx, &fc2_out, &weight_row_buf);

        // Debug: save fc2 output for layer 0, pos 0
        if (layer == 0 and pos == 0) {
            @memcpy(&debug_after_fc2, fc2_out[0..8]);
        }

        // Add to residual with SIMD
        const res: *[CLIP_EMBED_DIM]f32 = @ptrCast(residual[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);
        simdAdd(CLIP_EMBED_DIM, res, &fc2_out);
    }
}

// Layer norm in-place using tensor indices with SIMD
fn layerNormInPlace(hidden: []f32, seq_len: usize, weight_idx: usize, bias_idx: usize) void {
    const eps: f32 = 1e-5;

    for (0..seq_len) |pos| {
        var h: *[CLIP_EMBED_DIM]f32 = @ptrCast(hidden[pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM]);

        // Mean using SIMD
        var sum_vec: Vec4 = @splat(0);
        var i: usize = 0;
        while (i < CLIP_EMBED_DIM) : (i += SIMD_WIDTH) {
            sum_vec += h[i..][0..SIMD_WIDTH].*;
        }
        const mean = @reduce(.Add, sum_vec) / @as(f32, CLIP_EMBED_DIM);

        // Variance using SIMD
        const mean_vec: Vec4 = @splat(mean);
        var var_vec: Vec4 = @splat(0);
        i = 0;
        while (i < CLIP_EMBED_DIM) : (i += SIMD_WIDTH) {
            const diff = h[i..][0..SIMD_WIDTH].* - mean_vec;
            var_vec += diff * diff;
        }
        const variance = @reduce(.Add, var_vec) / @as(f32, CLIP_EMBED_DIM);
        const inv_std = 1.0 / @sqrt(variance + eps);

        // Normalize with weight and bias
        // Load weight and bias rows
        var weight_buf: [CLIP_EMBED_DIM]f32 = undefined;
        var bias_buf: [CLIP_EMBED_DIM]f32 = undefined;
        getWeightRowF32(weight_idx, 0, CLIP_EMBED_DIM, &weight_buf);
        getWeightRowF32(bias_idx, 0, CLIP_EMBED_DIM, &bias_buf);

        const inv_std_vec: Vec4 = @splat(inv_std);
        i = 0;
        while (i < CLIP_EMBED_DIM) : (i += SIMD_WIDTH) {
            const x = h[i..][0..SIMD_WIDTH].*;
            const w: Vec4 = weight_buf[i..][0..SIMD_WIDTH].*;
            const b: Vec4 = bias_buf[i..][0..SIMD_WIDTH].*;
            h[i..][0..SIMD_WIDTH].* = (x - mean_vec) * inv_std_vec * w + b;
        }
    }
}

/// Encode text to embedding
/// Returns 0 on success, negative on error
export fn clip_encode_text(text_len: usize) i32 {
    if (!clip_initialized) return -1;
    if (!clip_model_loaded) return -2;
    if (text_len == 0 or text_len > clip_text_buffer.len) return -3;

    const tok_emb_idx = token_embedding_idx orelse return -4;
    const pos_emb_idx = position_embedding_idx orelse return -5;
    const ln_w_idx = ln_final_weight_idx orelse return -6;
    const ln_b_idx = ln_final_bias_idx orelse return -7;
    const proj_idx = text_projection_idx orelse return -8;

    // Tokenize
    var tokens: [CLIP_MAX_SEQ_LEN]u32 = undefined;
    const seq_len = tokenize(clip_text_buffer[0..text_len], &tokens);

    // Store for debug
    @memcpy(&debug_tokens, &tokens);
    debug_token_count = seq_len;

    // Initialize hidden states with token + position embeddings
    // GGUF stores embeddings as [vocab_size/seq_len, embed_dim] row-major
    for (0..seq_len) |pos| {
        const tok_id = tokens[pos];
        for (0..CLIP_EMBED_DIM) |i| {
            // Token embedding: [vocab_size, embed_dim] -> tok_id * embed_dim + i
            // Position embedding: [seq_len, embed_dim] -> pos * embed_dim + i
            scratch_hidden[pos * CLIP_EMBED_DIM + i] =
                readWeight(tok_emb_idx, tok_id * CLIP_EMBED_DIM + i) +
                readWeight(pos_emb_idx, pos * CLIP_EMBED_DIM + i);
        }
    }

    // Debug: save initial embedding for position 0
    @memcpy(&debug_after_embedding, scratch_hidden[0..CLIP_EMBED_DIM]);

    // Run through transformer layers
    // CLIP uses pre-norm: LN -> Attn -> residual, LN -> MLP -> residual
    for (0..CLIP_NUM_LAYERS) |layer| {
        // Pre-attention layer norm
        const ln1_w_idx = layer_ln1_weight_idx[layer] orelse continue;
        const ln1_b_idx = layer_ln1_bias_idx[layer] orelse continue;

        // Apply layer norm to scratch_ln (input to attention)
        @memcpy(scratch_ln[0 .. seq_len * CLIP_EMBED_DIM], scratch_hidden[0 .. seq_len * CLIP_EMBED_DIM]);
        layerNormInPlace(&scratch_ln, seq_len, ln1_w_idx, ln1_b_idx);

        // Debug: save after ln1 on first layer
        if (layer == 0) {
            @memcpy(&debug_after_ln1, scratch_ln[0..CLIP_EMBED_DIM]);
        }

        // Multi-head attention on normalized input, adds to scratch_hidden (residual)
        multiHeadAttention(&scratch_ln, &scratch_hidden, seq_len, layer, &scratch_q, &scratch_k, &scratch_v, &scratch_attn);

        // Debug: save after attention on first layer
        if (layer == 0) {
            @memcpy(&debug_after_attn, scratch_hidden[0..CLIP_EMBED_DIM]);
        }

        // Pre-MLP layer norm
        const ln2_w_idx = layer_ln2_weight_idx[layer] orelse continue;
        const ln2_b_idx = layer_ln2_bias_idx[layer] orelse continue;

        // Apply layer norm to scratch_ln (input to MLP)
        @memcpy(scratch_ln[0 .. seq_len * CLIP_EMBED_DIM], scratch_hidden[0 .. seq_len * CLIP_EMBED_DIM]);

        // Debug: save pre-ln2 and weights on first layer
        if (layer == 0) {
            @memcpy(&debug_pre_ln2, scratch_ln[0..8]);
            for (0..8) |i| {
                debug_ln2_w[i] = readWeight(ln2_w_idx, i);
                debug_ln2_b[i] = readWeight(ln2_b_idx, i);
            }

            // Compute mean/std for debug
            const h = scratch_ln[0..CLIP_EMBED_DIM];
            var sum: f32 = 0;
            for (h) |v| sum += v;
            debug_ln2_mean = sum / @as(f32, CLIP_EMBED_DIM);

            var var_sum: f32 = 0;
            for (h) |v| {
                const diff = v - debug_ln2_mean;
                var_sum += diff * diff;
            }
            debug_ln2_std = @sqrt(var_sum / @as(f32, CLIP_EMBED_DIM));
        }

        layerNormInPlace(&scratch_ln, seq_len, ln2_w_idx, ln2_b_idx);

        // Debug: save after ln2 on first layer
        if (layer == 0) {
            @memcpy(&debug_after_ln2, scratch_ln[0..CLIP_EMBED_DIM]);
        }

        // MLP on normalized input, adds to scratch_hidden (residual)
        mlpBlock(&scratch_ln, &scratch_hidden, seq_len, layer);

        // Debug: save after first layer
        if (layer == 0) {
            @memcpy(&debug_after_layer0, scratch_hidden[0..CLIP_EMBED_DIM]);
        }
    }

    // Final layer norm
    layerNormInPlace(&scratch_hidden, seq_len, ln_w_idx, ln_b_idx);

    // Take embedding at EOS position (last real token before padding)
    const eos_pos = seq_len - 1;
    const final_hidden = scratch_hidden[eos_pos * CLIP_EMBED_DIM ..][0..CLIP_EMBED_DIM];

    // Project to output dimension: y = x @ W^T, W is [out, in]
    for (0..CLIP_EMBED_DIM) |i| {
        var sum: f32 = 0;
        for (0..CLIP_EMBED_DIM) |j| {
            sum += final_hidden[j] * readWeight(proj_idx, i * CLIP_EMBED_DIM + j);
        }
        clip_output_buffer[i] = sum;
    }

    // Debug: save pre-norm output
    @memcpy(&debug_pre_norm, clip_output_buffer[0..8]);
    var pre_norm_sq: f32 = 0;
    for (clip_output_buffer) |v| pre_norm_sq += v * v;
    debug_pre_norm_norm = @sqrt(pre_norm_sq);

    // L2 normalize
    var norm_sq: f32 = 0;
    for (clip_output_buffer) |v| norm_sq += v * v;
    const norm = @sqrt(norm_sq);
    if (norm > 0) {
        for (&clip_output_buffer) |*v| v.* /= norm;
    }

    return 0;
}

/// Test function for CLIP
export fn clip_test_add(a: i32, b: i32) i32 {
    return a + b;
}

// Debug: get token at position after encoding
var debug_tokens: [CLIP_MAX_SEQ_LEN]u32 = undefined;
var debug_token_count: usize = 0;

// Debug buffer to store intermediate values
var debug_hidden: [CLIP_EMBED_DIM]f32 = undefined;
var debug_stage: usize = 0; // 0=embedding, 1=after_layer0, etc
var debug_after_embedding: [CLIP_EMBED_DIM]f32 = undefined;
var debug_after_ln1: [CLIP_EMBED_DIM]f32 = undefined;
var debug_after_attn: [CLIP_EMBED_DIM]f32 = undefined;
var debug_after_ln2: [CLIP_EMBED_DIM]f32 = undefined;
var debug_after_fc1: [8]f32 = undefined; // First 8 of mlp_hidden (after GELU)
var debug_after_fc2: [8]f32 = undefined; // First 8 of fc2 output
var debug_after_layer0: [CLIP_EMBED_DIM]f32 = undefined;
var debug_ln2_w: [8]f32 = undefined;
var debug_ln2_b: [8]f32 = undefined;
var debug_pre_ln2: [8]f32 = undefined; // hidden state before ln2
var debug_ln2_mean: f32 = 0;
var debug_ln2_std: f32 = 0;
var debug_pre_norm: [8]f32 = undefined;
var debug_pre_norm_norm: f32 = 0;

export fn clip_debug_get_token(pos: usize) u32 {
    if (pos < debug_token_count) {
        return debug_tokens[pos];
    }
    return 0;
}

export fn clip_debug_get_token_count() usize {
    return debug_token_count;
}

// Get debug hidden state at dimension i
export fn clip_debug_get_hidden(i: usize) f32 {
    if (i < CLIP_EMBED_DIM) {
        return debug_hidden[i];
    }
    return 0;
}

// Get token embedding value directly
export fn clip_debug_get_token_emb(token_id: u32, dim: usize) f32 {
    const tok_emb_idx = token_embedding_idx orelse return -999;
    return readWeight(tok_emb_idx, token_id * CLIP_EMBED_DIM + dim);
}

// Get position embedding value directly
export fn clip_debug_get_pos_emb(pos: usize, dim: usize) f32 {
    const pos_emb_idx = position_embedding_idx orelse return -999;
    return readWeight(pos_emb_idx, pos * CLIP_EMBED_DIM + dim);
}

// Get scratch_hidden value (after embedding, or after each layer)
export fn clip_debug_get_scratch_hidden(pos: usize, dim: usize) f32 {
    if (pos < CLIP_MAX_SEQ_LEN and dim < CLIP_EMBED_DIM) {
        return scratch_hidden[pos * CLIP_EMBED_DIM + dim];
    }
    return -999;
}

// Get debug values at different stages
export fn clip_debug_get_after_embedding(dim: usize) f32 {
    if (dim < CLIP_EMBED_DIM) return debug_after_embedding[dim];
    return -999;
}

export fn clip_debug_get_after_layer0(dim: usize) f32 {
    if (dim < CLIP_EMBED_DIM) return debug_after_layer0[dim];
    return -999;
}

export fn clip_debug_get_after_ln1(dim: usize) f32 {
    if (dim < CLIP_EMBED_DIM) return debug_after_ln1[dim];
    return -999;
}

export fn clip_debug_get_after_attn(dim: usize) f32 {
    if (dim < CLIP_EMBED_DIM) return debug_after_attn[dim];
    return -999;
}

export fn clip_debug_get_after_ln2(dim: usize) f32 {
    if (dim < CLIP_EMBED_DIM) return debug_after_ln2[dim];
    return -999;
}

export fn clip_debug_get_after_fc1(dim: usize) f32 {
    if (dim < 8) return debug_after_fc1[dim];
    return -999;
}

export fn clip_debug_get_after_fc2(dim: usize) f32 {
    if (dim < 8) return debug_after_fc2[dim];
    return -999;
}

export fn clip_debug_get_ln2_w(dim: usize) f32 {
    if (dim < 8) return debug_ln2_w[dim];
    return -999;
}

export fn clip_debug_get_ln2_b(dim: usize) f32 {
    if (dim < 8) return debug_ln2_b[dim];
    return -999;
}

export fn clip_debug_get_pre_ln2(dim: usize) f32 {
    if (dim < 8) return debug_pre_ln2[dim];
    return -999;
}

export fn clip_debug_get_ln2_mean() f32 {
    return debug_ln2_mean;
}

export fn clip_debug_get_ln2_std() f32 {
    return debug_ln2_std;
}

export fn clip_debug_get_pre_norm(dim: usize) f32 {
    if (dim < 8) return debug_pre_norm[dim];
    return -999;
}

export fn clip_debug_get_pre_norm_norm() f32 {
    return debug_pre_norm_norm;
}

// ============================================================================
// Zstd Decompression
// ============================================================================

/// Decompresses zstd-compressed data in place or to a destination buffer.
/// compressed_ptr: pointer to compressed data
/// compressed_len: length of compressed data
/// decompressed_ptr: pointer to output buffer (must be pre-allocated with enough space)
/// decompressed_capacity: capacity of output buffer
/// Returns: decompressed size on success, 0 on error
export fn zstd_decompress(
    compressed_ptr: [*]const u8,
    compressed_len: usize,
    decompressed_ptr: [*]u8,
    decompressed_capacity: usize,
) usize {
    const compressed = compressed_ptr[0..compressed_len];

    // Use std.io.Reader.fixed for the new Zig 0.15 Reader API
    var reader = std.io.Reader.fixed(compressed);

    // Use fixed Writer for output buffer
    var writer = std.io.Writer.fixed(decompressed_ptr[0..decompressed_capacity]);

    // Initialize zstd decompressor (empty buffer = direct streaming mode)
    var zstd_stream = std.compress.zstd.Decompress.init(&reader, &.{}, .{});

    // Stream all decompressed data to writer
    const bytes_written = zstd_stream.reader.streamRemaining(&writer) catch {
        return 0;
    };

    return bytes_written;
}

// ============================================================================
// MiniLM Text Encoder (all-MiniLM-L6-v2)
// ============================================================================

// MiniLM model constants
const MINILM_VOCAB_SIZE: usize = 30522;
const MINILM_MAX_SEQ_LEN: usize = 256; // Shorter for typical queries
const MINILM_EMBED_DIM: usize = 384;
const MINILM_NUM_HEADS: usize = 12;
const MINILM_NUM_LAYERS: usize = 6;
const MINILM_MLP_DIM: usize = 1536;
const MINILM_HEAD_DIM: usize = MINILM_EMBED_DIM / MINILM_NUM_HEADS; // 32

// Comptime assertions for SIMD alignment
comptime {
    if (MINILM_EMBED_DIM % SIMD_WIDTH != 0) @compileError("MINILM_EMBED_DIM must be divisible by SIMD_WIDTH");
    if (MINILM_HEAD_DIM % SIMD_WIDTH != 0) @compileError("MINILM_HEAD_DIM must be divisible by SIMD_WIDTH");
    if (MINILM_MLP_DIM % SIMD_WIDTH != 0) @compileError("MINILM_MLP_DIM must be divisible by SIMD_WIDTH");
}

// MiniLM state
var minilm_initialized: bool = false;
var minilm_model_loaded: bool = false;

// Buffers for MiniLM
var minilm_text_buffer: [1024]u8 = undefined;
var minilm_output_buffer: [MINILM_EMBED_DIM]f32 = undefined;

// Model weights storage
var minilm_model_buffer: ?[*]u8 = null;
var minilm_model_size: usize = 0;

// GGUF parsing state for MiniLM
var minilm_gguf_data_offset: usize = 0;
var minilm_n_tensors_loaded: usize = 0;
var minilm_tensor_names: [MAX_TENSORS][96]u8 = undefined; // Longer names for BERT
var minilm_tensor_name_lens: [MAX_TENSORS]usize = undefined;
var minilm_tensor_offsets: [MAX_TENSORS]u64 = undefined;
var minilm_tensor_types: [MAX_TENSORS]u32 = undefined;
var minilm_tensor_dims: [MAX_TENSORS][4]u64 = undefined;
var minilm_tensor_n_dims: [MAX_TENSORS]u32 = undefined;

// MiniLM vocab
var minilm_vocab_data: ?[*]const u8 = null;
var minilm_vocab_count: usize = 0;
var minilm_vocab_string_offsets: [MINILM_VOCAB_SIZE + 1]u32 = undefined;

// MiniLM weight tensor indices
var minilm_word_emb_idx: ?usize = null;
var minilm_pos_emb_idx: ?usize = null;
var minilm_token_type_emb_idx: ?usize = null;
var minilm_emb_ln_weight_idx: ?usize = null;
var minilm_emb_ln_bias_idx: ?usize = null;

// Per-layer weight indices (6 layers)
var minilm_layer_q_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_q_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_k_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_k_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_v_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_v_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_out_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_out_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_attn_ln_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_attn_ln_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_ffn_up_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_ffn_up_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_ffn_down_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_ffn_down_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_ffn_ln_weight_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;
var minilm_layer_ffn_ln_bias_idx: [MINILM_NUM_LAYERS]?usize = [_]?usize{null} ** MINILM_NUM_LAYERS;

// Scratch buffers for MiniLM inference
var minilm_scratch_hidden: [MINILM_MAX_SEQ_LEN * MINILM_EMBED_DIM]f32 = undefined;
var minilm_scratch_q: [MINILM_MAX_SEQ_LEN * MINILM_EMBED_DIM]f32 = undefined;
var minilm_scratch_k: [MINILM_MAX_SEQ_LEN * MINILM_EMBED_DIM]f32 = undefined;
var minilm_scratch_v: [MINILM_MAX_SEQ_LEN * MINILM_EMBED_DIM]f32 = undefined;
var minilm_scratch_attn: [MINILM_NUM_HEADS * MINILM_MAX_SEQ_LEN * MINILM_MAX_SEQ_LEN]f32 = undefined;
var minilm_scratch_ln: [MINILM_MAX_SEQ_LEN * MINILM_EMBED_DIM]f32 = undefined;
var minilm_weight_row_buf: [MINILM_MLP_DIM]f32 = undefined;

/// Initialize MiniLM module
export fn minilm_init() i32 {
    minilm_initialized = true;
    minilm_model_loaded = false;

    for (&minilm_output_buffer) |*v| {
        v.* = 0;
    }

    return 0;
}

/// Get pointer to text input buffer
export fn minilm_get_text_buffer() [*]u8 {
    return &minilm_text_buffer;
}

/// Get size of text input buffer
export fn minilm_get_text_buffer_size() usize {
    return minilm_text_buffer.len;
}

/// Get pointer to output embedding buffer
export fn minilm_get_output_buffer() [*]f32 {
    return &minilm_output_buffer;
}

/// Get output embedding dimension
export fn minilm_get_output_dim() usize {
    return MINILM_EMBED_DIM;
}

/// Allocate buffer for model weights
export fn minilm_alloc_model_buffer(size: usize) usize {
    const page_size: usize = 65536;
    const pages_needed = (size + page_size - 1) / page_size;

    const current_pages = @wasmMemorySize(0);
    const current_size = current_pages * page_size;

    const result = @wasmMemoryGrow(0, pages_needed);
    if (result == @as(usize, @bitCast(@as(isize, -1)))) {
        return 0;
    }

    const ptr: [*]u8 = @ptrFromInt(current_size);
    minilm_model_buffer = ptr;
    minilm_model_size = size;
    return current_size;
}

/// Check if model weights are loaded
export fn minilm_weights_loaded() i32 {
    return if (minilm_model_loaded) 1 else 0;
}

// Find tensor in MiniLM model
fn minilmFindTensor(name: []const u8) ?usize {
    for (0..minilm_n_tensors_loaded) |i| {
        if (strEql(minilm_tensor_names[i][0..minilm_tensor_name_lens[i]], name)) {
            return i;
        }
    }
    return null;
}

// Read weight from MiniLM model
fn minilmReadWeight(idx: usize, i: usize) f32 {
    const model_data = minilm_model_buffer orelse return 0;
    const offset: usize = minilm_gguf_data_offset + @as(usize, @intCast(minilm_tensor_offsets[idx]));

    if (minilm_tensor_types[idx] == GGML_TYPE_F16) {
        const ptr: [*]const u16 = @ptrCast(@alignCast(model_data + offset));
        return f16ToF32(ptr[i]);
    } else {
        const ptr: [*]const f32 = @ptrCast(@alignCast(model_data + offset));
        return ptr[i];
    }
}

// Get weight row from MiniLM model
fn minilmGetWeightRowF32(idx: usize, row: usize, row_len: usize, buf: []f32) void {
    const model_data = minilm_model_buffer orelse return;
    const offset: usize = minilm_gguf_data_offset + @as(usize, @intCast(minilm_tensor_offsets[idx]));
    const row_offset = row * row_len;

    if (minilm_tensor_types[idx] == GGML_TYPE_F16) {
        const ptr: [*]const u16 = @ptrCast(@alignCast(model_data + offset));
        for (0..row_len) |i| {
            buf[i] = f16ToF32(ptr[row_offset + i]);
        }
    } else {
        const ptr: [*]const f32 = @ptrCast(@alignCast(model_data + offset));
        @memcpy(buf[0..row_len], ptr[row_offset .. row_offset + row_len]);
    }
}

// Linear layer for MiniLM dimensions
fn minilmLinearLayer384to384(
    input: *const [MINILM_EMBED_DIM]f32,
    w_idx: usize,
    b_idx: usize,
    output: *[MINILM_EMBED_DIM]f32,
) void {
    for (0..MINILM_EMBED_DIM) |i| {
        minilmGetWeightRowF32(w_idx, i, MINILM_EMBED_DIM, minilm_weight_row_buf[0..MINILM_EMBED_DIM]);
        var sum: f32 = minilmReadWeight(b_idx, i);
        var j: usize = 0;
        while (j < MINILM_EMBED_DIM) : (j += SIMD_WIDTH) {
            const va: Vec4 = input[j..][0..SIMD_WIDTH].*;
            const vb: Vec4 = minilm_weight_row_buf[j..][0..SIMD_WIDTH].*;
            sum += @reduce(.Add, va * vb);
        }
        output[i] = sum;
    }
}

fn minilmLinearLayer384to1536(
    input: *const [MINILM_EMBED_DIM]f32,
    w_idx: usize,
    b_idx: usize,
    output: *[MINILM_MLP_DIM]f32,
) void {
    for (0..MINILM_MLP_DIM) |i| {
        minilmGetWeightRowF32(w_idx, i, MINILM_EMBED_DIM, minilm_weight_row_buf[0..MINILM_EMBED_DIM]);
        var sum: f32 = minilmReadWeight(b_idx, i);
        var j: usize = 0;
        while (j < MINILM_EMBED_DIM) : (j += SIMD_WIDTH) {
            const va: Vec4 = input[j..][0..SIMD_WIDTH].*;
            const vb: Vec4 = minilm_weight_row_buf[j..][0..SIMD_WIDTH].*;
            sum += @reduce(.Add, va * vb);
        }
        output[i] = sum;
    }
}

fn minilmLinearLayer1536to384(
    input: *const [MINILM_MLP_DIM]f32,
    w_idx: usize,
    b_idx: usize,
    output: *[MINILM_EMBED_DIM]f32,
) void {
    for (0..MINILM_EMBED_DIM) |i| {
        minilmGetWeightRowF32(w_idx, i, MINILM_MLP_DIM, &minilm_weight_row_buf);
        var sum: f32 = minilmReadWeight(b_idx, i);
        var j: usize = 0;
        while (j < MINILM_MLP_DIM) : (j += SIMD_WIDTH) {
            const va: Vec4 = input[j..][0..SIMD_WIDTH].*;
            const vb: Vec4 = minilm_weight_row_buf[j..][0..SIMD_WIDTH].*;
            sum += @reduce(.Add, va * vb);
        }
        output[i] = sum;
    }
}

// Layer norm for MiniLM
fn minilmLayerNorm(input: []f32, seq_len: usize, weight_idx: usize, bias_idx: usize) void {
    const eps: f32 = 1e-12; // BERT uses 1e-12

    for (0..seq_len) |pos| {
        var h: *[MINILM_EMBED_DIM]f32 = @ptrCast(input[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);

        // Mean
        var sum_vec: Vec4 = @splat(0);
        var i: usize = 0;
        while (i < MINILM_EMBED_DIM) : (i += SIMD_WIDTH) {
            sum_vec += h[i..][0..SIMD_WIDTH].*;
        }
        const mean = @reduce(.Add, sum_vec) / @as(f32, MINILM_EMBED_DIM);

        // Variance
        const mean_vec: Vec4 = @splat(mean);
        var var_vec: Vec4 = @splat(0);
        i = 0;
        while (i < MINILM_EMBED_DIM) : (i += SIMD_WIDTH) {
            const diff = h[i..][0..SIMD_WIDTH].* - mean_vec;
            var_vec += diff * diff;
        }
        const variance = @reduce(.Add, var_vec) / @as(f32, MINILM_EMBED_DIM);
        const inv_std = 1.0 / @sqrt(variance + eps);

        // Normalize
        var weight_buf: [MINILM_EMBED_DIM]f32 = undefined;
        var bias_buf: [MINILM_EMBED_DIM]f32 = undefined;
        minilmGetWeightRowF32(weight_idx, 0, MINILM_EMBED_DIM, &weight_buf);
        minilmGetWeightRowF32(bias_idx, 0, MINILM_EMBED_DIM, &bias_buf);

        const inv_std_vec: Vec4 = @splat(inv_std);
        i = 0;
        while (i < MINILM_EMBED_DIM) : (i += SIMD_WIDTH) {
            const x = h[i..][0..SIMD_WIDTH].*;
            const w: Vec4 = weight_buf[i..][0..SIMD_WIDTH].*;
            const b: Vec4 = bias_buf[i..][0..SIMD_WIDTH].*;
            h[i..][0..SIMD_WIDTH].* = (x - mean_vec) * inv_std_vec * w + b;
        }
    }
}

// MiniLM multi-head attention (bidirectional, no causal mask)
fn minilmMultiHeadAttention(
    input: []f32,
    seq_len: usize,
    layer: usize,
) void {
    const q_w_idx = minilm_layer_q_weight_idx[layer] orelse return;
    const q_b_idx = minilm_layer_q_bias_idx[layer] orelse return;
    const k_w_idx = minilm_layer_k_weight_idx[layer] orelse return;
    const k_b_idx = minilm_layer_k_bias_idx[layer] orelse return;
    const v_w_idx = minilm_layer_v_weight_idx[layer] orelse return;
    const v_b_idx = minilm_layer_v_bias_idx[layer] orelse return;
    const out_w_idx = minilm_layer_out_weight_idx[layer] orelse return;
    const out_b_idx = minilm_layer_out_bias_idx[layer] orelse return;
    const ln_w_idx = minilm_layer_attn_ln_weight_idx[layer] orelse return;
    const ln_b_idx = minilm_layer_attn_ln_bias_idx[layer] orelse return;

    const scale: f32 = 1.0 / @sqrt(@as(f32, MINILM_HEAD_DIM));

    // Compute Q, K, V
    for (0..seq_len) |pos| {
        const h: *const [MINILM_EMBED_DIM]f32 = @ptrCast(input[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);
        const q: *[MINILM_EMBED_DIM]f32 = @ptrCast(minilm_scratch_q[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);
        const k: *[MINILM_EMBED_DIM]f32 = @ptrCast(minilm_scratch_k[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);
        const v: *[MINILM_EMBED_DIM]f32 = @ptrCast(minilm_scratch_v[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);

        minilmLinearLayer384to384(h, q_w_idx, q_b_idx, q);
        minilmLinearLayer384to384(h, k_w_idx, k_b_idx, k);
        minilmLinearLayer384to384(h, v_w_idx, v_b_idx, v);
    }

    // Compute attention scores (bidirectional - no causal mask)
    for (0..MINILM_NUM_HEADS) |head| {
        const head_offset = head * MINILM_HEAD_DIM;

        for (0..seq_len) |i| {
            for (0..seq_len) |j| {
                // SIMD dot product for head dimension
                var sum: f32 = 0;
                var d: usize = 0;
                while (d < MINILM_HEAD_DIM) : (d += SIMD_WIDTH) {
                    const qi: Vec4 = minilm_scratch_q[i * MINILM_EMBED_DIM + head_offset + d ..][0..SIMD_WIDTH].*;
                    const kj: Vec4 = minilm_scratch_k[j * MINILM_EMBED_DIM + head_offset + d ..][0..SIMD_WIDTH].*;
                    sum += @reduce(.Add, qi * kj);
                }
                minilm_scratch_attn[head * seq_len * seq_len + i * seq_len + j] = sum * scale;
            }
        }

        // Softmax per row
        for (0..seq_len) |i| {
            const row_start = head * seq_len * seq_len + i * seq_len;

            // Find max
            var max_val: f32 = minilm_scratch_attn[row_start];
            for (1..seq_len) |j| {
                if (minilm_scratch_attn[row_start + j] > max_val) max_val = minilm_scratch_attn[row_start + j];
            }

            // Exp and sum
            var sum: f32 = 0;
            for (0..seq_len) |j| {
                minilm_scratch_attn[row_start + j] = @exp(minilm_scratch_attn[row_start + j] - max_val);
                sum += minilm_scratch_attn[row_start + j];
            }

            // Normalize
            const inv_sum = 1.0 / sum;
            for (0..seq_len) |j| {
                minilm_scratch_attn[row_start + j] *= inv_sum;
            }
        }
    }

    // Compute attention output
    var attn_output: [MINILM_MAX_SEQ_LEN * MINILM_EMBED_DIM]f32 = undefined;

    for (0..seq_len) |pos| {
        // Zero output
        for (0..MINILM_EMBED_DIM) |d| {
            attn_output[pos * MINILM_EMBED_DIM + d] = 0;
        }

        for (0..MINILM_NUM_HEADS) |head| {
            const head_offset = head * MINILM_HEAD_DIM;

            for (0..seq_len) |j| {
                const attn_weight = minilm_scratch_attn[head * seq_len * seq_len + pos * seq_len + j];
                for (0..MINILM_HEAD_DIM) |d| {
                    attn_output[pos * MINILM_EMBED_DIM + head_offset + d] +=
                        attn_weight * minilm_scratch_v[j * MINILM_EMBED_DIM + head_offset + d];
                }
            }
        }

        // Output projection
        const attn_vec: *const [MINILM_EMBED_DIM]f32 = @ptrCast(attn_output[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);
        var proj_out: [MINILM_EMBED_DIM]f32 = undefined;
        minilmLinearLayer384to384(attn_vec, out_w_idx, out_b_idx, &proj_out);

        // Add to input (residual connection)
        for (0..MINILM_EMBED_DIM) |d| {
            input[pos * MINILM_EMBED_DIM + d] += proj_out[d];
        }
    }

    // Post-attention layer norm
    minilmLayerNorm(input, seq_len, ln_w_idx, ln_b_idx);
}

// MiniLM FFN block
fn minilmFFNBlock(input: []f32, seq_len: usize, layer: usize) void {
    const up_w_idx = minilm_layer_ffn_up_weight_idx[layer] orelse return;
    const up_b_idx = minilm_layer_ffn_up_bias_idx[layer] orelse return;
    const down_w_idx = minilm_layer_ffn_down_weight_idx[layer] orelse return;
    const down_b_idx = minilm_layer_ffn_down_bias_idx[layer] orelse return;
    const ln_w_idx = minilm_layer_ffn_ln_weight_idx[layer] orelse return;
    const ln_b_idx = minilm_layer_ffn_ln_bias_idx[layer] orelse return;

    for (0..seq_len) |pos| {
        const h: *const [MINILM_EMBED_DIM]f32 = @ptrCast(input[pos * MINILM_EMBED_DIM ..][0..MINILM_EMBED_DIM]);

        // Up projection: 384 -> 1536
        var mlp_hidden: [MINILM_MLP_DIM]f32 = undefined;
        minilmLinearLayer384to1536(h, up_w_idx, up_b_idx, &mlp_hidden);

        // GELU activation
        const sqrt2_inv: f32 = 1.0 / @sqrt(2.0);
        var i: usize = 0;
        while (i < MINILM_MLP_DIM) : (i += SIMD_WIDTH) {
            const x: Vec4 = mlp_hidden[i..][0..SIMD_WIDTH].*;
            var erf_val: Vec4 = undefined;
            inline for (0..SIMD_WIDTH) |k| {
                erf_val[k] = erf(x[k] * sqrt2_inv);
            }
            const half: Vec4 = @splat(0.5);
            const one: Vec4 = @splat(1.0);
            mlp_hidden[i..][0..SIMD_WIDTH].* = x * half * (one + erf_val);
        }

        // Down projection: 1536 -> 384
        var ffn_out: [MINILM_EMBED_DIM]f32 = undefined;
        minilmLinearLayer1536to384(&mlp_hidden, down_w_idx, down_b_idx, &ffn_out);

        // Residual connection
        for (0..MINILM_EMBED_DIM) |d| {
            input[pos * MINILM_EMBED_DIM + d] += ffn_out[d];
        }
    }

    // Post-FFN layer norm
    minilmLayerNorm(input, seq_len, ln_w_idx, ln_b_idx);
}

// Get MiniLM vocab token
fn minilmGetVocabToken(idx: usize) []const u8 {
    if (minilm_vocab_data == null or idx >= minilm_vocab_count) return "";
    const start = minilm_vocab_string_offsets[idx];
    const vdata = minilm_vocab_data.?;
    const len: usize = @intCast(
        @as(u64, vdata[start]) |
            (@as(u64, vdata[start + 1]) << 8) |
            (@as(u64, vdata[start + 2]) << 16) |
            (@as(u64, vdata[start + 3]) << 24) |
            (@as(u64, vdata[start + 4]) << 32) |
            (@as(u64, vdata[start + 5]) << 40) |
            (@as(u64, vdata[start + 6]) << 48) |
            (@as(u64, vdata[start + 7]) << 56),
    );
    return vdata[start + 8 .. start + 8 + len];
}

// WordPiece tokenizer for BERT
fn minilmTokenize(text: []const u8, tokens: []u32, attention_mask: []u32) usize {
    var n_tokens: usize = 0;

    // [CLS] token
    tokens[n_tokens] = 101;
    attention_mask[n_tokens] = 1;
    n_tokens += 1;

    var text_pos: usize = 0;

    while (text_pos < text.len and n_tokens < MINILM_MAX_SEQ_LEN - 1) {
        if (text[text_pos] == 0) break;

        // Skip spaces
        if (text[text_pos] == ' ') {
            text_pos += 1;
            continue;
        }

        // Find word boundary
        var word_end = text_pos;
        while (word_end < text.len and text[word_end] != ' ' and text[word_end] != 0) {
            word_end += 1;
        }

        // Process word with WordPiece
        var word_pos = text_pos;
        var is_first = true;

        while (word_pos < word_end and n_tokens < MINILM_MAX_SEQ_LEN - 1) {
            var best_len: usize = 0;
            var best_id: u32 = 100; // [UNK]

            // Try to find longest matching token
            for (0..minilm_vocab_count) |i| {
                const tok = minilmGetVocabToken(i);
                if (tok.len == 0) continue;

                // Handle ## prefix for continuation
                var tok_text = tok;
                var is_subword = false;
                if (tok.len >= 2 and tok[0] == '#' and tok[1] == '#') {
                    tok_text = tok[2..];
                    is_subword = true;
                }

                // Only match subwords if not first piece, and non-subwords if first piece
                if (is_subword == is_first) continue;

                const remaining = word_end - word_pos;
                if (tok_text.len > remaining) continue;
                if (tok_text.len <= best_len) continue;

                // Case-insensitive match
                var matches = true;
                for (0..tok_text.len) |j| {
                    var tc = tok_text[j];
                    var xc = text[word_pos + j];
                    if (tc >= 'A' and tc <= 'Z') tc = tc + 32;
                    if (xc >= 'A' and xc <= 'Z') xc = xc + 32;
                    if (tc != xc) {
                        matches = false;
                        break;
                    }
                }

                if (matches) {
                    best_len = tok_text.len;
                    best_id = @intCast(i);
                }
            }

            if (best_len > 0) {
                tokens[n_tokens] = best_id;
                attention_mask[n_tokens] = 1;
                n_tokens += 1;
                word_pos += best_len;
                is_first = false;
            } else {
                // Unknown character, skip
                word_pos += 1;
            }
        }

        text_pos = word_end;
    }

    // [SEP] token
    tokens[n_tokens] = 102;
    attention_mask[n_tokens] = 1;
    n_tokens += 1;

    // Pad
    const final_len = n_tokens;
    while (n_tokens < MINILM_MAX_SEQ_LEN) {
        tokens[n_tokens] = 0; // [PAD]
        attention_mask[n_tokens] = 0;
        n_tokens += 1;
    }

    return final_len;
}

/// Load MiniLM GGUF model
export fn minilm_load_model(size: usize) i32 {
    const model_data = minilm_model_buffer orelse return -1;
    if (size < 128) return -2;

    const data = model_data[0..size];

    // Check GGUF magic
    if (data[0] != 'G' or data[1] != 'G' or data[2] != 'U' or data[3] != 'F') {
        return -3;
    }

    const version = readU32LE(data, 4);
    if (version < 2 or version > 3) {
        return -4;
    }

    const n_tensors: usize = @intCast(readU64LE(data, 8));
    const n_kv: usize = @intCast(readU64LE(data, 16));

    var pos: usize = 24;

    // Parse KV pairs to find vocab
    for (0..n_kv) |_| {
        const key = ggufReadString(data, &pos);
        if (pos + 4 > data.len) return -5;
        const vtype = readU32LE(data, pos);
        pos += 4;

        if (strEql(key, "tokenizer.ggml.tokens")) {
            if (vtype != GGUF_TYPE_ARRAY) {
                ggufSkipValue(data, &pos, vtype);
                continue;
            }
            if (pos + 12 > data.len) return -6;
            const atype = readU32LE(data, pos);
            pos += 4;
            const alen: usize = @intCast(readU64LE(data, pos));
            pos += 8;

            if (atype == GGUF_TYPE_STRING and alen <= MINILM_VOCAB_SIZE) {
                minilm_vocab_data = data.ptr + pos;
                minilm_vocab_count = alen;

                var str_pos: u32 = 0;
                for (0..alen) |i| {
                    minilm_vocab_string_offsets[i] = str_pos;
                    const slen: u32 = @intCast(readU64LE(data, pos));
                    pos += 8;
                    str_pos += slen + 8;
                    pos += slen;
                }
                minilm_vocab_string_offsets[alen] = str_pos;
            } else {
                ggufSkipValue(data, &pos, vtype);
            }
        } else {
            ggufSkipValue(data, &pos, vtype);
        }
    }

    // Parse tensor info
    minilm_n_tensors_loaded = @min(n_tensors, MAX_TENSORS);
    for (0..minilm_n_tensors_loaded) |i| {
        const name = ggufReadString(data, &pos);
        const name_len = @min(name.len, 95);
        @memcpy(minilm_tensor_names[i][0..name_len], name[0..name_len]);
        minilm_tensor_name_lens[i] = name_len;

        if (pos + 4 > data.len) return -7;
        const n_dims = readU32LE(data, pos);
        pos += 4;
        minilm_tensor_n_dims[i] = n_dims;

        for (0..@min(n_dims, 4)) |d| {
            if (pos + 8 > data.len) return -8;
            minilm_tensor_dims[i][d] = readU64LE(data, pos);
            pos += 8;
        }

        if (pos + 12 > data.len) return -9;
        minilm_tensor_types[i] = readU32LE(data, pos);
        pos += 4;
        minilm_tensor_offsets[i] = readU64LE(data, pos);
        pos += 8;
    }

    // Data offset (aligned to 32 bytes)
    minilm_gguf_data_offset = (pos + 31) & ~@as(usize, 31);

    // Find embedding tensors
    minilm_word_emb_idx = minilmFindTensor("bert.embeddings.word_embeddings.weight");
    minilm_pos_emb_idx = minilmFindTensor("bert.embeddings.position_embeddings.weight");
    minilm_token_type_emb_idx = minilmFindTensor("bert.embeddings.token_type_embeddings.weight");
    minilm_emb_ln_weight_idx = minilmFindTensor("bert.embeddings.LayerNorm.weight");
    minilm_emb_ln_bias_idx = minilmFindTensor("bert.embeddings.LayerNorm.bias");

    // Find per-layer tensors
    for (0..MINILM_NUM_LAYERS) |layer| {
        var name_buf: [128]u8 = undefined;

        const q_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.self.query.weight", .{layer}) catch continue;
        minilm_layer_q_weight_idx[layer] = minilmFindTensor(q_w);

        const q_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.self.query.bias", .{layer}) catch continue;
        minilm_layer_q_bias_idx[layer] = minilmFindTensor(q_b);

        const k_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.self.key.weight", .{layer}) catch continue;
        minilm_layer_k_weight_idx[layer] = minilmFindTensor(k_w);

        const k_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.self.key.bias", .{layer}) catch continue;
        minilm_layer_k_bias_idx[layer] = minilmFindTensor(k_b);

        const v_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.self.value.weight", .{layer}) catch continue;
        minilm_layer_v_weight_idx[layer] = minilmFindTensor(v_w);

        const v_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.self.value.bias", .{layer}) catch continue;
        minilm_layer_v_bias_idx[layer] = minilmFindTensor(v_b);

        const out_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.output.dense.weight", .{layer}) catch continue;
        minilm_layer_out_weight_idx[layer] = minilmFindTensor(out_w);

        const out_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.output.dense.bias", .{layer}) catch continue;
        minilm_layer_out_bias_idx[layer] = minilmFindTensor(out_b);

        const attn_ln_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.output.LayerNorm.weight", .{layer}) catch continue;
        minilm_layer_attn_ln_weight_idx[layer] = minilmFindTensor(attn_ln_w);

        const attn_ln_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.attention.output.LayerNorm.bias", .{layer}) catch continue;
        minilm_layer_attn_ln_bias_idx[layer] = minilmFindTensor(attn_ln_b);

        const up_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.intermediate.dense.weight", .{layer}) catch continue;
        minilm_layer_ffn_up_weight_idx[layer] = minilmFindTensor(up_w);

        const up_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.intermediate.dense.bias", .{layer}) catch continue;
        minilm_layer_ffn_up_bias_idx[layer] = minilmFindTensor(up_b);

        const down_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.output.dense.weight", .{layer}) catch continue;
        minilm_layer_ffn_down_weight_idx[layer] = minilmFindTensor(down_w);

        const down_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.output.dense.bias", .{layer}) catch continue;
        minilm_layer_ffn_down_bias_idx[layer] = minilmFindTensor(down_b);

        const ffn_ln_w = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.output.LayerNorm.weight", .{layer}) catch continue;
        minilm_layer_ffn_ln_weight_idx[layer] = minilmFindTensor(ffn_ln_w);

        const ffn_ln_b = std.fmt.bufPrint(&name_buf, "bert.encoder.layer.{d}.output.LayerNorm.bias", .{layer}) catch continue;
        minilm_layer_ffn_ln_bias_idx[layer] = minilmFindTensor(ffn_ln_b);
    }

    // Verify essential weights
    if (minilm_word_emb_idx == null) return -10;
    if (minilm_pos_emb_idx == null) return -11;
    if (minilm_emb_ln_weight_idx == null) return -12;

    minilm_model_loaded = true;
    return 0;
}

/// Encode text to embedding
export fn minilm_encode_text(text_len: usize) i32 {
    if (!minilm_initialized) return -1;
    if (!minilm_model_loaded) return -2;
    if (text_len == 0 or text_len > minilm_text_buffer.len) return -3;

    const word_emb_idx = minilm_word_emb_idx orelse return -4;
    const pos_emb_idx = minilm_pos_emb_idx orelse return -5;
    const token_type_emb_idx = minilm_token_type_emb_idx orelse return -6;
    const emb_ln_w_idx = minilm_emb_ln_weight_idx orelse return -7;
    const emb_ln_b_idx = minilm_emb_ln_bias_idx orelse return -8;

    // Tokenize
    var tokens: [MINILM_MAX_SEQ_LEN]u32 = undefined;
    var attention_mask: [MINILM_MAX_SEQ_LEN]u32 = undefined;
    const seq_len = minilmTokenize(minilm_text_buffer[0..text_len], &tokens, &attention_mask);

    // Initialize hidden states with embeddings
    for (0..seq_len) |pos| {
        const tok_id = tokens[pos];
        for (0..MINILM_EMBED_DIM) |i| {
            // word + position + token_type embeddings
            minilm_scratch_hidden[pos * MINILM_EMBED_DIM + i] =
                minilmReadWeight(word_emb_idx, tok_id * MINILM_EMBED_DIM + i) +
                minilmReadWeight(pos_emb_idx, pos * MINILM_EMBED_DIM + i) +
                minilmReadWeight(token_type_emb_idx, i); // token_type = 0 for single sequence
        }
    }

    // Embedding layer norm
    minilmLayerNorm(&minilm_scratch_hidden, seq_len, emb_ln_w_idx, emb_ln_b_idx);

    // Run through transformer layers (BERT uses post-norm)
    for (0..MINILM_NUM_LAYERS) |layer| {
        minilmMultiHeadAttention(&minilm_scratch_hidden, seq_len, layer);
        minilmFFNBlock(&minilm_scratch_hidden, seq_len, layer);
    }

    // Mean pooling over non-padded tokens
    for (0..MINILM_EMBED_DIM) |d| {
        minilm_output_buffer[d] = 0;
    }

    var valid_tokens: f32 = 0;
    for (0..seq_len) |pos| {
        if (attention_mask[pos] == 1) {
            for (0..MINILM_EMBED_DIM) |d| {
                minilm_output_buffer[d] += minilm_scratch_hidden[pos * MINILM_EMBED_DIM + d];
            }
            valid_tokens += 1;
        }
    }

    // Average
    if (valid_tokens > 0) {
        for (0..MINILM_EMBED_DIM) |d| {
            minilm_output_buffer[d] /= valid_tokens;
        }
    }

    // L2 normalize
    var norm_sq: f32 = 0;
    for (minilm_output_buffer) |v| norm_sq += v * v;
    const norm = @sqrt(norm_sq);
    if (norm > 0) {
        for (&minilm_output_buffer) |*v| v.* /= norm;
    }

    return 0;
}

// ============================================================================
// Zstd Decompression
// ============================================================================

/// Returns the decompressed size from zstd frame header (if available).
/// This allows JS to know how much memory to allocate before decompression.
/// Returns 0 if size is unknown or error.
export fn zstd_get_decompressed_size(compressed_ptr: [*]const u8, compressed_len: usize) usize {
    if (compressed_len < 18) return 0; // Minimum frame header size

    const compressed = compressed_ptr[0..compressed_len];

    // Check magic number (0xFD2FB528 little endian)
    if (compressed[0] != 0x28 or compressed[1] != 0xB5 or
        compressed[2] != 0x2F or compressed[3] != 0xFD)
    {
        return 0;
    }

    // Frame header descriptor
    const fhd = compressed[4];
    const fcs_flag = (fhd >> 6) & 0x03; // Frame content size flag
    const single_segment = (fhd >> 5) & 0x01;
    const dict_id_flag = fhd & 0x03;

    // Calculate header size
    var offset: usize = 5;

    // Window descriptor (if not single segment)
    if (single_segment == 0) {
        offset += 1;
    }

    // Dictionary ID
    const dict_id_sizes = [_]usize{ 0, 1, 2, 4 };
    offset += dict_id_sizes[dict_id_flag];

    // Frame content size
    if (fcs_flag == 0 and single_segment == 1) {
        // 1 byte
        if (offset >= compressed_len) return 0;
        return compressed[offset];
    } else if (fcs_flag == 1) {
        // 2 bytes
        if (offset + 2 > compressed_len) return 0;
        return @as(usize, std.mem.readInt(u16, compressed[offset..][0..2], .little)) + 256;
    } else if (fcs_flag == 2) {
        // 4 bytes
        if (offset + 4 > compressed_len) return 0;
        return std.mem.readInt(u32, compressed[offset..][0..4], .little);
    } else if (fcs_flag == 3) {
        // 8 bytes
        if (offset + 8 > compressed_len) return 0;
        const size = std.mem.readInt(u64, compressed[offset..][0..8], .little);
        if (size > std.math.maxInt(usize)) return 0;
        return @intCast(size);
    }

    return 0;
}

// ============================================================================
// Lance File Writer Exports
// ============================================================================

// Writer state
var writer_buffer: ?[*]u8 = null;
var writer_buffer_len: usize = 0;
var writer_offset: usize = 0;

/// Initialize a new Lance file writer with capacity
export fn writerInit(capacity: usize) u32 {
    writer_buffer = wasmAlloc(capacity);
    if (writer_buffer == null) return 0;
    writer_buffer_len = capacity;
    writer_offset = 0;
    return 1;
}

/// Get pointer to writer buffer for JS to write column data directly
export fn writerGetBuffer() ?[*]u8 {
    return writer_buffer;
}

/// Get current write offset
export fn writerGetOffset() usize {
    return writer_offset;
}

/// Write int64 values to buffer
export fn writerWriteInt64(values: [*]const i64, count: usize) u32 {
    const buf = writer_buffer orelse return 0;
    const bytes_needed = count * 8;
    if (writer_offset + bytes_needed > writer_buffer_len) return 0;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        std.mem.writeInt(i64, buf[writer_offset..][0..8], values[i], .little);
        writer_offset += 8;
    }
    return 1;
}

/// Write int32 values to buffer
export fn writerWriteInt32(values: [*]const i32, count: usize) u32 {
    const buf = writer_buffer orelse return 0;
    const bytes_needed = count * 4;
    if (writer_offset + bytes_needed > writer_buffer_len) return 0;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        std.mem.writeInt(i32, buf[writer_offset..][0..4], values[i], .little);
        writer_offset += 4;
    }
    return 1;
}

/// Write float64 values to buffer
export fn writerWriteFloat64(values: [*]const f64, count: usize) u32 {
    const buf = writer_buffer orelse return 0;
    const bytes_needed = count * 8;
    if (writer_offset + bytes_needed > writer_buffer_len) return 0;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const bits: u64 = @bitCast(values[i]);
        std.mem.writeInt(u64, buf[writer_offset..][0..8], bits, .little);
        writer_offset += 8;
    }
    return 1;
}

/// Write float32 values to buffer
export fn writerWriteFloat32(values: [*]const f32, count: usize) u32 {
    const buf = writer_buffer orelse return 0;
    const bytes_needed = count * 4;
    if (writer_offset + bytes_needed > writer_buffer_len) return 0;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const bits: u32 = @bitCast(values[i]);
        std.mem.writeInt(u32, buf[writer_offset..][0..4], bits, .little);
        writer_offset += 4;
    }
    return 1;
}

/// Write raw bytes to buffer (for strings, vectors, etc)
export fn writerWriteBytes(data: [*]const u8, len: usize) u32 {
    const buf = writer_buffer orelse return 0;
    if (writer_offset + len > writer_buffer_len) return 0;

    @memcpy(buf[writer_offset..][0..len], data[0..len]);
    writer_offset += len;
    return 1;
}

/// Write u32 offset value (for string offsets)
export fn writerWriteOffset32(value: u32) u32 {
    const buf = writer_buffer orelse return 0;
    if (writer_offset + 4 > writer_buffer_len) return 0;

    std.mem.writeInt(u32, buf[writer_offset..][0..4], value, .little);
    writer_offset += 4;
    return 1;
}

/// Write u64 offset value
export fn writerWriteOffset64(value: u64) u32 {
    const buf = writer_buffer orelse return 0;
    if (writer_offset + 8 > writer_buffer_len) return 0;

    std.mem.writeInt(u64, buf[writer_offset..][0..8], value, .little);
    writer_offset += 8;
    return 1;
}

/// Write Lance footer (40 bytes)
export fn writerWriteFooter(
    column_meta_start: u64,
    column_meta_offsets_start_arg: u64,
    global_buff_offsets_start: u64,
    num_global_buffers: u32,
    num_cols: u32,
    major_version: u16,
    minor_version: u16,
) u32 {
    const buf = writer_buffer orelse return 0;
    if (writer_offset + 40 > writer_buffer_len) return 0;

    std.mem.writeInt(u64, buf[writer_offset..][0..8], column_meta_start, .little);
    writer_offset += 8;
    std.mem.writeInt(u64, buf[writer_offset..][0..8], column_meta_offsets_start_arg, .little);
    writer_offset += 8;
    std.mem.writeInt(u64, buf[writer_offset..][0..8], global_buff_offsets_start, .little);
    writer_offset += 8;
    std.mem.writeInt(u32, buf[writer_offset..][0..4], num_global_buffers, .little);
    writer_offset += 4;
    std.mem.writeInt(u32, buf[writer_offset..][0..4], num_cols, .little);
    writer_offset += 4;
    std.mem.writeInt(u16, buf[writer_offset..][0..2], major_version, .little);
    writer_offset += 2;
    std.mem.writeInt(u16, buf[writer_offset..][0..2], minor_version, .little);
    writer_offset += 2;
    @memcpy(buf[writer_offset..][0..4], "LANC");
    writer_offset += 4;

    return 1;
}

/// Write protobuf varint
export fn writerWriteVarint(value: u64) u32 {
    const buf = writer_buffer orelse return 0;
    var v = value;

    while (v >= 0x80) {
        if (writer_offset >= writer_buffer_len) return 0;
        buf[writer_offset] = @as(u8, @truncate(v)) | 0x80;
        writer_offset += 1;
        v >>= 7;
    }

    if (writer_offset >= writer_buffer_len) return 0;
    buf[writer_offset] = @truncate(v);
    writer_offset += 1;

    return 1;
}

/// Finalize and return the final file size
export fn writerFinalize() usize {
    return writer_offset;
}

/// Reset writer for next file
export fn writerReset() void {
    writer_offset = 0;
}

// ============================================================================
// High-Level Fragment Writer API
// ============================================================================
// Manages column schema, data offsets, and metadata writing automatically.
// JS just needs to: beginFragment -> addColumn (for each) -> endFragment

const MAX_COLUMNS = 64;

const ColumnType = enum(u8) {
    int64 = 0,
    int32 = 1,
    float64 = 2,
    float32 = 3,
    string = 4,
    bool = 5,
    vector = 6,
    uint8 = 7,
};

const ColumnInfo = struct {
    name_ptr: [*]const u8,
    name_len: usize,
    col_type: ColumnType,
    data_offset: usize,
    data_size: usize,
    row_count: usize,
    vector_dim: u32, // Only for vector type
    nullable: bool,
};

var fragment_columns: [MAX_COLUMNS]ColumnInfo = undefined;
var fragment_column_count: usize = 0;
var fragment_row_count: usize = 0;

/// Begin a new fragment (resets state)
export fn fragmentBegin(capacity: usize) u32 {
    if (writerInit(capacity) == 0) return 0;
    fragment_column_count = 0;
    fragment_row_count = 0;
    return 1;
}

/// Add a column with int64 data
export fn fragmentAddInt64Column(
    name_ptr: [*]const u8,
    name_len: usize,
    values: [*]const i64,
    count: usize,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;

    const data_offset = writer_offset;
    if (writerWriteInt64(values, count) == 0) return 0;
    const data_size = writer_offset - data_offset;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .int64,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = count,
        .vector_dim = 0,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (count > fragment_row_count) fragment_row_count = count;

    return 1;
}

/// Add a column with int32 data
export fn fragmentAddInt32Column(
    name_ptr: [*]const u8,
    name_len: usize,
    values: [*]const i32,
    count: usize,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;

    const data_offset = writer_offset;
    if (writerWriteInt32(values, count) == 0) return 0;
    const data_size = writer_offset - data_offset;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .int32,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = count,
        .vector_dim = 0,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (count > fragment_row_count) fragment_row_count = count;

    return 1;
}

/// Add a column with float64 data
export fn fragmentAddFloat64Column(
    name_ptr: [*]const u8,
    name_len: usize,
    values: [*]const f64,
    count: usize,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;

    const data_offset = writer_offset;
    if (writerWriteFloat64(values, count) == 0) return 0;
    const data_size = writer_offset - data_offset;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .float64,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = count,
        .vector_dim = 0,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (count > fragment_row_count) fragment_row_count = count;

    return 1;
}

/// Add a column with float32 data
export fn fragmentAddFloat32Column(
    name_ptr: [*]const u8,
    name_len: usize,
    values: [*]const f32,
    count: usize,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;

    const data_offset = writer_offset;
    if (writerWriteFloat32(values, count) == 0) return 0;
    const data_size = writer_offset - data_offset;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .float32,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = count,
        .vector_dim = 0,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (count > fragment_row_count) fragment_row_count = count;

    return 1;
}

/// Add a column with string data (data followed by offsets)
/// string_data: concatenated UTF-8 bytes
/// offsets: uint32 array of length count+1 (start positions + final end)
export fn fragmentAddStringColumn(
    name_ptr: [*]const u8,
    name_len: usize,
    string_data: [*]const u8,
    string_data_len: usize,
    offsets: [*]const u32,
    count: usize,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;

    const data_offset = writer_offset;

    // Write string data
    if (writerWriteBytes(string_data, string_data_len) == 0) return 0;

    // Write offsets (count + 1 values)
    const buf = writer_buffer orelse return 0;
    const offsets_bytes = (count + 1) * 4;
    if (writer_offset + offsets_bytes > writer_buffer_len) return 0;

    var i: usize = 0;
    while (i <= count) : (i += 1) {
        std.mem.writeInt(u32, buf[writer_offset..][0..4], offsets[i], .little);
        writer_offset += 4;
    }

    const data_size = writer_offset - data_offset;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .string,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = count,
        .vector_dim = 0,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (count > fragment_row_count) fragment_row_count = count;

    return 1;
}

/// Add a column with boolean data (bit-packed)
export fn fragmentAddBoolColumn(
    name_ptr: [*]const u8,
    name_len: usize,
    packed_bits: [*]const u8,
    byte_count: usize,
    row_count: usize,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;

    const data_offset = writer_offset;
    if (writerWriteBytes(packed_bits, byte_count) == 0) return 0;
    const data_size = writer_offset - data_offset;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .bool,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = row_count,
        .vector_dim = 0,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (row_count > fragment_row_count) fragment_row_count = row_count;

    return 1;
}

/// Add a column with vector data (float32 arrays, flattened)
export fn fragmentAddVectorColumn(
    name_ptr: [*]const u8,
    name_len: usize,
    values: [*]const f32,
    total_floats: usize,
    vector_dim: u32,
    nullable: bool,
) u32 {
    if (fragment_column_count >= MAX_COLUMNS) return 0;
    if (vector_dim == 0) return 0;

    const data_offset = writer_offset;
    if (writerWriteFloat32(values, total_floats) == 0) return 0;
    const data_size = writer_offset - data_offset;

    const row_count = total_floats / vector_dim;

    fragment_columns[fragment_column_count] = .{
        .name_ptr = name_ptr,
        .name_len = name_len,
        .col_type = .vector,
        .data_offset = data_offset,
        .data_size = data_size,
        .row_count = row_count,
        .vector_dim = vector_dim,
        .nullable = nullable,
    };
    fragment_column_count += 1;
    if (row_count > fragment_row_count) fragment_row_count = row_count;

    return 1;
}

/// Helper to write column metadata in protobuf format
fn writeColumnMetadata(col: *const ColumnInfo) void {
    const buf = writer_buffer orelse return;

    // Field 1: name (string) - tag = (1 << 3) | 2 = 10
    buf[writer_offset] = 10;
    writer_offset += 1;
    writeVarintInternal(col.name_len);
    @memcpy(buf[writer_offset..][0..col.name_len], col.name_ptr[0..col.name_len]);
    writer_offset += col.name_len;

    // Field 2: type (string) - tag = (2 << 3) | 2 = 18
    const type_str = switch (col.col_type) {
        .int64 => "int64",
        .int32 => "int32",
        .float64 => "float64",
        .float32 => "float32",
        .string => "string",
        .bool => "bool",
        .vector => "vector",
        .uint8 => "uint8",
    };
    buf[writer_offset] = 18;
    writer_offset += 1;
    writeVarintInternal(type_str.len);
    @memcpy(buf[writer_offset..][0..type_str.len], type_str);
    writer_offset += type_str.len;

    // Field 3: nullable (varint) - tag = (3 << 3) | 0 = 24
    buf[writer_offset] = 24;
    writer_offset += 1;
    buf[writer_offset] = if (col.nullable) 1 else 0;
    writer_offset += 1;

    // Field 4: data_offset (fixed64) - tag = (4 << 3) | 1 = 33
    buf[writer_offset] = 33;
    writer_offset += 1;
    std.mem.writeInt(u64, buf[writer_offset..][0..8], col.data_offset, .little);
    writer_offset += 8;

    // Field 5: row_count (varint) - tag = (5 << 3) | 0 = 40
    buf[writer_offset] = 40;
    writer_offset += 1;
    writeVarintInternal(col.row_count);

    // Field 6: data_size (varint) - tag = (6 << 3) | 0 = 48
    buf[writer_offset] = 48;
    writer_offset += 1;
    writeVarintInternal(col.data_size);

    // Field 7: vector_dim (varint) - tag = (7 << 3) | 0 = 56, only if vector
    if (col.col_type == .vector and col.vector_dim > 0) {
        buf[writer_offset] = 56;
        writer_offset += 1;
        writeVarintInternal(col.vector_dim);
    }
}

fn writeVarintInternal(value: usize) void {
    const buf = writer_buffer orelse return;
    var v = value;

    while (v >= 0x80) {
        buf[writer_offset] = @as(u8, @truncate(v)) | 0x80;
        writer_offset += 1;
        v >>= 7;
    }
    buf[writer_offset] = @truncate(v);
    writer_offset += 1;
}

/// Finish the fragment - writes metadata, offsets table, and footer
/// Returns final file size, or 0 on error
export fn fragmentEnd() usize {
    if (fragment_column_count == 0) return 0;
    const buf = writer_buffer orelse return 0;

    // Record where column metadata starts
    const col_meta_start = writer_offset;

    // Track each column's metadata offset
    var meta_offsets: [MAX_COLUMNS]usize = undefined;

    // Write column metadata
    for (0..fragment_column_count) |i| {
        meta_offsets[i] = writer_offset;
        writeColumnMetadata(&fragment_columns[i]);
    }

    // Record where offsets table starts
    const col_meta_offsets_start = writer_offset;

    // Write metadata offsets table (uint64 per column)
    for (0..fragment_column_count) |i| {
        std.mem.writeInt(u64, buf[writer_offset..][0..8], meta_offsets[i], .little);
        writer_offset += 8;
    }

    // Global buffer offsets (none for now)
    const global_buff_offsets_start = writer_offset;

    // Write footer (40 bytes)
    std.mem.writeInt(u64, buf[writer_offset..][0..8], col_meta_start, .little);
    writer_offset += 8;
    std.mem.writeInt(u64, buf[writer_offset..][0..8], col_meta_offsets_start, .little);
    writer_offset += 8;
    std.mem.writeInt(u64, buf[writer_offset..][0..8], global_buff_offsets_start, .little);
    writer_offset += 8;
    std.mem.writeInt(u32, buf[writer_offset..][0..4], 0, .little); // num_global_buffers
    writer_offset += 4;
    std.mem.writeInt(u32, buf[writer_offset..][0..4], @intCast(fragment_column_count), .little);
    writer_offset += 4;
    std.mem.writeInt(u16, buf[writer_offset..][0..2], 0, .little); // major version (Lance 2.0)
    writer_offset += 2;
    std.mem.writeInt(u16, buf[writer_offset..][0..2], 3, .little); // minor version
    writer_offset += 2;
    @memcpy(buf[writer_offset..][0..4], "LANC");
    writer_offset += 4;

    return writer_offset;
}

// ============================================================================
// High-Level Fragment Reader API
// ============================================================================
// Parse a Lance fragment file and provide access to columns

var reader_data: ?[*]const u8 = null;
var reader_len: usize = 0;
var reader_num_columns: u32 = 0;
var reader_column_meta_start: u64 = 0;
var reader_column_meta_offsets_start: u64 = 0;

const ReaderColumnInfo = struct {
    name: [64]u8,
    name_len: usize,
    col_type: [16]u8,
    type_len: usize,
    nullable: bool,
    data_offset: u64,
    row_count: u64,
    data_size: u64,
    vector_dim: u32,
};

var reader_columns: [MAX_COLUMNS]ReaderColumnInfo = undefined;

/// Load a fragment for reading
export fn fragmentLoad(data: [*]const u8, len: usize) u32 {
    if (len < 40) return 0;

    reader_data = data;
    reader_len = len;

    // Parse footer (last 40 bytes)
    const footer_start = len - 40;

    // Check magic
    if (data[footer_start + 36] != 'L' or
        data[footer_start + 37] != 'A' or
        data[footer_start + 38] != 'N' or
        data[footer_start + 39] != 'C')
    {
        return 0;
    }

    reader_column_meta_start = std.mem.readInt(u64, data[footer_start..][0..8], .little);
    reader_column_meta_offsets_start = std.mem.readInt(u64, data[footer_start + 8 ..][0..8], .little);
    reader_num_columns = std.mem.readInt(u32, data[footer_start + 28 ..][0..4], .little);

    if (reader_num_columns > MAX_COLUMNS) return 0;

    // Parse column metadata
    for (0..reader_num_columns) |i| {
        const offset_pos: usize = @intCast(reader_column_meta_offsets_start + i * 8);
        const meta_offset = std.mem.readInt(u64, data[offset_pos..][0..8], .little);

        const next_offset = if (i + 1 < reader_num_columns)
            std.mem.readInt(u64, data[offset_pos + 8 ..][0..8], .little)
        else
            reader_column_meta_offsets_start;

        parseColumnMeta(data, meta_offset, next_offset, &reader_columns[i]);
    }

    return 1;
}

fn parseColumnMeta(data: [*]const u8, start: u64, end: u64, info: *ReaderColumnInfo) void {
    info.* = .{
        .name = undefined,
        .name_len = 0,
        .col_type = undefined,
        .type_len = 0,
        .nullable = true,
        .data_offset = 0,
        .row_count = 0,
        .data_size = 0,
        .vector_dim = 0,
    };

    var pos: usize = @intCast(start);
    const end_pos: usize = @intCast(end);
    while (pos < end_pos) {
        const tag = data[pos];
        pos += 1;

        const field_num = tag >> 3;
        const wire_type = tag & 0x7;

        switch (field_num) {
            1 => { // name (string)
                if (wire_type == 2) {
                    const len = readVarintAtUsize(data, &pos);
                    const copy_len = @min(len, 64);
                    @memcpy(info.name[0..copy_len], data[pos..][0..copy_len]);
                    info.name_len = copy_len;
                    pos += len;
                }
            },
            2 => { // type (string)
                if (wire_type == 2) {
                    const len = readVarintAtUsize(data, &pos);
                    const copy_len = @min(len, 16);
                    @memcpy(info.col_type[0..copy_len], data[pos..][0..copy_len]);
                    info.type_len = copy_len;
                    pos += len;
                }
            },
            3 => { // nullable (varint)
                if (wire_type == 0) {
                    info.nullable = readVarintAtUsize(data, &pos) != 0;
                }
            },
            4 => { // data_offset (fixed64)
                if (wire_type == 1) {
                    info.data_offset = std.mem.readInt(u64, data[pos..][0..8], .little);
                    pos += 8;
                }
            },
            5 => { // row_count (varint)
                if (wire_type == 0) {
                    info.row_count = readVarintAtUsize(data, &pos);
                }
            },
            6 => { // data_size (varint)
                if (wire_type == 0) {
                    info.data_size = readVarintAtUsize(data, &pos);
                }
            },
            7 => { // vector_dim (varint)
                if (wire_type == 0) {
                    info.vector_dim = @intCast(readVarintAtUsize(data, &pos));
                }
            },
            else => {
                // Skip unknown field
                if (wire_type == 0) {
                    _ = readVarintAtUsize(data, &pos);
                } else if (wire_type == 1) {
                    pos += 8;
                } else if (wire_type == 2) {
                    const len = readVarintAtUsize(data, &pos);
                    pos += len;
                } else if (wire_type == 5) {
                    pos += 4;
                }
            },
        }
    }
}

fn readVarintAtUsize(data: [*]const u8, pos: *usize) usize {
    var value: usize = 0;
    var shift: u5 = 0;

    while (true) {
        const byte = data[pos.*];
        pos.* += 1;
        value |= @as(usize, byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }

    return value;
}

/// Get number of columns in loaded fragment
export fn fragmentGetColumnCount() u32 {
    return reader_num_columns;
}

/// Get row count from loaded fragment
export fn fragmentGetRowCount() u64 {
    if (reader_num_columns == 0) return 0;
    return reader_columns[0].row_count;
}

/// Get column name (returns length, writes to out_ptr)
export fn fragmentGetColumnName(col_idx: u32, out_ptr: [*]u8, max_len: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const info = &reader_columns[col_idx];
    const copy_len = @min(info.name_len, max_len);
    @memcpy(out_ptr[0..copy_len], info.name[0..copy_len]);
    return copy_len;
}

/// Get column type (returns length, writes to out_ptr)
export fn fragmentGetColumnType(col_idx: u32, out_ptr: [*]u8, max_len: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const info = &reader_columns[col_idx];
    const copy_len = @min(info.type_len, max_len);
    @memcpy(out_ptr[0..copy_len], info.col_type[0..copy_len]);
    return copy_len;
}

/// Get column vector dimension (0 if not a vector)
export fn fragmentGetColumnVectorDim(col_idx: u32) u32 {
    if (col_idx >= reader_num_columns) return 0;
    return reader_columns[col_idx].vector_dim;
}

/// Read int64 column data
export fn fragmentReadInt64(col_idx: u32, out_ptr: [*]i64, max_count: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    const count: usize = @intCast(@min(info.row_count, max_count));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const offset: usize = @intCast(info.data_offset + i * 8);
        out_ptr[i] = std.mem.readInt(i64, data[offset..][0..8], .little);
    }
    return count;
}

/// Read int32 column data
export fn fragmentReadInt32(col_idx: u32, out_ptr: [*]i32, max_count: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    const count: usize = @intCast(@min(info.row_count, max_count));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const offset: usize = @intCast(info.data_offset + i * 4);
        out_ptr[i] = std.mem.readInt(i32, data[offset..][0..4], .little);
    }
    return count;
}

/// Read float64 column data
export fn fragmentReadFloat64(col_idx: u32, out_ptr: [*]f64, max_count: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    const count: usize = @intCast(@min(info.row_count, max_count));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const offset: usize = @intCast(info.data_offset + i * 8);
        const bits = std.mem.readInt(u64, data[offset..][0..8], .little);
        out_ptr[i] = @bitCast(bits);
    }
    return count;
}

/// Read float32 column data
export fn fragmentReadFloat32(col_idx: u32, out_ptr: [*]f32, max_count: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    const count: usize = @intCast(@min(info.row_count, max_count));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const offset: usize = @intCast(info.data_offset + i * 4);
        const bits = std.mem.readInt(u32, data[offset..][0..4], .little);
        out_ptr[i] = @bitCast(bits);
    }
    return count;
}

/// Read bool column data (unpacked from bits)
export fn fragmentReadBool(col_idx: u32, out_ptr: [*]u8, max_count: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    const count: usize = @intCast(@min(info.row_count, max_count));
    const base_offset: usize = @intCast(info.data_offset);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const byte_idx = i / 8;
        const bit_idx: u3 = @intCast(i % 8);
        const byte = data[base_offset + byte_idx];
        out_ptr[i] = if ((byte & (@as(u8, 1) << bit_idx)) != 0) 1 else 0;
    }
    return count;
}

/// Get string at index - returns length, writes to out_ptr
export fn fragmentReadStringAt(col_idx: u32, row_idx: u32, out_ptr: [*]u8, max_len: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    if (row_idx >= info.row_count) return 0;

    // String layout: [string_data][offsets]
    // offsets are at the end: (row_count + 1) * 4 bytes
    const offsets_size: usize = @intCast((info.row_count + 1) * 4);
    const offsets_start: usize = @intCast(info.data_offset + info.data_size - offsets_size);
    const data_start: usize = @intCast(info.data_offset);

    const start_offset = std.mem.readInt(u32, data[offsets_start + row_idx * 4 ..][0..4], .little);
    const end_offset = std.mem.readInt(u32, data[offsets_start + (row_idx + 1) * 4 ..][0..4], .little);

    const str_len = end_offset - start_offset;
    const copy_len = @min(str_len, max_len);

    @memcpy(out_ptr[0..copy_len], data[data_start + start_offset ..][0..copy_len]);
    return copy_len;
}

/// Get string length at index (useful for allocation)
export fn fragmentGetStringLength(col_idx: u32, row_idx: u32) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    if (row_idx >= info.row_count) return 0;

    const offsets_size: usize = @intCast((info.row_count + 1) * 4);
    const offsets_start: usize = @intCast(info.data_offset + info.data_size - offsets_size);

    const start_offset = std.mem.readInt(u32, data[offsets_start + row_idx * 4 ..][0..4], .little);
    const end_offset = std.mem.readInt(u32, data[offsets_start + (row_idx + 1) * 4 ..][0..4], .little);

    return end_offset - start_offset;
}

/// Read vector at index - returns number of floats written
export fn fragmentReadVectorAt(col_idx: u32, row_idx: u32, out_ptr: [*]f32, max_floats: usize) usize {
    if (col_idx >= reader_num_columns) return 0;
    const data = reader_data orelse return 0;
    const info = &reader_columns[col_idx];

    if (row_idx >= info.row_count) return 0;
    if (info.vector_dim == 0) return 0;

    const dim = info.vector_dim;
    const copy_count: usize = @min(dim, max_floats);
    const base_offset: usize = @intCast(info.data_offset + row_idx * dim * 4);

    var i: usize = 0;
    while (i < copy_count) : (i += 1) {
        const bits = std.mem.readInt(u32, data[base_offset + i * 4 ..][0..4], .little);
        out_ptr[i] = @bitCast(bits);
    }
    return copy_count;
}
