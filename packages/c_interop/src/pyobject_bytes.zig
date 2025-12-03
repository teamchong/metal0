/// PyBytesObject - Immutable Byte String Implementation
///
/// EXACT CPython 3.12 memory layout for binary compatibility.
///
/// Reference: cpython/Include/cpython/bytesobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export type from cpython_object.zig for exact CPython layout
pub const PyBytesObject = cpython.PyBytesObject;

// ============================================================================
// SEQUENCE PROTOCOL
// ============================================================================

fn bytes_length(obj: *cpython.PyObject) callconv(.c) isize {
    const bytes: *PyBytesObject = @ptrCast(@alignCast(obj));
    return bytes.ob_base.ob_size;
}

fn bytes_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyBytes_Check(a) == 0 or PyBytes_Check(b) == 0) return null;

    const bytes_a: *PyBytesObject = @ptrCast(@alignCast(a));
    const bytes_b: *PyBytesObject = @ptrCast(@alignCast(b));

    const len_a: usize = @intCast(bytes_a.ob_base.ob_size);
    const len_b: usize = @intCast(bytes_b.ob_base.ob_size);
    const total_len = len_a + len_b;

    const result = PyBytes_FromStringAndSize(null, @intCast(total_len));
    if (result == null) return null;

    const result_bytes: *PyBytesObject = @ptrCast(@alignCast(result.?));
    const result_data: [*]u8 = @ptrCast(&result_bytes.ob_sval);
    const data_a: [*]const u8 = @ptrCast(&bytes_a.ob_sval);
    const data_b: [*]const u8 = @ptrCast(&bytes_b.ob_sval);

    @memcpy(result_data[0..len_a], data_a[0..len_a]);
    @memcpy(result_data[len_a..total_len], data_b[0..len_b]);

    return result;
}

fn bytes_repeat(obj: *cpython.PyObject, count: isize) callconv(.c) ?*cpython.PyObject {
    if (count < 0) return PyBytes_FromStringAndSize(null, 0);

    const bytes_obj: *PyBytesObject = @ptrCast(@alignCast(obj));
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);
    const ucount: usize = @intCast(count);
    const total_len = len * ucount;

    const result = PyBytes_FromStringAndSize(null, @intCast(total_len));
    if (result == null) return null;

    const result_bytes: *PyBytesObject = @ptrCast(@alignCast(result.?));
    const result_data: [*]u8 = @ptrCast(&result_bytes.ob_sval);
    const src_data: [*]const u8 = @ptrCast(&bytes_obj.ob_sval);

    var i: usize = 0;
    while (i < ucount) : (i += 1) {
        @memcpy(result_data[i * len .. (i + 1) * len], src_data[0..len]);
    }

    return result;
}

fn bytes_item(obj: *cpython.PyObject, index: isize) callconv(.c) ?*cpython.PyObject {
    const bytes_obj: *PyBytesObject = @ptrCast(@alignCast(obj));
    const len = bytes_obj.ob_base.ob_size;

    if (index < 0 or index >= len) return null;

    const data: [*]const u8 = @ptrCast(&bytes_obj.ob_sval);
    const uindex: usize = @intCast(index);

    // Return single-byte bytes object
    return PyBytes_FromStringAndSize(@ptrCast(&data[uindex]), 1);
}

/// Sequence protocol methods table
var bytes_as_sequence: cpython.PySequenceMethods = .{
    .sq_length = bytes_length,
    .sq_concat = bytes_concat,
    .sq_repeat = bytes_repeat,
    .sq_item = bytes_item,
    .sq_ass_item = null, // Immutable
    .sq_contains = null, // TODO
    .sq_inplace_concat = null, // Immutable
    .sq_inplace_repeat = null, // Immutable
};

// ============================================================================
// PYBYTES_TYPE OBJECT
// ============================================================================

fn bytes_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const bytes_obj: *PyBytesObject = @ptrCast(@alignCast(obj));
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);

    // Free the entire allocation (struct + extra data)
    // Layout: PyBytesObject base (has ob_sval[1]) + extra bytes
    const base_size = @sizeOf(PyBytesObject);
    const extra_bytes: usize = if (len > 0) len else 0; // len includes space for \0 if needed
    const total_size = base_size + extra_bytes;

    const memory: [*]u8 = @ptrCast(@alignCast(bytes_obj));
    allocator.free(memory[0..total_size]);
}

fn bytes_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const bytes_obj: *PyBytesObject = @ptrCast(@alignCast(obj));

    // Return cached hash if available
    if (bytes_obj.ob_shash != -1) {
        return bytes_obj.ob_shash;
    }

    // Compute hash
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);
    const data: [*]const u8 = @ptrCast(&bytes_obj.ob_sval);

    var hash: u64 = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        hash = hash *% 31 +% data[i];
    }

    const result: isize = @intCast(hash);
    bytes_obj.ob_shash = result;
    return result;
}

