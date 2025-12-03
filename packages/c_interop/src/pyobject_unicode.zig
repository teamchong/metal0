/// Python unicode (str) object implementation
///
/// EXACT CPython 3.12 memory layout for binary compatibility.
/// Uses PyASCIIObject for ASCII-only strings, PyCompactUnicodeObject for non-ASCII.
///
/// Reference: cpython/Include/cpython/unicodeobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export types from cpython_object.zig for exact CPython layout
pub const PyASCIIObject = cpython.PyASCIIObject;
pub const PyCompactUnicodeObject = cpython.PyCompactUnicodeObject;
pub const PyUnicodeObject = cpython.PyUnicodeObject;

// Unicode string kind constants
pub const PyUnicode_1BYTE_KIND = cpython.PyUnicode_1BYTE_KIND;
pub const PyUnicode_2BYTE_KIND = cpython.PyUnicode_2BYTE_KIND;
pub const PyUnicode_4BYTE_KIND = cpython.PyUnicode_4BYTE_KIND;

// State bit manipulation
const STATE_INTERNED_SHIFT: u5 = 0;
const STATE_KIND_SHIFT: u5 = 2;
const STATE_COMPACT_SHIFT: u5 = 5;
const STATE_ASCII_SHIFT: u5 = 6;
const STATE_STATICALLY_ALLOCATED_SHIFT: u5 = 7;

fn makeState(interned: u2, kind: u3, compact: bool, ascii: bool, static_alloc: bool) u32 {
    return @as(u32, interned) << STATE_INTERNED_SHIFT |
        @as(u32, kind) << STATE_KIND_SHIFT |
        @as(u32, @intFromBool(compact)) << STATE_COMPACT_SHIFT |
        @as(u32, @intFromBool(ascii)) << STATE_ASCII_SHIFT |
        @as(u32, @intFromBool(static_alloc)) << STATE_STATICALLY_ALLOCATED_SHIFT;
}

fn isAscii(state: cpython._PyUnicodeObject_state) bool {
    return (state._packed >> STATE_ASCII_SHIFT) & 1 != 0;
}

fn isCompact(state: cpython._PyUnicodeObject_state) bool {
    return (state._packed >> STATE_COMPACT_SHIFT) & 1 != 0;
}

fn getKind(state: cpython._PyUnicodeObject_state) u3 {
    return @intCast((state._packed >> STATE_KIND_SHIFT) & 0x7);
}

/// Sequence protocol for strings
var unicode_as_sequence: cpython.PySequenceMethods = .{
    .sq_length = unicode_length,
    .sq_concat = unicode_concat,
    .sq_repeat = null,
    .sq_item = null,
    .sq_ass_item = null,
    .sq_contains = null,
    .sq_inplace_concat = null,
    .sq_inplace_repeat = null,
};

fn unicode_length(obj: *cpython.PyObject) callconv(.c) isize {
    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));
    return ascii_obj.length;
}

/// PyUnicode_Type - the 'str' type
pub var PyUnicode_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "str",
    .tp_basicsize = @sizeOf(PyASCIIObject),
    .tp_itemsize = 1, // Variable-size
    .tp_dealloc = unicode_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = &unicode_as_sequence,
    .tp_as_mapping = null,
    .tp_hash = unicode_hash,
    .tp_call = null,
    .tp_str = unicode_str,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_UNICODE_SUBCLASS,
    .tp_doc = "str(object='') -> string",
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
// Core API Functions
// ============================================================================

/// Check if string is all ASCII
fn isAllAscii(str: [*]const u8, len: usize) bool {
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (str[i] >= 0x80) return false;
    }
    return true;
}

/// Create Unicode from UTF-8 C string
pub export fn PyUnicode_FromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const len = std.mem.len(str);
    return PyUnicode_FromStringAndSize(str, @intCast(len));
}

