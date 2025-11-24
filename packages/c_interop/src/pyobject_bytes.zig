/// PyBytesObject - Immutable Byte String Implementation
///
/// Implements CPython-compatible bytes object with:
/// - Immutable byte array
/// - Cached hash value
/// - Sequence protocol
/// - Concatenation and formatting

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// ============================================================================
/// INTERNAL BYTES STRUCTURE
/// ============================================================================

/// Internal bytes object with flexible array
/// Layout: PyBytesObject + data bytes + null terminator
const InternalBytesObject = struct {
    base: cpython.PyBytesObject,
    // Data follows immediately after
};

/// Get pointer to data array
fn getData(bytes: *cpython.PyBytesObject) [*]u8 {
    const base_ptr = @intFromPtr(bytes);
    const data_ptr = base_ptr + @sizeOf(cpython.PyBytesObject);
    return @ptrFromInt(data_ptr);
}

/// Get data as slice
fn getDataSlice(bytes: *cpython.PyBytesObject) []u8 {
    const len: usize = @intCast(bytes.ob_base.ob_size);
    return getData(bytes)[0..len];
}

/// ============================================================================
/// SEQUENCE PROTOCOL
/// ============================================================================

fn bytes_length(obj: *cpython.PyObject) callconv(.c) isize {
    const bytes = @as(*cpython.PyBytesObject, @ptrCast(obj));
    return bytes.ob_base.ob_size;
}

fn bytes_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const bytes_a = @as(*cpython.PyBytesObject, @ptrCast(a));
    const bytes_b = @as(*cpython.PyBytesObject, @ptrCast(b));

    const len_a: usize = @intCast(bytes_a.ob_base.ob_size);
    const len_b: usize = @intCast(bytes_b.ob_base.ob_size);
    const total_len = len_a + len_b;

    // Create new bytes object
    const result = PyBytes_FromStringAndSize(null, @intCast(total_len));
    if (result == null) return null;

    const result_bytes = @as(*cpython.PyBytesObject, @ptrCast(result.?));
    const result_data = getData(result_bytes);

    // Copy data
    const data_a = getData(bytes_a);
    const data_b = getData(bytes_b);

    @memcpy(result_data[0..len_a], data_a[0..len_a]);
    @memcpy(result_data[len_a..total_len], data_b[0..len_b]);

    return result;
}

fn bytes_repeat(obj: *cpython.PyObject, count: isize) callconv(.c) ?*cpython.PyObject {
    if (count < 0) return PyBytes_FromStringAndSize(null, 0);

    const bytes_obj = @as(*cpython.PyBytesObject, @ptrCast(obj));
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);
    const ucount: usize = @intCast(count);
    const total_len = len * ucount;

    // Create new bytes object
    const result = PyBytes_FromStringAndSize(null, @intCast(total_len));
    if (result == null) return null;

    const result_bytes = @as(*cpython.PyBytesObject, @ptrCast(result.?));
    const result_data = getData(result_bytes);
    const src_data = getData(bytes_obj);

    // Repeat data
    var i: usize = 0;
    while (i < ucount) : (i += 1) {
        @memcpy(result_data[i * len .. (i + 1) * len], src_data[0..len]);
    }

    return result;
}

fn bytes_item(obj: *cpython.PyObject, index: isize) callconv(.c) ?*cpython.PyObject {
    const bytes_obj = @as(*cpython.PyBytesObject, @ptrCast(obj));
    const len = bytes_obj.ob_base.ob_size;

    if (index < 0 or index >= len) return null;

    const data = getData(bytes_obj);
    const uindex: usize = @intCast(index);

    // Return single-byte bytes object
    return PyBytes_FromStringAndSize(@ptrCast(&data[uindex]), 1);
}

