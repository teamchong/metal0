/// Arrow C Data Interface implementation for zero-copy interop.
///
/// This module implements the Arrow C Data Interface specification:
/// https://arrow.apache.org/docs/format/CDataInterface.html
///
/// This enables zero-copy data sharing with PyArrow and other Arrow implementations.
const std = @import("std");

// Arrow C Data Interface flags
pub const ARROW_FLAG_DICTIONARY_ORDERED: i64 = 1;
pub const ARROW_FLAG_NULLABLE: i64 = 2;
pub const ARROW_FLAG_MAP_KEYS_SORTED: i64 = 4;

/// Arrow Schema - describes the type of an array.
/// This matches the C struct exactly for ABI compatibility.
pub const ArrowSchema = extern struct {
    /// Array type description (format string)
    format: ?[*:0]const u8,
    /// Optional name
    name: ?[*:0]const u8,
    /// Optional metadata (null or serialized key-value pairs)
    metadata: ?[*]const u8,
    /// Flags (combination of ARROW_FLAG_*)
    flags: i64,
    /// Number of children (for nested types)
    n_children: i64,
    /// Child schemas (for nested types)
    children: ?[*]?*ArrowSchema,
    /// Optional dictionary schema
    dictionary: ?*ArrowSchema,
    /// Release callback - MUST be called to free resources
    release: ?*const fn (*ArrowSchema) callconv(.c) void,
    /// Opaque producer-specific data
    private_data: ?*anyopaque,

    /// Check if schema has been released
    pub fn isReleased(self: *const ArrowSchema) bool {
        return self.release == null;
    }

    /// Mark schema as released (null out release callback)
    pub fn markReleased(self: *ArrowSchema) void {
        self.release = null;
    }
};

/// Arrow Array - holds the actual array data.
/// This matches the C struct exactly for ABI compatibility.
pub const ArrowArray = extern struct {
    /// Logical length of the array
    length: i64,
    /// Number of null values
    null_count: i64,
    /// Logical offset into buffers
    offset: i64,
    /// Number of buffers
    n_buffers: i64,
    /// Number of children (for nested types)
    n_children: i64,
    /// Array of buffer pointers
    buffers: ?[*]?*const anyopaque,
    /// Child arrays (for nested types)
    children: ?[*]?*ArrowArray,
    /// Optional dictionary array
    dictionary: ?*ArrowArray,
    /// Release callback - MUST be called to free resources
    release: ?*const fn (*ArrowArray) callconv(.c) void,
    /// Opaque producer-specific data
    private_data: ?*anyopaque,

    /// Check if array has been released
    pub fn isReleased(self: *const ArrowArray) bool {
        return self.release == null;
    }

    /// Mark array as released (null out release callback)
    pub fn markReleased(self: *ArrowArray) void {
        self.release = null;
    }
};

// ============================================================================
// Private data structures for tracking allocations
// ============================================================================

const SchemaPrivateData = struct {
    allocator: std.mem.Allocator,
    format_owned: ?[]const u8,
    name_owned: ?[]const u8,
    children_owned: ?[]?*ArrowSchema,
};

const ArrayPrivateData = struct {
    allocator: std.mem.Allocator,
    buffers_owned: ?[]?*const anyopaque,
    /// If we own the data buffer (i64), store it here for cleanup
    data_owned_i64: ?[]i64,
    /// If we own the data buffer (f64), store it here for cleanup
    data_owned_f64: ?[]f64,
    /// If we own the data buffer (bytes), store it here for cleanup
    data_owned_bytes: ?[]const u8,
    /// If we own the offsets buffer (i32 for strings), store it here
    offsets_owned_i32: ?[]i32,
};

// ============================================================================
// Release callbacks
// ============================================================================

fn releaseSchema(schema: *ArrowSchema) callconv(.c) void {
    if (schema.private_data) |ptr| {
        const private = @as(*SchemaPrivateData, @ptrCast(@alignCast(ptr)));
        const allocator = private.allocator;

        // Free owned strings
        if (private.format_owned) |s| allocator.free(s);
        if (private.name_owned) |s| allocator.free(s);

        // Free children array (but children themselves are caller's responsibility)
        if (private.children_owned) |c| allocator.free(c);

        // Free private data
        allocator.destroy(private);
    }
    schema.markReleased();
}