pub var PyBytes_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "bytes",
    .tp_basicsize = @sizeOf(PyBytesObject),
    .tp_itemsize = 1, // Variable-size items
    .tp_dealloc = bytes_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = &bytes_as_sequence,
    .tp_as_mapping = null,
    .tp_hash = bytes_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BYTES_SUBCLASS,
    .tp_doc = "bytes(iterable_of_ints) -> bytes",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

// ============================================================================
// CREATION FUNCTIONS
// ============================================================================

pub export fn PyBytes_FromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const len = std.mem.len(str);
    return PyBytes_FromStringAndSize(str, @intCast(len));
}

pub export fn PyBytes_FromStringAndSize(str: ?[*]const u8, len: isize) callconv(.c) ?*cpython.PyObject {
    if (len < 0) return null;

    const ulen: usize = @intCast(len);

    // Allocate bytes object + extra data
    // PyBytesObject already has ob_sval[1], so we need len more bytes (not len+1)
    const base_size = @sizeOf(PyBytesObject);
    const extra_bytes: usize = if (ulen > 0) ulen else 0;
    const total_size = base_size + extra_bytes;

    const memory = allocator.alloc(u8, total_size) catch return null;
    const bytes: *PyBytesObject = @ptrCast(@alignCast(memory.ptr));

    bytes.ob_base.ob_base.ob_refcnt = 1;
    bytes.ob_base.ob_base.ob_type = &PyBytes_Type;
    bytes.ob_base.ob_size = len;
    bytes.ob_shash = -1; // Not computed yet

    // Copy data if provided
    const data_ptr: [*]u8 = @ptrCast(&bytes.ob_sval);
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
    _ = format;
    return PyBytes_FromString("TODO: PyBytes_FromFormat");
}

export fn PyBytes_Concat(bytes_ptr: *?*cpython.PyObject, newpart: *cpython.PyObject) callconv(.c) void {
    const old = bytes_ptr.* orelse return;

    const result = bytes_concat(old, newpart);
    if (result == null) {
        bytes_ptr.* = null;
        return;
    }

    bytes_ptr.* = result;
}

export fn PyBytes_ConcatAndDel(bytes_ptr: *?*cpython.PyObject, newpart: ?*cpython.PyObject) callconv(.c) void {
    if (newpart == null) {
        bytes_ptr.* = null;
        return;
    }

    PyBytes_Concat(bytes_ptr, newpart.?);

    // Decref newpart
    newpart.?.ob_refcnt -= 1;
    // TODO: Check if refcnt == 0 and deallocate
}

// ============================================================================
// ACCESS FUNCTIONS
// ============================================================================

pub export fn PyBytes_AsString(obj: *cpython.PyObject) callconv(.c) [*:0]const u8 {
    const bytes: *PyBytesObject = @ptrCast(@alignCast(obj));
    return @ptrCast(&bytes.ob_sval);
}

export fn PyBytes_AsStringAndSize(obj: *cpython.PyObject, buffer: *[*]const u8, length: *isize) callconv(.c) c_int {
    const bytes: *PyBytesObject = @ptrCast(@alignCast(obj));

    buffer.* = @ptrCast(&bytes.ob_sval);
    length.* = bytes.ob_base.ob_size;

    return 0;
}

pub export fn PyBytes_Size(obj: *cpython.PyObject) callconv(.c) isize {
    const bytes: *PyBytesObject = @ptrCast(@alignCast(obj));
    return bytes.ob_base.ob_size;
}

export fn PyBytes_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    return PyBytes_Size(obj);
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

pub export fn PyBytes_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return if ((flags & cpython.Py_TPFLAGS_BYTES_SUBCLASS) != 0) 1 else 0;
}

export fn PyBytes_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyBytes_Type) 1 else 0;
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

export fn PyBytes_Repr(obj: *cpython.PyObject, smartquotes: c_int) callconv(.c) ?*cpython.PyObject {
    _ = smartquotes;

    const bytes_obj: *PyBytesObject = @ptrCast(@alignCast(obj));
    const len: usize = @intCast(bytes_obj.ob_base.ob_size);
    const data: [*]const u8 = @ptrCast(&bytes_obj.ob_sval);

    // Simple repr: b'...'
    const prefix = "b'";
    const suffix = "'";
    const total = prefix.len + len + suffix.len;

    const result = PyBytes_FromStringAndSize(null, @intCast(total));
    if (result == null) return null;

    const result_bytes: *PyBytesObject = @ptrCast(@alignCast(result.?));
    const result_data: [*]u8 = @ptrCast(&result_bytes.ob_sval);

    // Build repr
    @memcpy(result_data[0..prefix.len], prefix);
    @memcpy(result_data[prefix.len .. prefix.len + len], data[0..len]);
    @memcpy(result_data[prefix.len + len ..][0..suffix.len], suffix);

    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyBytesObject layout matches CPython" {
    // PyBytesObject: ob_base(24) + ob_shash(8) + ob_sval[1](1) = 33 bytes
    // But with alignment, it will be 40 bytes
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyBytesObject, "ob_shash"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyBytesObject, "ob_sval"));
}

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