/// Sequence protocol methods table
const PySequenceMethods = extern struct {
    sq_length: ?*const fn (*cpython.PyObject) callconv(.c) isize,
    sq_concat: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    sq_repeat: ?*const fn (*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject,
    sq_item: ?*const fn (*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject,
    was_sq_slice: ?*anyopaque,
    sq_ass_item: ?*const fn (*cpython.PyObject, isize, *cpython.PyObject) callconv(.c) c_int,
    was_sq_ass_slice: ?*anyopaque,
    sq_contains: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) c_int,
    sq_inplace_concat: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    sq_inplace_repeat: ?*const fn (*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject,
};

var bytes_as_sequence = PySequenceMethods{
    .sq_length = bytes_length,
    .sq_concat = bytes_concat,
    .sq_repeat = bytes_repeat,
    .sq_item = bytes_item,
    .was_sq_slice = null,
    .sq_ass_item = null, // Immutable
    .was_sq_ass_slice = null,
    .sq_contains = null, // TODO
    .sq_inplace_concat = null, // Immutable
    .sq_inplace_repeat = null, // Immutable
};

/// ============================================================================
/// PYBYTES_TYPE OBJECT
/// ============================================================================

fn bytes_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const bytes_obj = @as(*cpython.PyBytesObject, @ptrCast(obj));
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);

    // Free the entire allocation (struct + data)
    const total_size = @sizeOf(cpython.PyBytesObject) + len + 1;
    const ptr = @as([*]u8, @ptrCast(bytes_obj));
    allocator.free(ptr[0..total_size]);
}

var PyBytes_Type = cpython.PyTypeObject{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1000000, // Immortal
            .ob_type = undefined,
        },
        .ob_size = 0,
    },
    .tp_name = "bytes",
    .tp_basicsize = @sizeOf(cpython.PyBytesObject),
    .tp_itemsize = 1, // Variable-size items
    .tp_dealloc = bytes_dealloc,
    .tp_repr = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_number = null,
    .tp_as_sequence = @ptrCast(&bytes_as_sequence),
};

/// ============================================================================
/// CREATION FUNCTIONS
/// ============================================================================

pub export fn PyBytes_FromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const len = std.mem.len(str);
    return PyBytes_FromStringAndSize(str, @intCast(len));
}

export fn PyBytes_FromStringAndSize(str: ?[*]const u8, len: isize) callconv(.c) ?*cpython.PyObject {
    if (len < 0) return null;

    const ulen: usize = @intCast(len);

    // Allocate bytes object + data + null terminator
    const total_size = @sizeOf(cpython.PyBytesObject) + ulen + 1;
    const memory = allocator.alloc(u8, total_size) catch return null;

    const bytes = @as(*cpython.PyBytesObject, @ptrCast(@alignCast(memory.ptr)));

    bytes.* = cpython.PyBytesObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyBytes_Type,
            },
            .ob_size = len,
        },
        .ob_shash = -1, // Not computed yet
    };

    // Copy data if provided
    const data_ptr = getData(bytes);
    if (str) |s| {
        @memcpy(data_ptr[0..ulen], s[0..ulen]);
    } else {
        // Zero-initialize if no source provided
        @memset(data_ptr[0..ulen], 0);
    }

    // Null terminate
    data_ptr[ulen] = 0;

    return @ptrCast(&bytes.ob_base.ob_base);
}