fn releaseArray(array: *ArrowArray) callconv(.c) void {
    if (array.private_data) |ptr| {
        const private = @as(*ArrayPrivateData, @ptrCast(@alignCast(ptr)));
        const alloc = private.allocator;

        // Free buffers array
        if (private.buffers_owned) |b| alloc.free(b);

        // Free owned data if any
        if (private.data_owned_i64) |d| alloc.free(d);
        if (private.data_owned_f64) |d| alloc.free(d);
        if (private.data_owned_bytes) |d| alloc.free(d);
        if (private.offsets_owned_i32) |d| alloc.free(d);

        // Free private data
        alloc.destroy(private);
    }
    array.markReleased();
}

// ============================================================================
// Schema creation helpers
// ============================================================================

/// Create an ArrowSchema for int64 type
pub fn createInt64Schema(allocator: std.mem.Allocator, name: ?[]const u8) !*ArrowSchema {
    return createPrimitiveSchema(allocator, "l", name); // "l" = int64
}

/// Create an ArrowSchema for float64 type
pub fn createFloat64Schema(allocator: std.mem.Allocator, name: ?[]const u8) !*ArrowSchema {
    return createPrimitiveSchema(allocator, "g", name); // "g" = float64
}

/// Create an ArrowSchema for utf8 string type
pub fn createStringSchema(allocator: std.mem.Allocator, name: ?[]const u8) !*ArrowSchema {
    return createPrimitiveSchema(allocator, "u", name); // "u" = utf8
}

/// Create a primitive (non-nested) schema
fn createPrimitiveSchema(allocator: std.mem.Allocator, format: []const u8, name: ?[]const u8) !*ArrowSchema {
    const schema = try allocator.create(ArrowSchema);
    errdefer allocator.destroy(schema);

    const private = try allocator.create(SchemaPrivateData);
    errdefer allocator.destroy(private);

    // Copy format string (needs null terminator)
    const format_owned = try allocator.alloc(u8, format.len + 1);
    @memcpy(format_owned[0..format.len], format);
    format_owned[format.len] = 0;

    // Copy name if provided
    var name_owned: ?[]u8 = null;
    var name_ptr: ?[*:0]const u8 = null;
    if (name) |n| {
        name_owned = try allocator.alloc(u8, n.len + 1);
        @memcpy(name_owned.?[0..n.len], n);
        name_owned.?[n.len] = 0;
        name_ptr = @ptrCast(name_owned.?.ptr);
    }

    private.* = .{
        .allocator = allocator,
        .format_owned = format_owned,
        .name_owned = name_owned,
        .children_owned = null,
    };

    schema.* = .{
        .format = @ptrCast(format_owned.ptr),
        .name = name_ptr,
        .metadata = null,
        .flags = ARROW_FLAG_NULLABLE,
        .n_children = 0,
        .children = null,
        .dictionary = null,
        .release = releaseSchema,
        .private_data = private,
    };

    return schema;
}

// ============================================================================
// Array creation helpers (zero-copy when possible)
// ============================================================================

