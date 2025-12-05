/// CPython Buffer Protocol
///
/// Implements the buffer protocol for memory-efficient data exchange.
const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

/// Fill buffer info from object
export fn PyBuffer_FillInfo(
    view: *cpython.Py_buffer,
    obj: ?*cpython.PyObject,
    buf: ?*anyopaque,
    len: isize,
    readonly: c_int,
    flags: c_int,
) callconv(.c) c_int {
    _ = flags;

    // Fill Py_buffer view
    view.buf = buf;
    view.obj = obj;
    view.len = len;
    view.readonly = readonly;
    view.itemsize = 1;
    view.ndim = 1;
    view.shape = null;
    view.strides = null;
    view.format = null;
    view.suboffsets = null;
    view.internal = null;

    // INCREF object
    if (obj) |o| {
        _ = traits.incref(o);
    }

    return 0;
}

/// Get buffer from object
export fn PyObject_GetBuffer(
    obj: *cpython.PyObject,
    view: *cpython.Py_buffer,
    flags: c_int,
) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);

    // Check if type supports buffer protocol
    if (type_obj.tp_as_buffer) |buffer_procs| {
        if (buffer_procs.bf_getbuffer) |getbuffer| {
            return getbuffer(obj, view, flags);
        }
    }

    // Type doesn't support buffer protocol
    return -1;
}

/// Release buffer
export fn PyBuffer_Release(view: *cpython.Py_buffer) callconv(.c) void {
    if (view.obj) |obj| {
        const type_obj = cpython.Py_TYPE(obj);

        if (type_obj.tp_as_buffer) |buffer_procs| {
            if (buffer_procs.bf_releasebuffer) |releasebuffer| {
                releasebuffer(obj, view);
            }
        }

        // DECREF object
        traits.decref(obj);
        view.obj = null;
    }

    // Free allocated shape/strides if we own them
    if (view.internal != null) {
        if (view.shape) |s| {
            allocator.free(s[0..@intCast(view.ndim)]);
            view.shape = null;
        }
        if (view.strides) |s| {
            allocator.free(s[0..@intCast(view.ndim)]);
            view.strides = null;
        }
        view.internal = null;
    }
}

/// Get buffer size from format string
export fn PyBuffer_SizeFromFormat(format: [*:0]const u8) callconv(.c) isize {
    const fmt = std.mem.span(format);

    // Simple format codes
    if (fmt.len == 1) {
        return switch (fmt[0]) {
            'c', 'b', 'B', '?' => 1, // char, signed/unsigned byte, bool
            'h', 'H' => 2, // short
            'i', 'I', 'l', 'L' => 4, // int, long
            'q', 'Q' => 8, // long long
            'f' => 4, // float
            'd' => 8, // double
            else => -1,
        };
    }

    return -1;
}

/// Check if buffer is contiguous
export fn PyBuffer_IsContiguous(view: *const cpython.Py_buffer, fort: u8) callconv(.c) c_int {
    // If no strides, it's C-contiguous by default
    if (view.strides == null) {
        return if (fort == 'C' or fort == 'c' or fort == 'A' or fort == 'a') 1 else 0;
    }

    const ndim = view.ndim;
    if (ndim == 0) return 1;

    const shape = view.shape orelse return 0;
    const strides = view.strides.?;
    const itemsize = view.itemsize;

    // Check C-contiguous
    if (fort == 'C' or fort == 'c' or fort == 'A' or fort == 'a') {
        var expected_stride = itemsize;
        var i: isize = ndim - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            if (strides[idx] != expected_stride) {
                if (fort == 'A' or fort == 'a') {
                    // Try Fortran order
                    break;
                }
                return 0;
            }
            expected_stride *= shape[idx];
        }
        if (i < 0) return 1;
    }

    // Check Fortran-contiguous
    if (fort == 'F' or fort == 'f' or fort == 'A' or fort == 'a') {
        var expected_stride = itemsize;
        var i: usize = 0;
        while (i < ndim) : (i += 1) {
            if (strides[i] != expected_stride) return 0;
            expected_stride *= shape[i];
        }
        return 1;
    }

    return 0;
}

