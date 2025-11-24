/// CPython Buffer Protocol - Using Generic Buffer Implementation
///
/// This implements the buffer protocol with comptime-specialized buffer types.
/// All buffer variants share the same generic implementation!

const std = @import("std");
const cpython = @import("cpython_object.zig");
const buffer_impl = @import("../../shared/buffer_impl.zig");

const allocator = std.heap.c_allocator;

/// Comptime select buffer config based on flags
fn selectBufferConfig(comptime flags: c_int) type {
    if (flags & cpython.PyBUF_ND != 0) {
        return buffer_impl.NDArrayBufferConfig;
    } else if (flags & cpython.PyBUF_WRITABLE == 0) {
        return buffer_impl.ReadOnlyBufferConfig;
    } else {
        return buffer_impl.SimpleBufferConfig;
    }
}

/// Fill buffer info from object (comptime specialized!)
export fn PyBuffer_FillInfo(
    view: *cpython.Py_buffer,
    obj: ?*cpython.PyObject,
    buf: ?*anyopaque,
    len: isize,
    readonly: c_int,
    flags: c_int,
) callconv(.c) c_int {
    // Comptime select config based on flags
    const Config = comptime selectBufferConfig(flags);
    const Buffer = buffer_impl.BufferImpl(Config);

    // Create buffer (comptime specialized!)
    var buffer = Buffer.init(
        allocator,
        buf orelse return -1,
        len,
        readonly != 0
    ) catch return -1;

    // Fill Py_buffer view
    view.buf = buffer.buf;
    view.obj = obj;
    view.len = buffer.len;
    view.readonly = if (buffer.readonly) 1 else 0;
    view.itemsize = buffer.itemsize;

    if (Config.multi_dimensional) {
        view.ndim = @intCast(buffer.ndim);
        view.shape = if (buffer.shape) |s| s.ptr else null;
        view.strides = if (buffer.strides) |s| s.ptr else null;
    } else {
        view.ndim = 1;
        view.shape = null;
        view.strides = null;
    }

    if (Config.has_format) {
        view.format = @constCast(buffer.format orelse null);
    } else {
        view.format = null;
    }

    view.suboffsets = null;
    view.internal = null;

    // INCREF object
    if (obj) |o| {
        o.ob_refcnt += 1;
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
        obj.ob_refcnt -= 1;
        view.obj = null;
    }

    // Free allocated shape/strides
    if (view.shape) |s| {
        allocator.free(s[0..@intCast(view.ndim)]);
        view.shape = null;
    }
    if (view.strides) |s| {
        allocator.free(s[0..@intCast(view.ndim)]);
        view.strides = null;
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

/// Check if buffer is contiguous (uses generic buffer!)
export fn PyBuffer_IsContiguous(view: *const cpython.Py_buffer, fort: u8) callconv(.c) c_int {
    // If no strides, it's C-contiguous by default
    if (view.strides == null) {
        return if (fort == 'C' or fort == 'c') 1 else 0;
    }

    // Use generic buffer's contiguity check
    const Config = buffer_impl.NDArrayBufferConfig;
    const Buffer = buffer_impl.BufferImpl(Config);

    // Create temporary buffer from view
    var buffer = Buffer{
        .buf = view.buf orelse return 0,
        .len = view.len,
        .itemsize = view.itemsize,
        .readonly = view.readonly != 0,
        .allocator = allocator,
        .ndim = @intCast(view.ndim),
        .shape = view.shape,
        .strides = view.strides,
        .format = view.format,
    };

    return if (buffer.isContiguous(fort)) 1 else 0;
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
test "Py_buffer size" {
    // Verify struct matches CPython layout
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(cpython.Py_buffer)); // On 64-bit
}

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
