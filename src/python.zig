/// Python C API bindings for LanceQL
///
/// This module exports C-compatible functions for use with Python ctypes.
/// All exported functions follow C calling conventions and use C-compatible types.
///
/// Zero-copy Arrow support:
/// - Use lance_export_column_arrow() to get Arrow C Data Interface pointers
/// - Python can import via pyarrow.Array._import_from_c()
const std = @import("std");
const Table = @import("lanceql.table").Table;
const arrow_c = @import("arrow_c");

/// Global allocator for Python bindings
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

/// Track allocated strings per handle for proper cleanup
var tracked_strings = std.AutoHashMap(*Handle, std.ArrayListUnmanaged([]const u8)).init(allocator);

/// Opaque handle for Python (represents a Table)
pub const Handle = opaque {};

/// Convert Table pointer to Handle
fn tableToHandle(table: *Table) *Handle {
    return @ptrCast(table);
}

/// Convert Handle to Table pointer
fn handleToTable(handle: *Handle) *Table {
    return @ptrCast(@alignCast(handle));
}

/// Track a string allocation for later cleanup
fn trackString(handle: *Handle, str: []const u8) !void {
    const gop = try tracked_strings.getOrPut(handle);
    if (!gop.found_existing) {
        gop.value_ptr.* = std.ArrayListUnmanaged([]const u8){};
    }
    try gop.value_ptr.append(allocator, str);
}

/// Free all tracked strings for a handle
fn freeTrackedStrings(handle: *Handle) void {
    if (tracked_strings.fetchRemove(handle)) |kv| {
        var list = kv.value;
        for (list.items) |str| {
            allocator.free(str);
        }
        list.deinit(allocator);
    }
}

// ============================================================================
// File Operations
// ============================================================================

/// Open a Lance file from a byte buffer
/// Returns null on error
export fn lance_open_memory(data: [*]const u8, len: usize) ?*Handle {
    const slice = data[0..len];
    const table = allocator.create(Table) catch return null;
    table.* = Table.init(allocator, slice) catch {
        allocator.destroy(table);
        return null;
    };
    return tableToHandle(table);
}

/// Close a Lance file and free resources
export fn lance_close(handle: *Handle) void {
    // Free any tracked strings first
    freeTrackedStrings(handle);

    const table = handleToTable(handle);
    table.deinit();
    allocator.destroy(table);
}

// ============================================================================
// Metadata Access
// ============================================================================

/// Get number of columns
export fn lance_column_count(handle: *Handle) u32 {
    const table = handleToTable(handle);
    return table.numColumns();
}

/// Get row count for a column
export fn lance_row_count(handle: *Handle, col_idx: u32) u64 {
    const table = handleToTable(handle);
    return table.rowCount(col_idx) catch 0;
}

/// Get column name
/// Writes to buf, returns bytes written (0 on error)
export fn lance_column_name(handle: *Handle, col_idx: u32, buf: [*]u8, buf_len: usize) usize {
    const table = handleToTable(handle);

    // Get column names
    const names = table.columnNames() catch return 0;
    defer allocator.free(names);

    if (col_idx >= names.len) return 0;

    const name = names[col_idx];
    const len = @min(name.len, buf_len);
    @memcpy(buf[0..len], name[0..len]);
    return len;
}

/// Get column type (logical type string)
/// Writes to buf, returns bytes written (0 on error)
export fn lance_column_type(handle: *Handle, col_idx: u32, buf: [*]u8, buf_len: usize) usize {
    const table = handleToTable(handle);

    const field = table.getField(col_idx) orelse return 0;
    const type_str = field.logical_type;

    const len = @min(type_str.len, buf_len);
    @memcpy(buf[0..len], type_str[0..len]);
    return len;
}

// ============================================================================
// Column Reading (Legacy copy-based API - use Arrow exports for zero-copy)
// ============================================================================

/// Read string column (copy-based, no Arrow string export yet)
/// Returns number of strings read (0 on error)
/// out_strings should be pre-allocated array of string pointers
/// out_lengths should be pre-allocated array for string lengths
/// NOTE: The returned string pointers are valid until lance_close() is called.
export fn lance_read_string(
    handle: *Handle,
    col_idx: u32,
    out_strings: [*][*]const u8,
    out_lengths: [*]usize,
    max_count: usize,
) usize {
    const table = handleToTable(handle);

    const strings = table.readStringColumn(col_idx) catch return 0;
    defer allocator.free(strings);

    const count = @min(strings.len, max_count);
    for (0..count) |i| {
        // Duplicate string and track for cleanup on lance_close()
        const duped = allocator.dupe(u8, strings[i]) catch return i;
        trackString(handle, duped) catch {
            allocator.free(duped);
            return i;
        };
        out_strings[i] = duped.ptr;
        out_lengths[i] = duped.len;
    }

    return count;
}