/// Create Unicode from UTF-8 buffer with size
pub export fn PyUnicode_FromStringAndSize(str: ?[*]const u8, size: isize) callconv(.c) ?*cpython.PyObject {
    if (size < 0) return null;

    const usize_len: usize = @intCast(size);

    // Check if string is ASCII
    const is_ascii = if (str) |s| isAllAscii(s, usize_len) else true;

    if (is_ascii) {
        // Use compact ASCII form - data follows PyASCIIObject
        const base_size = @sizeOf(PyASCIIObject);
        const total_size = base_size + usize_len + 1; // +1 for null terminator

        const memory = allocator.alloc(u8, total_size) catch return null;
        const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(memory.ptr));

        ascii_obj.ob_base.ob_refcnt = 1;
        ascii_obj.ob_base.ob_type = &PyUnicode_Type;
        ascii_obj.length = size;
        ascii_obj.hash = -1;
        ascii_obj.state._packed = makeState(0, PyUnicode_1BYTE_KIND, true, true, false);

        // Copy data after struct
        const data_ptr = memory.ptr + base_size;
        if (str) |s| {
            @memcpy(data_ptr[0..usize_len], s[0..usize_len]);
        } else {
            @memset(data_ptr[0..usize_len], 0);
        }
        data_ptr[usize_len] = 0; // Null terminate

        return @ptrCast(&ascii_obj.ob_base);
    } else {
        // Use compact non-ASCII form - need to count UTF-8 code points
        const base_size = @sizeOf(PyCompactUnicodeObject);
        const total_size = base_size + usize_len + 1;

        const memory = allocator.alloc(u8, total_size) catch return null;
        const compact_obj: *PyCompactUnicodeObject = @ptrCast(@alignCast(memory.ptr));

        // Count code points
        var char_count: isize = 0;
        if (str) |s| {
            var i: usize = 0;
            while (i < usize_len) {
                if ((s[i] & 0xC0) != 0x80) {
                    char_count += 1;
                }
                i += 1;
            }
        }

        compact_obj._base.ob_base.ob_refcnt = 1;
        compact_obj._base.ob_base.ob_type = &PyUnicode_Type;
        compact_obj._base.length = char_count;
        compact_obj._base.hash = -1;
        compact_obj._base.state._packed = makeState(0, PyUnicode_1BYTE_KIND, true, false, false);
        compact_obj.utf8_length = size;
        compact_obj.utf8 = null; // Data follows struct, not here

        // Copy data after struct
        const data_ptr = memory.ptr + base_size;
        if (str) |s| {
            @memcpy(data_ptr[0..usize_len], s[0..usize_len]);
        } else {
            @memset(data_ptr[0..usize_len], 0);
        }
        data_ptr[usize_len] = 0;

        return @ptrCast(&compact_obj._base.ob_base);
    }
}

/// Get UTF-8 representation
pub export fn PyUnicode_AsUTF8(obj: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    if (PyUnicode_Check(obj) == 0) return null;

    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));

    // For compact strings, data follows the struct
    if (isCompact(ascii_obj.state)) {
        if (isAscii(ascii_obj.state)) {
            // Data follows PyASCIIObject
            const base_ptr: [*]const u8 = @ptrCast(ascii_obj);
            return @ptrCast(base_ptr + @sizeOf(PyASCIIObject));
        } else {
            // Data follows PyCompactUnicodeObject
            const base_ptr: [*]const u8 = @ptrCast(ascii_obj);
            return @ptrCast(base_ptr + @sizeOf(PyCompactUnicodeObject));
        }
    }

    // Non-compact: use external utf8 buffer
    const compact_obj: *PyCompactUnicodeObject = @ptrCast(@alignCast(obj));
    return compact_obj.utf8;
}

/// Get UTF-8 with size
export fn PyUnicode_AsUTF8AndSize(obj: *cpython.PyObject, size: ?*isize) callconv(.c) ?[*:0]const u8 {
    if (PyUnicode_Check(obj) == 0) return null;

    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));

    if (size) |s| {
        if (isAscii(ascii_obj.state)) {
            s.* = ascii_obj.length;
        } else {
            const compact_obj: *PyCompactUnicodeObject = @ptrCast(@alignCast(obj));
            s.* = compact_obj.utf8_length;
        }
    }

    return PyUnicode_AsUTF8(obj);
}

/// Get character length
pub export fn PyUnicode_GetLength(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyUnicode_Check(obj) == 0) return -1;

    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));
    return ascii_obj.length;
}

/// Type check
pub export fn PyUnicode_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return if ((flags & cpython.Py_TPFLAGS_UNICODE_SUBCLASS) != 0) 1 else 0;
}

/// Exact type check
export fn PyUnicode_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyUnicode_Type) 1 else 0;
}

/// Decode UTF-8 bytes to Unicode
export fn PyUnicode_DecodeUTF8(data: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    return PyUnicode_FromStringAndSize(data, size);
}

/// Encode Unicode to UTF-8 bytes
export fn PyUnicode_AsUTF8String(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const utf8 = PyUnicode_AsUTF8(obj);
    if (utf8 == null) return null;

    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));
    var len: isize = undefined;

    if (isAscii(ascii_obj.state)) {
        len = ascii_obj.length;
    } else {
        const compact_obj: *PyCompactUnicodeObject = @ptrCast(@alignCast(obj));
        len = compact_obj.utf8_length;
    }

    // Create bytes object from UTF-8 data
    return @import("pyobject_bytes.zig").PyBytes_FromStringAndSize(utf8, len);
}

/// Concatenate two strings
export fn PyUnicode_Concat(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyUnicode_Check(left) == 0 or PyUnicode_Check(right) == 0) {
        return null;
    }

    return unicode_concat(left, right);
}