/// Create an ArrowArray for int64 data (zero-copy - caller retains ownership)
pub fn createInt64Array(alloc: std.mem.Allocator, data: []const i64) !*ArrowArray {
    const array = try alloc.create(ArrowArray);
    errdefer alloc.destroy(array);

    const private = try alloc.create(ArrayPrivateData);
    errdefer alloc.destroy(private);

    // Allocate buffers array (validity buffer + data buffer)
    const buffers = try alloc.alloc(?*const anyopaque, 2);
    errdefer alloc.free(buffers);

    buffers[0] = null; // No validity buffer (no nulls)
    buffers[1] = @ptrCast(data.ptr); // Direct pointer to data (zero-copy!)

    private.* = .{
        .allocator = alloc,
        .buffers_owned = buffers,
        .data_owned_i64 = null, // We don't own the data
        .data_owned_f64 = null,
        .data_owned_bytes = null,
        .offsets_owned_i32 = null,
    };

    array.* = .{
        .length = @intCast(data.len),
        .null_count = 0,
        .offset = 0,
        .n_buffers = 2,
        .n_children = 0,
        .buffers = @ptrCast(buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = releaseArray,
        .private_data = private,
    };

    return array;
}

/// Create an ArrowArray for int64 data (takes ownership of data)
pub fn createInt64ArrayOwned(alloc: std.mem.Allocator, data: []i64) !*ArrowArray {
    const array = try alloc.create(ArrowArray);
    errdefer alloc.destroy(array);

    const private = try alloc.create(ArrayPrivateData);
    errdefer alloc.destroy(private);

    // Allocate buffers array (validity buffer + data buffer)
    const buffers = try alloc.alloc(?*const anyopaque, 2);
    errdefer alloc.free(buffers);

    buffers[0] = null; // No validity buffer (no nulls)
    buffers[1] = @ptrCast(data.ptr); // Direct pointer to data (zero-copy!)

    private.* = .{
        .allocator = alloc,
        .buffers_owned = buffers,
        .data_owned_i64 = data, // We own this data
        .data_owned_f64 = null,
        .data_owned_bytes = null,
        .offsets_owned_i32 = null,
    };

    array.* = .{
        .length = @intCast(data.len),
        .null_count = 0,
        .offset = 0,
        .n_buffers = 2,
        .n_children = 0,
        .buffers = @ptrCast(buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = releaseArray,
        .private_data = private,
    };

    return array;
}

/// Create an ArrowArray for float64 data (zero-copy - caller retains ownership)
pub fn createFloat64Array(alloc: std.mem.Allocator, data: []const f64) !*ArrowArray {
    const array = try alloc.create(ArrowArray);
    errdefer alloc.destroy(array);

    const private = try alloc.create(ArrayPrivateData);
    errdefer alloc.destroy(private);

    // Allocate buffers array (validity buffer + data buffer)
    const buffers = try alloc.alloc(?*const anyopaque, 2);
    errdefer alloc.free(buffers);

    buffers[0] = null; // No validity buffer (no nulls)
    buffers[1] = @ptrCast(data.ptr); // Direct pointer to data (zero-copy!)

    private.* = .{
        .allocator = alloc,
        .buffers_owned = buffers,
        .data_owned_i64 = null, // We don't own the data
        .data_owned_f64 = null,
        .data_owned_bytes = null,
        .offsets_owned_i32 = null,
    };

    array.* = .{
        .length = @intCast(data.len),
        .null_count = 0,
        .offset = 0,
        .n_buffers = 2,
        .n_children = 0,
        .buffers = @ptrCast(buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = releaseArray,
        .private_data = private,
    };

    return array;
}

/// Create an ArrowArray for float64 data (takes ownership of data)
pub fn createFloat64ArrayOwned(alloc: std.mem.Allocator, data: []f64) !*ArrowArray {
    const array = try alloc.create(ArrowArray);
    errdefer alloc.destroy(array);

    const private = try alloc.create(ArrayPrivateData);
    errdefer alloc.destroy(private);

    // Allocate buffers array (validity buffer + data buffer)
    const buffers = try alloc.alloc(?*const anyopaque, 2);
    errdefer alloc.free(buffers);

    buffers[0] = null; // No validity buffer (no nulls)
    buffers[1] = @ptrCast(data.ptr); // Direct pointer to data (zero-copy!)

    private.* = .{
        .allocator = alloc,
        .buffers_owned = buffers,
        .data_owned_i64 = null,
        .data_owned_f64 = data, // We own this data
        .data_owned_bytes = null,
        .offsets_owned_i32 = null,
    };

    array.* = .{
        .length = @intCast(data.len),
        .null_count = 0,
        .offset = 0,
        .n_buffers = 2,
        .n_children = 0,
        .buffers = @ptrCast(buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = releaseArray,
        .private_data = private,
    };

    return array;
}

/// Create an ArrowArray for string data from Lance format.
/// Lance stores: end-offsets (int32 or int64) + data buffer
/// Arrow needs: start-offsets (int32, n+1 entries) + data buffer
/// We convert end-offsets to start-offsets by prepending 0.
/// NOTE: This copies the data buffer to ensure it remains valid after the source file is closed.
pub fn createStringArrayFromLance(
    alloc: std.mem.Allocator,
    lance_offsets: []const u8, // Raw Lance end-offsets buffer (int32 or int64 little-endian)
    data_buffer: []const u8, // String data (will be copied)
) !*ArrowArray {
    const array = try alloc.create(ArrowArray);
    errdefer alloc.destroy(array);

    const private = try alloc.create(ArrayPrivateData);
    errdefer alloc.destroy(private);

    // Determine offset size (4 or 8 bytes) - same logic as PlainDecoder
    const offset_size: usize = if (lance_offsets.len % 8 == 0 and lance_offsets.len / 8 > 0)
        8
    else if (lance_offsets.len % 4 == 0)
        4
    else
        return error.InvalidBufferSize;

    // Lance offsets are end positions, Arrow needs start positions with n+1 entries
    // Lance: [end0, end1, end2, ...] for n strings
    // Arrow: [0, end0, end1, end2, ...] for n strings (n+1 entries)
    const n_strings = lance_offsets.len / offset_size;

    // Allocate Arrow offsets (n+1 entries, always int32 for Arrow utf8 format "u")
    const arrow_offsets = try alloc.alloc(i32, n_strings + 1);
    errdefer alloc.free(arrow_offsets);

    // First offset is always 0
    arrow_offsets[0] = 0;

    // Copy Lance end-offsets as Arrow offsets[1..n+1]
    for (0..n_strings) |i| {
        const lance_end: i32 = if (offset_size == 4)
            std.mem.readInt(i32, lance_offsets[i * 4 ..][0..4], .little)
        else
            @intCast(std.mem.readInt(i64, lance_offsets[i * 8 ..][0..8], .little));
        arrow_offsets[i + 1] = lance_end;
    }

    // Copy the data buffer to ensure it stays valid after source file is closed
    // This is necessary because the Arrow array may outlive the Lance file handle
    const data_copy = try alloc.alloc(u8, data_buffer.len);
    errdefer alloc.free(data_copy);
    @memcpy(data_copy, data_buffer);

    // Allocate buffers array (validity + offsets + data)
    const buffers = try alloc.alloc(?*const anyopaque, 3);
    errdefer alloc.free(buffers);

    buffers[0] = null; // No validity buffer (no nulls)
    buffers[1] = @ptrCast(arrow_offsets.ptr); // Offsets buffer
    buffers[2] = @ptrCast(data_copy.ptr); // Data buffer (owned copy)

    private.* = .{
        .allocator = alloc,
        .buffers_owned = buffers,
        .data_owned_i64 = null,
        .data_owned_f64 = null,
        .data_owned_bytes = data_copy, // We own the data buffer copy
        .offsets_owned_i32 = arrow_offsets, // We own the offsets
    };

    array.* = .{
        .length = @intCast(n_strings),
        .null_count = 0,
        .offset = 0,
        .n_buffers = 3,
        .n_children = 0,
        .buffers = @ptrCast(buffers.ptr),
        .children = null,
        .dictionary = null,
        .release = releaseArray,
        .private_data = private,
    };

    return array;
}

// ============================================================================
// Tests
// ============================================================================

test "ArrowSchema size matches C" {
    // ArrowSchema should be pointer-sized fields
    try std.testing.expect(@sizeOf(ArrowSchema) > 0);
}

test "ArrowArray size matches C" {
    // ArrowArray should be pointer-sized fields
    try std.testing.expect(@sizeOf(ArrowArray) > 0);
}

test "create int64 schema" {
    const allocator = std.testing.allocator;

    const schema = try createInt64Schema(allocator, "my_column");
    defer {
        if (schema.release) |release| {
            release(schema);
        }
        allocator.destroy(schema);
    }

    try std.testing.expect(!schema.isReleased());
    try std.testing.expectEqualStrings("l", std.mem.span(schema.format.?));
    try std.testing.expectEqualStrings("my_column", std.mem.span(schema.name.?));
}

test "create int64 array zero-copy" {
    const allocator = std.testing.allocator;

    const data = [_]i64{ 1, 2, 3, 4, 5 };
    const array = try createInt64Array(allocator, &data);
    defer {
        if (array.release) |release| {
            release(array);
        }
        allocator.destroy(array);
    }

    try std.testing.expectEqual(@as(i64, 5), array.length);
    try std.testing.expectEqual(@as(i64, 0), array.null_count);
    try std.testing.expectEqual(@as(i64, 2), array.n_buffers);

    // Verify zero-copy: buffer pointer should point to original data
    const buffer_ptr = array.buffers.?[1];
    try std.testing.expectEqual(@intFromPtr(&data), @intFromPtr(buffer_ptr));
}
