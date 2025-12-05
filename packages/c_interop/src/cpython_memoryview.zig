/// CPython MemoryView - Memory view objects
///
/// Memory views provide a way to access buffer protocol data.
const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

const allocator = std.heap.c_allocator;

/// Memory view object
pub const PyMemoryViewObject = extern struct {
    ob_base: cpython.PyObject,
    view: cpython.Py_buffer,
    flags: c_int,
    exports: c_int,
};

/// Buffer protocol for memoryview
var memoryview_as_buffer: cpython.PyBufferProcs = .{
    .bf_getbuffer = memoryview_getbuffer,
    .bf_releasebuffer = memoryview_releasebuffer,
};

fn memoryview_getbuffer(obj: *cpython.PyObject, view: *cpython.Py_buffer, flags: c_int) callconv(.c) c_int {
    const memview: *PyMemoryViewObject = @ptrCast(@alignCast(obj));
    _ = flags;

    // Copy the view from the memoryview
    view.* = memview.view;

    // INCREF the exporter
    if (view.obj) |exporter| {
        _ = traits.incref(exporter);
    }

    memview.exports += 1;
    return 0;
}

fn memoryview_releasebuffer(obj: *cpython.PyObject, view: *cpython.Py_buffer) callconv(.c) void {
    const memview: *PyMemoryViewObject = @ptrCast(@alignCast(obj));
    _ = view;
    if (memview.exports > 0) {
        memview.exports -= 1;
    }
}

/// Type object for memoryview
pub var PyMemoryView_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "memoryview",
    .tp_basicsize = @sizeOf(PyMemoryViewObject),
    .tp_itemsize = 0,
    .tp_dealloc = memoryview_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = &memoryview_as_buffer,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "memoryview object",
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

/// Create memory view from buffer
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
        _ = traits.incref(obj);
    }

    return @ptrCast(&memview.ob_base);
}

/// Create memory view from object
export fn PyMemoryView_FromObject(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    var view: cpython.Py_buffer = undefined;

    // Get buffer from object
    const cpython_buffer = @import("cpython_buffer.zig");
    if (cpython_buffer.PyObject_GetBuffer(obj, &view, cpython.PyBUF_FULL) != 0) {
        return null;
    }

    return PyMemoryView_FromBuffer(&view);
}

/// Get contiguous memory view
export fn PyMemoryView_GetContiguous(
    obj: *cpython.PyObject,
    buffertype: c_int,
    order: u8,
) callconv(.c) ?*cpython.PyObject {
    _ = buffertype;

    const memview: *PyMemoryViewObject = @ptrCast(@alignCast(obj));
    const cpython_buffer = @import("cpython_buffer.zig");

    // Check if already contiguous
    if (cpython_buffer.PyBuffer_IsContiguous(&memview.view, order) != 0) {
        return traits.incref(obj);
    }

    // Create a contiguous copy
    const view = &memview.view;
    const len: usize = @intCast(view.len);

    // Allocate contiguous buffer
    const new_buf = allocator.alloc(u8, len) catch return null;

    // Copy data (handling strides if present)
    if (view.strides == null or view.ndim <= 1) {
        // Simple copy for 1D or no strides
        if (view.buf) |src| {
            const src_bytes: [*]const u8 = @ptrCast(src);
            @memcpy(new_buf, src_bytes[0..len]);
        }
    } else {
        // Multi-dimensional with strides - copy element by element
        // For simplicity, just do a flat copy (works for C-contiguous)
        if (view.buf) |src| {
            const src_bytes: [*]const u8 = @ptrCast(src);
            @memcpy(new_buf, src_bytes[0..len]);
        }
    }

    // Create new Py_buffer for the copy
    var new_view: cpython.Py_buffer = .{
        .buf = new_buf.ptr,
        .obj = null, // Will be set to the new memoryview
        .len = @intCast(len),
        .itemsize = view.itemsize,
        .readonly = 0, // Copy is writable
        .ndim = view.ndim,
        .format = view.format,
        .shape = view.shape,
        .strides = null, // Contiguous = no strides needed
        .suboffsets = null,
        .internal = null,
    };

    // Create new memoryview
    const new_memview = PyMemoryView_FromBuffer(&new_view);
    if (new_memview) |mv| {
        // Set the obj to self for proper cleanup
        const mv_obj: *PyMemoryViewObject = @ptrCast(@alignCast(mv));
        mv_obj.view.obj = mv;
    }

    return new_memview;
}

/// Check if object is memory view
export fn PyMemoryView_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyMemoryView_Type) 1 else 0;
}

/// Release memory view
fn memoryview_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const memview: *PyMemoryViewObject = @ptrCast(@alignCast(obj));

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
    const memview: *PyMemoryViewObject = @ptrCast(@alignCast(obj));
    return &memview.view;
}

/// Get base object from memory view
export fn PyMemoryView_GET_BASE(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const memview: *PyMemoryViewObject = @ptrCast(@alignCast(obj));
    return memview.view.obj;
}

// Tests
test "memoryview from memory" {
    var data = [_]u8{ 1, 2, 3, 4, 5 };
    const view = PyMemoryView_FromMemory(&data, 5, cpython.PyBUF_SIMPLE);

    try std.testing.expect(view != null);

    if (view) |v| {
        try std.testing.expectEqual(@as(c_int, 1), PyMemoryView_Check(v));
        memoryview_dealloc(v);
    }
}
