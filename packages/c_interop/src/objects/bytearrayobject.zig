/// PyByteArrayObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/bytearrayobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// PyByteArrayObject - EXACT CPython layout
pub const PyByteArrayObject = extern struct {
    ob_base: cpython.PyVarObject, // 24 bytes (includes ob_size)
    ob_alloc: isize, // Allocated size
    ob_bytes: ?[*]u8, // Physical backing buffer
    ob_start: ?[*]u8, // Logical start inside ob_bytes
    ob_exports: isize, // How many buffer exports
    ob_bytes_object: ?*cpython.PyObject, // PyBytes for zero-copy conversion
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyByteArray_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "bytearray",
    .tp_basicsize = @sizeOf(PyByteArrayObject),
    .tp_itemsize = 0,
    .tp_dealloc = bytearray_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null, // Mutable, not hashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "bytearray(iterable_of_ints) -> bytearray",
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
// API FUNCTIONS
// ============================================================================

/// Create new bytearray from C string
pub export fn PyByteArray_FromStringAndSize(str: ?[*]const u8, size: isize) callconv(.c) ?*cpython.PyObject {
    if (size < 0) return null;

    const obj = allocator.create(PyByteArrayObject) catch return null;
    const usize_size: usize = @intCast(size);

    // Allocate buffer
    const buffer = allocator.alloc(u8, usize_size + 1) catch {
        allocator.destroy(obj);
        return null;
    };

    obj.ob_base.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_base.ob_type = &PyByteArray_Type;
    obj.ob_base.ob_size = size;
    obj.ob_alloc = size + 1;
    obj.ob_bytes = buffer.ptr;
    obj.ob_start = buffer.ptr;
    obj.ob_exports = 0;
    obj.ob_bytes_object = null;

    // Copy data if provided
    if (str) |s| {
        @memcpy(buffer[0..usize_size], s[0..usize_size]);
    } else {
        @memset(buffer[0..usize_size], 0);
    }
    buffer[usize_size] = 0; // Null terminate

    return @ptrCast(&obj.ob_base.ob_base);
}

/// Create from object
/// Handles bytes, bytearray, and iterables of ints
pub export fn PyByteArray_FromObject(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj_type = cpython.Py_TYPE(obj);

    // Check if it's already a bytearray
    if (obj_type == &PyByteArray_Type) {
        // Copy the bytearray
        const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(ba.ob_base.ob_size);
        if (ba.ob_start) |src| {
            return PyByteArray_FromStringAndSize(src, @intCast(size));
        }
        return PyByteArray_FromStringAndSize(null, 0);
    }

    // Check if it's bytes
    const pybytes = @import("bytesobject.zig");
    if (pybytes.PyBytes_Check(obj) != 0) {
        const bytes: *pybytes.PyBytesObject = @ptrCast(@alignCast(obj));
        const size = bytes.ob_base.ob_size;
        const data: [*]const u8 = @ptrCast(&bytes.ob_sval);
        return PyByteArray_FromStringAndSize(data, size);
    }

    // Check if it's a memoryview or has buffer protocol
    const type_flags = obj_type.tp_flags;
    _ = type_flags;

    // Try to iterate and collect integers
    // Check for __iter__ via tp_iter
    if (obj_type.tp_iter) |iter_fn| {
        const iterator = iter_fn(obj) orelse return null;
        defer {
            const traits = @import("typetraits.zig");
            traits.decref(iterator);
        }

        const iter_type = cpython.Py_TYPE(iterator);
        const iternext = iter_type.tp_iternext orelse return null;

        // Collect bytes into a dynamic buffer
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        while (true) {
            const item = iternext(iterator);
            if (item == null) break;
            defer {
                const traits = @import("typetraits.zig");
                traits.decref(item.?);
            }

            // Must be an integer 0-255
            const traits = @import("typetraits.zig");
            if (traits.isInt(item.?)) {
                const val = traits.externs.PyLong_AsLong(item.?);
                if (val < 0 or val > 255) {
                    // Value out of range
                    return null;
                }
                buffer.append(@intCast(val)) catch return null;
            } else {
                // Not an integer
                return null;
            }
        }

        return PyByteArray_FromStringAndSize(buffer.items.ptr, @intCast(buffer.items.len));
    }

    // Check for sequence protocol
    if (obj_type.tp_as_sequence) |seq| {
        if (seq.sq_length) |len_fn| {
            const length = len_fn(obj);
            if (length < 0) return null;

            const result = PyByteArray_FromStringAndSize(null, length) orelse return null;
            const ba: *PyByteArrayObject = @ptrCast(@alignCast(result));
            const dest = ba.ob_start orelse return null;

            const get_item = seq.sq_item orelse {
                // Can't access items
                return result;
            };

            var i: isize = 0;
            while (i < length) : (i += 1) {
                const item = get_item(obj, i);
                if (item == null) {
                    // Error getting item - return partial result
                    ba.ob_base.ob_size = i;
                    return result;
                }
                defer {
                    const traits = @import("typetraits.zig");
                    traits.decref(item.?);
                }

                const traits = @import("typetraits.zig");
                if (traits.isInt(item.?)) {
                    const val = traits.externs.PyLong_AsLong(item.?);
                    if (val < 0 or val > 255) {
                        ba.ob_base.ob_size = i;
                        return result;
                    }
                    dest[@intCast(i)] = @intCast(val);
                } else {
                    ba.ob_base.ob_size = i;
                    return result;
                }
            }

            return result;
        }
    }

    // Can't convert
    return null;
}

/// Get size
pub export fn PyByteArray_Size(obj: *cpython.PyObject) callconv(.c) isize {
    const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));
    return ba.ob_base.ob_size;
}