export fn PyBytes_FromFormat(format: [*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    // Simple implementation - just copy format string for now
    // Full implementation would need varargs handling
    _ = format;
    return PyBytes_FromString("TODO: PyBytes_FromFormat");
}

export fn PyBytes_Concat(bytes_ptr: *?*cpython.PyObject, newpart: *cpython.PyObject) callconv(.c) void {
    const old = bytes_ptr.* orelse return;

    const result = bytes_concat(old, newpart);
    if (result == null) {
        // On error, set to null
        bytes_ptr.* = null;
        return;
    }

    // Replace old with new
    bytes_ptr.* = result;
}

export fn PyBytes_ConcatAndDel(bytes_ptr: *?*cpython.PyObject, newpart: ?*cpython.PyObject) callconv(.c) void {
    if (newpart == null) {
        bytes_ptr.* = null;
        return;
    }

    PyBytes_Concat(bytes_ptr, newpart.?);

    // Free newpart (simplified - should decref)
    const new_bytes = @as(*cpython.PyBytesObject, @ptrCast(newpart.?));
    bytes_dealloc(&new_bytes.ob_base.ob_base);
}

/// ============================================================================
/// ACCESS FUNCTIONS
/// ============================================================================

pub export fn PyBytes_AsString(obj: *cpython.PyObject) callconv(.c) [*:0]const u8 {
    const bytes = @as(*cpython.PyBytesObject, @ptrCast(obj));
    const data = getData(bytes);
    return @ptrCast(data);
}

export fn PyBytes_AsStringAndSize(obj: *cpython.PyObject, buffer: *[*]const u8, length: *isize) callconv(.c) c_int {
    const bytes = @as(*cpython.PyBytesObject, @ptrCast(obj));

    buffer.* = getData(bytes);
    length.* = bytes.ob_base.ob_size;

    return 0;
}

pub export fn PyBytes_Size(obj: *cpython.PyObject) callconv(.c) isize {
    const bytes = @as(*cpython.PyBytesObject, @ptrCast(obj));
    return bytes.ob_base.ob_size;
}

export fn PyBytes_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    // Macro-like accessor - same as PyBytes_Size
    return PyBytes_Size(obj);
}

/// ============================================================================
/// TYPE CHECKING
/// ============================================================================

pub export fn PyBytes_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyBytes_Type) 1 else 0;
}

export fn PyBytes_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyBytes_Type) 1 else 0;
}

/// ============================================================================
/// UTILITY FUNCTIONS
/// ============================================================================

export fn PyBytes_Repr(obj: *cpython.PyObject, smartquotes: c_int) callconv(.c) ?*cpython.PyObject {
    _ = smartquotes;

    const bytes_obj = @as(*cpython.PyBytesObject, @ptrCast(obj));
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);
    const data = getData(bytes_obj);

    // Simple repr: b'...'
    const prefix = "b'";
    const suffix = "'";
    const total = prefix.len + len + suffix.len;

    const result = PyBytes_FromStringAndSize(null, @intCast(total));
    if (result == null) return null;

    const result_bytes = @as(*cpython.PyBytesObject, @ptrCast(result.?));
    const result_data = getData(result_bytes);

    // Build repr
    @memcpy(result_data[0..prefix.len], prefix);
    @memcpy(result_data[prefix.len .. prefix.len + len], data[0..len]);
    @memcpy(result_data[prefix.len + len ..][0..suffix.len], suffix);

    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyBytes creation and access" {
    const bytes = PyBytes_FromString("hello");
    try std.testing.expect(bytes != null);

    const size = PyBytes_Size(bytes.?);
    try std.testing.expectEqual(@as(isize, 5), size);

    const str = PyBytes_AsString(bytes.?);
    try std.testing.expectEqualStrings("hello", std.mem.span(str));
}

test "PyBytes concatenation" {
    const a = PyBytes_FromString("hello");
    const b = PyBytes_FromString(" world");

    const result = bytes_concat(a.?, b.?);
    try std.testing.expect(result != null);

    const str = PyBytes_AsString(result.?);
    try std.testing.expectEqualStrings("hello world", std.mem.span(str));
}

test "PyBytes repeat" {
    const bytes = PyBytes_FromString("ab");
    const result = bytes_repeat(bytes.?, 3);

    try std.testing.expect(result != null);

    const str = PyBytes_AsString(result.?);
    try std.testing.expectEqualStrings("ababab", std.mem.span(str));
}

test "PyBytes empty" {
    const empty = PyBytes_FromStringAndSize(null, 0);
    try std.testing.expect(empty != null);

    const size = PyBytes_Size(empty.?);
    try std.testing.expectEqual(@as(isize, 0), size);
}