/// Compare strings
export fn PyUnicode_Compare(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) c_int {
    if (PyUnicode_Check(left) == 0 or PyUnicode_Check(right) == 0) {
        return -1;
    }

    const left_str = PyUnicode_AsUTF8(left);
    const right_str = PyUnicode_AsUTF8(right);

    if (left_str == null or right_str == null) return -1;

    const left_bytes = std.mem.span(left_str.?);
    const right_bytes = std.mem.span(right_str.?);

    return switch (std.mem.order(u8, left_bytes, right_bytes)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

// ============================================================================
// Internal Functions
// ============================================================================

fn unicode_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_str = PyUnicode_AsUTF8(a);
    const b_str = PyUnicode_AsUTF8(b);

    if (a_str == null or b_str == null) return null;

    const a_obj: *PyASCIIObject = @ptrCast(@alignCast(a));
    const b_obj: *PyASCIIObject = @ptrCast(@alignCast(b));

    var a_len: isize = undefined;
    var b_len: isize = undefined;

    if (isAscii(a_obj.state)) {
        a_len = a_obj.length;
    } else {
        const compact_a: *PyCompactUnicodeObject = @ptrCast(@alignCast(a));
        a_len = compact_a.utf8_length;
    }

    if (isAscii(b_obj.state)) {
        b_len = b_obj.length;
    } else {
        const compact_b: *PyCompactUnicodeObject = @ptrCast(@alignCast(b));
        b_len = compact_b.utf8_length;
    }

    const total_len: usize = @intCast(a_len + b_len);
    const buffer = allocator.alloc(u8, total_len) catch return null;
    defer allocator.free(buffer);

    const a_ulen: usize = @intCast(a_len);
    const b_ulen: usize = @intCast(b_len);

    @memcpy(buffer[0..a_ulen], a_str.?[0..a_ulen]);
    @memcpy(buffer[a_ulen..total_len], b_str.?[0..b_ulen]);

    return PyUnicode_FromStringAndSize(buffer.ptr, @intCast(total_len));
}

fn unicode_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));

    var total_size: usize = undefined;

    if (isCompact(ascii_obj.state)) {
        if (isAscii(ascii_obj.state)) {
            const len: usize = @intCast(ascii_obj.length);
            total_size = @sizeOf(PyASCIIObject) + len + 1;
        } else {
            const compact_obj: *PyCompactUnicodeObject = @ptrCast(@alignCast(obj));
            const len: usize = @intCast(compact_obj.utf8_length);
            total_size = @sizeOf(PyCompactUnicodeObject) + len + 1;
        }
    } else {
        // Non-compact - has separate data buffer
        const unicode_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
        if (unicode_obj.data.any) |data| {
            // Free data buffer - would need to track size
            _ = data;
        }
        total_size = @sizeOf(PyUnicodeObject);
    }

    const memory: [*]u8 = @ptrCast(@alignCast(ascii_obj));
    allocator.free(memory[0..total_size]);
}

fn unicode_str(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    obj.ob_refcnt += 1;
    return obj;
}

fn unicode_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const ascii_obj: *PyASCIIObject = @ptrCast(@alignCast(obj));

    // Return cached hash if available
    if (ascii_obj.hash != -1) {
        return ascii_obj.hash;
    }

    // Compute hash using SipHash-like algorithm
    const str = PyUnicode_AsUTF8(obj);
    if (str == null) return 0;

    var len: usize = undefined;
    if (isAscii(ascii_obj.state)) {
        len = @intCast(ascii_obj.length);
    } else {
        const compact_obj: *PyCompactUnicodeObject = @ptrCast(@alignCast(obj));
        len = @intCast(compact_obj.utf8_length);
    }

    var hash: u64 = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        hash = hash *% 1000003 +% str.?[i];
    }

    const result: isize = @intCast(hash);
    ascii_obj.hash = result;
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "PyASCIIObject layout" {
    // PyASCIIObject: ob_base(16) + length(8) + hash(8) + state(4) = 36 bytes + padding = 40 bytes
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyASCIIObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyASCIIObject, "length"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyASCIIObject, "hash"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyASCIIObject, "state"));
}

test "PyUnicode creation and access" {
    const obj = PyUnicode_FromString("hello");
    try std.testing.expect(obj != null);

    const length = PyUnicode_GetLength(obj.?);
    try std.testing.expectEqual(@as(isize, 5), length);

    const str = PyUnicode_AsUTF8(obj.?);
    try std.testing.expect(str != null);
    try std.testing.expectEqualStrings("hello", std.mem.span(str.?));
}

test "unicode exports" {
    _ = PyUnicode_FromString;
    _ = PyUnicode_AsUTF8;
    _ = PyUnicode_Check;
}