/// Get buffer pointer
pub export fn PyByteArray_AsString(obj: *cpython.PyObject) callconv(.c) ?[*]u8 {
    const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));
    return ba.ob_start;
}

/// Resize bytearray
pub export fn PyByteArray_Resize(obj: *cpython.PyObject, newsize: isize) callconv(.c) c_int {
    if (newsize < 0) return -1;
    const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));

    if (ba.ob_exports > 0) return -1; // Can't resize while exported

    const usize_new: usize = @intCast(newsize);
    const usize_alloc: usize = @intCast(ba.ob_alloc);

    if (ba.ob_bytes) |old_buf| {
        const new_buf = allocator.realloc(old_buf[0..usize_alloc], usize_new + 1) catch return -1;
        ba.ob_bytes = new_buf.ptr;
        ba.ob_start = new_buf.ptr;
        ba.ob_alloc = newsize + 1;
    }

    ba.ob_base.ob_size = newsize;
    return 0;
}

/// Concatenate
pub export fn PyByteArray_Concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const ba_a: *PyByteArrayObject = @ptrCast(@alignCast(a));
    const ba_b: *PyByteArrayObject = @ptrCast(@alignCast(b));

    const size_a: usize = @intCast(ba_a.ob_base.ob_size);
    const size_b: usize = @intCast(ba_b.ob_base.ob_size);
    const total = size_a + size_b;

    const result = PyByteArray_FromStringAndSize(null, @intCast(total)) orelse return null;
    const ba_result: *PyByteArrayObject = @ptrCast(@alignCast(result));

    if (ba_result.ob_start) |dest| {
        if (ba_a.ob_start) |src_a| {
            @memcpy(dest[0..size_a], src_a[0..size_a]);
        }
        if (ba_b.ob_start) |src_b| {
            @memcpy(dest[size_a..total], src_b[0..size_b]);
        }
    }

    return result;
}

/// Type check
pub export fn PyByteArray_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyByteArray_Type) 1 else 0;
}

pub export fn PyByteArray_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyByteArray_Type) 1 else 0;
}

/// PyByteArray_AS_STRING - macro form, no type checking
pub export fn PyByteArray_AS_STRING(obj: *cpython.PyObject) callconv(.c) ?[*]u8 {
    const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));
    return ba.ob_start;
}

/// PyByteArray_GET_SIZE - macro form, no type checking
pub export fn PyByteArray_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));
    return ba.ob_base.ob_size;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn bytearray_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const ba: *PyByteArrayObject = @ptrCast(@alignCast(obj));

    if (ba.ob_bytes) |buf| {
        const size: usize = @intCast(ba.ob_alloc);
        allocator.free(buf[0..size]);
    }

    allocator.destroy(ba);
}

// ============================================================================
// TESTS
// ============================================================================

test "PyByteArrayObject layout" {
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyByteArrayObject, "ob_alloc"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyByteArrayObject, "ob_bytes"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(PyByteArrayObject, "ob_start"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(PyByteArrayObject, "ob_exports"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(PyByteArrayObject, "ob_bytes_object"));
}