/// Fill contiguous strides
export fn PyBuffer_FillContiguousStrides(
    ndim: c_int,
    shape: [*]isize,
    strides: [*]isize,
    itemsize: isize,
    fort: u8,
) callconv(.c) void {
    if (fort == 'C' or fort == 'c') {
        // C-contiguous (row-major)
        var stride = itemsize;
        var i: isize = ndim - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            strides[idx] = stride;
            stride *= shape[idx];
        }
    } else {
        // Fortran-contiguous (column-major)
        var stride = itemsize;
        var i: usize = 0;
        while (i < ndim) : (i += 1) {
            strides[i] = stride;
            stride *= shape[i];
        }
    }
}

/// Get pointer to buffer data
export fn PyBuffer_GetPointer(
    view: *cpython.Py_buffer,
    indices: [*]isize,
) callconv(.c) ?*anyopaque {
    const buf_ptr: [*]u8 = @ptrCast(view.buf orelse return null);
    var offset: isize = 0;

    if (view.strides) |strides| {
        var i: usize = 0;
        while (i < view.ndim) : (i += 1) {
            offset += indices[i] * strides[i];
        }
    } else {
        // C-contiguous
        var stride = view.itemsize;
        var i: isize = @as(isize, @intCast(view.ndim)) - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            offset += indices[idx] * stride;
            if (i > 0 and view.shape != null) {
                stride *= view.shape.?[idx];
            }
        }
    }

    const offset_usize: usize = @intCast(offset);
    return @ptrCast(&buf_ptr[offset_usize]);
}

/// Copy data between buffer objects
export fn PyObject_CopyData(
    dest: *cpython.PyObject,
    src: *cpython.PyObject,
) callconv(.c) c_int {
    var dest_view: cpython.Py_buffer = undefined;
    var src_view: cpython.Py_buffer = undefined;

    if (PyObject_GetBuffer(dest, &dest_view, cpython.PyBUF_WRITABLE) != 0) {
        return -1;
    }
    defer PyBuffer_Release(&dest_view);

    if (PyObject_GetBuffer(src, &src_view, cpython.PyBUF_SIMPLE) != 0) {
        return -1;
    }
    defer PyBuffer_Release(&src_view);

    if (dest_view.len != src_view.len) {
        return -1;
    }

    // Copy data
    const dest_ptr: [*]u8 = @ptrCast(dest_view.buf orelse return -1);
    const src_ptr: [*]const u8 = @ptrCast(src_view.buf orelse return -1);
    const len: usize = @intCast(dest_view.len);

    @memcpy(dest_ptr[0..len], src_ptr[0..len]);

    return 0;
}

/// Check if object supports buffer protocol
export fn PyObject_CheckBuffer(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_as_buffer) |buffer_procs| {
        if (buffer_procs.bf_getbuffer != null) {
            return 1;
        }
    }

    return 0;
}

// Tests
test "PyBuffer_SizeFromFormat" {
    try std.testing.expectEqual(@as(isize, 1), PyBuffer_SizeFromFormat("b"));
    try std.testing.expectEqual(@as(isize, 2), PyBuffer_SizeFromFormat("h"));
    try std.testing.expectEqual(@as(isize, 4), PyBuffer_SizeFromFormat("i"));
    try std.testing.expectEqual(@as(isize, 8), PyBuffer_SizeFromFormat("q"));
    try std.testing.expectEqual(@as(isize, 4), PyBuffer_SizeFromFormat("f"));
    try std.testing.expectEqual(@as(isize, 8), PyBuffer_SizeFromFormat("d"));
}

test "PyBuffer_FillContiguousStrides C-order" {
    var shape = [_]isize{ 3, 4, 5 };
    var strides = [_]isize{ 0, 0, 0 };

    PyBuffer_FillContiguousStrides(3, &shape, &strides, 4, 'C'); // 4-byte items

    try std.testing.expectEqual(@as(isize, 80), strides[0]); // 4*5*4
    try std.testing.expectEqual(@as(isize, 20), strides[1]); // 5*4
    try std.testing.expectEqual(@as(isize, 4), strides[2]); // 4
}

test "PyBuffer_FillContiguousStrides F-order" {
    var shape = [_]isize{ 3, 4, 5 };
    var strides = [_]isize{ 0, 0, 0 };

    PyBuffer_FillContiguousStrides(3, &shape, &strides, 4, 'F'); // 4-byte items

    try std.testing.expectEqual(@as(isize, 4), strides[0]); // 4
    try std.testing.expectEqual(@as(isize, 12), strides[1]); // 3*4
    try std.testing.expectEqual(@as(isize, 48), strides[2]); // 3*4*4
}
