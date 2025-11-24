/// CPython MemoryView - Using Generic Buffer Implementation
///
/// Memory views provide a way to access buffer protocol data with comptime optimization.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const buffer_impl = @import("../../shared/buffer_impl.zig");

const allocator = std.heap.c_allocator;

/// Memory view object
pub const PyMemoryViewObject = extern struct {
    ob_base: cpython.PyObject,
    view: cpython.Py_buffer,
    flags: c_int,
    exports: c_int,
};

/// Type object for memoryview
pub var PyMemoryView_Type: cpython.PyTypeObject = undefined;

/// Create memory view from buffer (comptime specialized!)
export fn PyMemoryView_FromBuffer(view: *cpython.Py_buffer) callconv(.c) ?*cpython.PyObject {
    const memview = allocator.create(PyMemoryViewObject) catch return null;

    memview.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = &PyMemoryView_Type,
    };

    // Copy view
    memview.view = view.*;
    memview.flags = 0;
    memview.exports = 0;

    // INCREF the underlying object
    if (view.obj) |obj| {
        obj.ob_refcnt += 1;
    }

    return @ptrCast(&memview.ob_base);
}

/// Create memory view from object
export fn PyMemoryView_FromObject(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    var view: cpython.Py_buffer = undefined;

    // Get buffer from object (uses comptime-specialized buffer!)
    const cpython_buffer = @import("cpython_buffer.zig");
    if (cpython_buffer.PyObject_GetBuffer(obj, &view, cpython.PyBUF_FULL) != 0) {
        return null;
    }

    return PyMemoryView_FromBuffer(&view);
}

/// Get contiguous memory view (uses generic buffer's contiguity check!)
export fn PyMemoryView_GetContiguous(
    obj: *cpython.PyObject,
    buffertype: c_int,
    order: u8,
) callconv(.c) ?*cpython.PyObject {
    _ = buffertype;

    const memview = @as(*PyMemoryViewObject, @ptrCast(obj));

    // Use generic buffer to check contiguity
    const Config = buffer_impl.NDArrayBufferConfig;
    const Buffer = buffer_impl.BufferImpl(Config);

    // Create buffer from view
    var buffer = Buffer{
        .buf = memview.view.buf orelse return null,
        .len = memview.view.len,
        .itemsize = memview.view.itemsize,
        .readonly = memview.view.readonly != 0,
        .allocator = allocator,
        .ndim = @intCast(memview.view.ndim),
        .shape = memview.view.shape,
        .strides = memview.view.strides,
        .format = memview.view.format,
    };

    if (buffer.isContiguous(order)) {
        // Already contiguous, return same object
        obj.ob_refcnt += 1;
        return obj;
    }

    // Need to make contiguous copy (uses generic buffer's makeContiguous!)
    var contiguous = buffer.makeContiguous(order) catch return null;
    defer contiguous.deinit();

    // Create new view for contiguous data
    var new_view = cpython.Py_buffer{
        .buf = contiguous.buf,
        .obj = memview.view.obj,
        .len = contiguous.len,
        .itemsize = contiguous.itemsize,
        .readonly = if (contiguous.readonly) 1 else 0,
        .ndim = @intCast(contiguous.ndim),
        .format = if (Config.has_format) contiguous.format else null,
        .shape = if (contiguous.shape) |s| s.ptr else null,
        .strides = if (contiguous.strides) |s| s.ptr else null,
        .suboffsets = null,
        .internal = null,
    };

    return PyMemoryView_FromBuffer(&new_view);
}

/// Check if object is memory view
export fn PyMemoryView_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyMemoryView_Type) 1 else 0;
}

/// Release memory view
export fn PyMemoryView_Release(obj: *cpython.PyObject) callconv(.c) void {
    const memview = @as(*PyMemoryViewObject, @ptrCast(obj));

    // Release buffer
    const cpython_buffer = @import("cpython_buffer.zig");
    cpython_buffer.PyBuffer_Release(&memview.view);

    // Free memory view object
    allocator.destroy(memview);
}

/// Get memory view from bytes object
export fn PyMemoryView_FromMemory(
    mem: [*]u8,
    size: isize,
    flags: c_int,
) callconv(.c) ?*cpython.PyObject {
    const readonly = (flags & cpython.PyBUF_WRITABLE) == 0;

    var view: cpython.Py_buffer = undefined;
    const cpython_buffer = @import("cpython_buffer.zig");

    if (cpython_buffer.PyBuffer_FillInfo(
        &view,
        null,
        @ptrCast(mem),
        size,
        if (readonly) 1 else 0,
        flags,
    ) != 0) {
        return null;
    }

    return PyMemoryView_FromBuffer(&view);
}

/// Get buffer from memory view
export fn PyMemoryView_GET_BUFFER(obj: *cpython.PyObject) callconv(.c) ?*cpython.Py_buffer {
    const memview = @as(*PyMemoryViewObject, @ptrCast(obj));
    return &memview.view;
}

/// Get base object from memory view
export fn PyMemoryView_GET_BASE(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const memview = @as(*PyMemoryViewObject, @ptrCast(obj));
    return memview.view.obj;
}

// Tests
test "memoryview size" {
    const expected = @sizeOf(cpython.PyObject) + @sizeOf(cpython.Py_buffer) + @sizeOf(c_int) * 2;
    try std.testing.expectEqual(expected, @sizeOf(PyMemoryViewObject));
}

test "memoryview from memory" {
    var data = [_]u8{ 1, 2, 3, 4, 5 };
    const view = PyMemoryView_FromMemory(&data, 5, cpython.PyBUF_SIMPLE);

    try std.testing.expect(view != null);

    if (view) |v| {
        try std.testing.expectEqual(@as(c_int, 1), PyMemoryView_Check(v));
        PyMemoryView_Release(v);
    }
}