// ============================================================================
// Version Info
// ============================================================================

/// Get library version string
/// Returns length of version string written to buf
export fn lance_version(buf: [*]u8, buf_len: usize) usize {
    const version = "0.1.0";
    const len = @min(version.len, buf_len);
    @memcpy(buf[0..len], version[0..len]);
    return len;
}

// ============================================================================
// Arrow C Data Interface - Zero-Copy Exports
// ============================================================================

/// Export a column as Arrow arrays (zero-copy when possible).
/// Returns 1 on success, 0 on error.
/// The schema and array pointers are written to out_schema and out_array.
/// Caller is responsible for calling the release callbacks on both.
export fn lance_export_int64_column(
    handle: *Handle,
    col_idx: u32,
    out_schema: *?*arrow_c.ArrowSchema,
    out_array: *?*arrow_c.ArrowArray,
) u32 {
    const table = handleToTable(handle);

    // Get column name for schema
    const names = table.columnNames() catch return 0;
    defer allocator.free(names);

    if (col_idx >= names.len) return 0;
    const col_name = names[col_idx];

    // Create schema
    const schema = arrow_c.createInt64Schema(allocator, col_name) catch return 0;
    errdefer {
        if (schema.release) |release| release(schema);
        allocator.destroy(schema);
    }

    // Read column data
    const data = table.readInt64Column(col_idx) catch return 0;
    // Note: data is owned by us, but we pass ownership to the ArrowArray

    // Create array (zero-copy - points directly to data)
    const array = arrow_c.createInt64ArrayOwned(allocator, data) catch {
        allocator.free(data);
        return 0;
    };

    out_schema.* = schema;
    out_array.* = array;
    return 1;
}

/// Export a float64 column as Arrow arrays (zero-copy when possible).
export fn lance_export_float64_column(
    handle: *Handle,
    col_idx: u32,
    out_schema: *?*arrow_c.ArrowSchema,
    out_array: *?*arrow_c.ArrowArray,
) u32 {
    const table = handleToTable(handle);

    // Get column name for schema
    const names = table.columnNames() catch return 0;
    defer allocator.free(names);

    if (col_idx >= names.len) return 0;
    const col_name = names[col_idx];

    // Create schema
    const schema = arrow_c.createFloat64Schema(allocator, col_name) catch return 0;
    errdefer {
        if (schema.release) |release| release(schema);
        allocator.destroy(schema);
    }

    // Read column data
    const data = table.readFloat64Column(col_idx) catch return 0;

    // Create array (zero-copy - points directly to data)
    const array = arrow_c.createFloat64ArrayOwned(allocator, data) catch {
        allocator.free(data);
        return 0;
    };

    out_schema.* = schema;
    out_array.* = array;
    return 1;
}

/// Release an Arrow schema (call the release callback and free)
export fn lance_release_schema(schema: *arrow_c.ArrowSchema) void {
    if (schema.release) |release| {
        release(schema);
    }
    allocator.destroy(schema);
}

/// Release an Arrow array (call the release callback and free)
export fn lance_release_array(array: *arrow_c.ArrowArray) void {
    if (array.release) |release| {
        release(array);
    }
    allocator.destroy(array);
}

/// Export a string column as Arrow arrays.
/// String data buffer is zero-copy, only offsets need conversion.
export fn lance_export_string_column(
    handle: *Handle,
    col_idx: u32,
    out_schema: *?*arrow_c.ArrowSchema,
    out_array: *?*arrow_c.ArrowArray,
) u32 {
    const table = handleToTable(handle);

    // Get column name for schema
    const names = table.columnNames() catch return 0;
    defer allocator.free(names);

    if (col_idx >= names.len) return 0;
    const col_name = names[col_idx];

    // Create schema
    const schema = arrow_c.createStringSchema(allocator, col_name) catch return 0;
    errdefer {
        if (schema.release) |release| release(schema);
        allocator.destroy(schema);
    }

    // Get raw buffers from Lance file
    const buffers = table.getStringColumnBuffers(col_idx) catch return 0;
    const offsets_buffer = buffers.offsets;
    const data_buffer = buffers.data;

    // Create Arrow array (offsets converted, data zero-copy)
    const array = arrow_c.createStringArrayFromLance(allocator, offsets_buffer, data_buffer) catch return 0;

    out_schema.* = schema;
    out_array.* = array;
    return 1;
}
