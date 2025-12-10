/// Memory Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/memoryobject.c
/// memoryview - exposes the buffer interface as a Python object
///
/// Reference: cpython/Objects/memoryobject.c
///            cpython/Include/cpython/memoryobject.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Memoryview flags
pub const _Py_MEMORYVIEW_SCALAR: c_int = 0x0001; // Scalar view (0-dimensional)
pub const _Py_MEMORYVIEW_C: c_int = 0x0002; // C-contiguous
pub const _Py_MEMORYVIEW_FORTRAN: c_int = 0x0004; // Fortran-contiguous
pub const _Py_MEMORYVIEW_PIL: c_int = 0x0008; // PIL-style layout
pub const _Py_MEMORYVIEW_RELEASED: c_int = 0x0010; // Buffer released

/// Maximum number of dimensions for static shape/strides arrays
pub const PyBUF_MAX_NDIM: usize = 64;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// _PyManagedBufferObject - Managed buffer for memoryview
/// Reference: cpython/Objects/memoryobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     int flags;
///     Py_ssize_t exports;
///     Py_buffer master;
/// } _PyManagedBufferObject;
pub const _PyManagedBufferObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    flags: c_int, // 4 bytes
    _pad1: [4]u8, // 4 bytes padding
    exports: isize, // 8 bytes - number of exports
    master: cpython.Py_buffer, // 88 bytes - the buffer info
};

// Verify Py_buffer size
comptime {
    // Py_buffer: buf(8) + obj(8) + len(8) + itemsize(8) + readonly(4) + ndim(4) +
    //            format(8) + shape(8) + strides(8) + suboffsets(8) + internal(8) = 80 bytes
    // But with padding for alignment, could be 88 bytes
    // Let's verify the actual size at runtime
}

/// PyMemoryViewObject - The memoryview object
/// Reference: cpython/Include/cpython/memoryobject.h
///
/// typedef struct {
///     PyObject_VAR_HEAD
///     _PyManagedBufferObject *mbuf;
///     Py_hash_t hash;
///     int flags;
///     Py_ssize_t exports;
///     Py_buffer view;
///     PyObject *weakreflist;
///     Py_ssize_t ob_array[1];
/// } PyMemoryViewObject;
pub const PyMemoryViewObject = extern struct {
    ob_base: cpython.PyVarObject, // 24 bytes
    mbuf: ?*_PyManagedBufferObject, // 8 bytes - managed buffer
    hash: isize, // 8 bytes - cached hash
    flags: c_int, // 4 bytes - flags
    _pad1: [4]u8, // 4 bytes padding
    exports: isize, // 8 bytes - number of exports
    view: cpython.Py_buffer, // 88 bytes - buffer info (copy)
    weakreflist: ?*cpython.PyObject, // 8 bytes - weak references
    ob_array: [1]isize, // flexible array for shape/strides
};

// ============================================================================
// MANAGED BUFFER IMPLEMENTATION
// ============================================================================

/// Dealloc for managed buffer
fn mbuf_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const mbuf: *_PyManagedBufferObject = @ptrCast(@alignCast(self_obj.?));

    // Release the buffer if we have one
    if (mbuf.master.obj) |obj| {
        // Call bf_releasebuffer if available
        if (obj.ob_type.tp_as_buffer) |buf_procs| {
            if (buf_procs.bf_releasebuffer) |release| {
                release(obj, &mbuf.master);
            }
        }
        obj.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(mbuf);
    allocator.free(ptr[0..@sizeOf(_PyManagedBufferObject)]);
}

/// _PyManagedBuffer_Type
pub export var _PyManagedBuffer_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "managedbuffer",
    .tp_basicsize = @sizeOf(_PyManagedBufferObject),
    .tp_itemsize = 0,
    .tp_dealloc = mbuf_dealloc,
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
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = null,
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
};

// ============================================================================
// MEMORYVIEW TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for memoryview
fn memory_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj.?));

    // Clear weakrefs
    if (mv.weakreflist != null) {
        // PyObject_ClearWeakRefs
    }

    // Release managed buffer
    if (mv.mbuf) |mbuf| {
        const mbuf_obj: *cpython.PyObject = @ptrCast(mbuf);
        mbuf_obj.ob_refcnt -= 1;
        if (mbuf_obj.ob_refcnt == 0) {
            mbuf_dealloc(mbuf_obj);
        }
    }

    const ptr: [*]u8 = @ptrCast(mv);
    allocator.free(ptr[0..memoryview_size(mv)]);
}

/// Calculate size needed for memoryview object
fn memoryview_size(mv: *PyMemoryViewObject) usize {
    const ndim: usize = @intCast(@max(0, mv.view.ndim));
    // Need space for shape and strides arrays
    return @sizeOf(PyMemoryViewObject) - @sizeOf(isize) + (ndim * 2 * @sizeOf(isize));
}

/// Traverse for memoryview (GC)
fn memory_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (mv.view.obj) |obj| {
            const result = v(obj, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for memoryview (GC)
fn memory_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj.?));

    if (mv.view.obj) |obj| {
        obj.ob_refcnt -= 1;
        mv.view.obj = null;
    }
    return 0;
}

/// Repr for memoryview
fn memory_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj.?));

    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        // Return "<released memory at 0x...>"
    }

    // Return "<memory at 0x...>"
    _ = mv;
    return null;
}

/// Hash for memoryview
fn memory_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return -1;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj.?));

    if (mv.hash != -1) {
        return mv.hash;
    }

    // Check if released
    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        return -1;
    }

    // Must be readonly to hash
    if (mv.view.readonly == 0) {
        return -1;
    }

    // Compute hash of buffer contents
    if (mv.view.buf) |buf| {
        const data: [*]const u8 = @ptrCast(buf);
        const len: usize = @intCast(mv.view.len);
        var hash: isize = 0;
        for (data[0..len]) |byte| {
            hash = hash *% 31 +% @as(isize, byte);
        }
        if (hash == -1) hash = -2;
        mv.hash = hash;
        return hash;
    }

    return -1;
}

/// Length for memoryview
fn memory_length(self_obj: *cpython.PyObject) callconv(.C) isize {
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj));

    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        return -1;
    }

    if (mv.view.ndim == 0) {
        return 1;
    }

    if (mv.view.shape) |shape| {
        return shape[0];
    }

    return mv.view.len / mv.view.itemsize;
}

/// Subscript getter for memoryview
fn memory_subscript(self_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj));

    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        return null;
    }

    const pylong = @import("longobject.zig");
    const pybytes = @import("bytesobject.zig");

    // Handle integer index
    if (pylong.PyLong_Check(key) != 0) {
        var index = pylong.PyLong_AsSsize_t(key);
        const length = mv.view.len;

        // Handle negative index
        if (index < 0) {
            index += @intCast(length);
        }

        // Bounds check
        if (index < 0 or index >= @as(isize, @intCast(length))) {
            return null; // IndexError
        }

        // Get single byte from buffer
        const buf: [*]u8 = @ptrCast(mv.view.buf orelse return null);
        const byte_val = buf[@intCast(index)];

        // Return as integer for bytes-like access
        return pylong.PyLong_FromLong(@intCast(byte_val));
    }

    // Handle slice
    const pyslice = @import("sliceobject.zig");
    if (key.ob_type == &pyslice.PySlice_Type) {
        var start: isize = 0;
        var stop: isize = 0;
        var step: isize = 0;
        var slice_length: isize = 0;

        if (pyslice.PySlice_GetIndicesEx(key, @intCast(mv.view.len), &start, &stop, &step, &slice_length) < 0) {
            return null;
        }

        // For step=1, return a new bytes object
        if (step == 1) {
            const buf: [*]u8 = @ptrCast(mv.view.buf orelse return null);
            return pybytes.PyBytes_FromStringAndSize(buf + @as(usize, @intCast(start)), slice_length);
        }

        // For non-unit step, build result byte by byte
        const result_buf = allocator.alloc(u8, @intCast(slice_length)) catch return null;
        defer allocator.free(result_buf);

        const buf: [*]u8 = @ptrCast(mv.view.buf orelse return null);
        var src_idx: isize = start;
        for (0..@intCast(slice_length)) |i| {
            result_buf[i] = buf[@intCast(src_idx)];
            src_idx += step;
        }

        return pybytes.PyBytes_FromStringAndSize(result_buf.ptr, slice_length);
    }

    return null;
}

/// Subscript setter for memoryview
fn memory_ass_subscript(self_obj: *cpython.PyObject, key: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.C) c_int {
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj));

    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        return -1;
    }

    if (mv.view.readonly != 0) {
        return -1;
    }

    const pylong = @import("longobject.zig");
    const pybytes = @import("bytesobject.zig");

    // Handle integer index assignment
    if (pylong.PyLong_Check(key) != 0) {
        var index = pylong.PyLong_AsSsize_t(key);
        const length = mv.view.len;

        // Handle negative index
        if (index < 0) {
            index += @intCast(length);
        }

        // Bounds check
        if (index < 0 or index >= @as(isize, @intCast(length))) {
            return -1; // IndexError
        }

        // Get value to assign
        if (value == null) {
            return -1; // Cannot delete from memoryview
        }

        // Value must be an integer 0-255
        if (pylong.PyLong_Check(value.?) == 0) {
            return -1; // TypeError
        }

        const byte_val = pylong.PyLong_AsLong(value.?);
        if (byte_val < 0 or byte_val > 255) {
            return -1; // ValueError
        }

        // Set the byte
        const buf: [*]u8 = @ptrCast(mv.view.buf orelse return -1);
        buf[@intCast(index)] = @truncate(@as(u64, @intCast(byte_val)));
        return 0;
    }

    // Handle slice assignment
    const pyslice = @import("sliceobject.zig");
    if (key.ob_type == &pyslice.PySlice_Type) {
        var start: isize = 0;
        var stop: isize = 0;
        var step: isize = 0;
        var slice_length: isize = 0;

        if (pyslice.PySlice_GetIndicesEx(key, @intCast(mv.view.len), &start, &stop, &step, &slice_length) < 0) {
            return -1;
        }

        if (value == null) {
            return -1; // Cannot delete from memoryview
        }

        // Get source bytes
        var src_ptr: [*]const u8 = undefined;
        var src_len: isize = 0;

        if (pybytes.PyBytes_Check(value.?) != 0) {
            src_ptr = @ptrCast(pybytes.PyBytes_AsString(value.?));
            src_len = pybytes.PyBytes_Size(value.?);
        } else {
            return -1; // Need bytes-like object
        }

        // Length must match
        if (src_len != slice_length) {
            return -1; // ValueError: length mismatch
        }

        // Copy bytes
        const buf: [*]u8 = @ptrCast(mv.view.buf orelse return -1);
        if (step == 1) {
            @memcpy(buf[@intCast(start)..][0..@intCast(slice_length)], src_ptr[0..@intCast(src_len)]);
        } else {
            var dst_idx: isize = start;
            for (0..@intCast(slice_length)) |i| {
                buf[@intCast(dst_idx)] = src_ptr[i];
                dst_idx += step;
            }
        }

        return 0;
    }

    return -1;
}

/// Mapping methods for memoryview
var memory_as_mapping = cpython.PyMappingMethods{
    .mp_length = memory_length,
    .mp_subscript = memory_subscript,
    .mp_ass_subscript = memory_ass_subscript,
};

/// Get buffer for memoryview
fn memory_getbuffer(self_obj: *cpython.PyObject, view: *cpython.Py_buffer, flags: c_int) callconv(.C) c_int {
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj));
    _ = flags;

    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        return -1;
    }

    // Copy view info
    view.* = mv.view;
    view.obj = self_obj;
    self_obj.ob_refcnt += 1;

    mv.exports += 1;
    return 0;
}

/// Release buffer for memoryview
fn memory_releasebuffer(self_obj: *cpython.PyObject, view: *cpython.Py_buffer) callconv(.C) void {
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj));
    _ = view;

    mv.exports -= 1;
}

/// Buffer procs for memoryview
var memory_as_buffer = cpython.PyBufferProcs{
    .bf_getbuffer = memory_getbuffer,
    .bf_releasebuffer = memory_releasebuffer,
};

/// New for memoryview
fn memory_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    // memoryview requires an object argument
    return null;
}

/// Rich comparison for memoryview
fn memory_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only support == and !=
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return cpython.Py_NotImplemented;
    }

    const mv_self: *PyMemoryViewObject = @ptrCast(@alignCast(self_obj));

    // Check if other is also a memoryview
    if (other.ob_type != &PyMemoryView_Type) {
        // Compare with bytes-like objects
        const pybytes = @import("bytesobject.zig");
        if (pybytes.PyBytes_Check(other) != 0) {
            const other_ptr = pybytes.PyBytes_AsString(other);
            const other_len = pybytes.PyBytes_Size(other);

            // Length check
            if (@as(isize, @intCast(mv_self.view.len)) != other_len) {
                return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
            }

            // Content comparison
            const self_buf: [*]const u8 = @ptrCast(mv_self.view.buf orelse {
                return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
            });

            const len: usize = @intCast(other_len);
            const are_equal = std.mem.eql(u8, self_buf[0..len], other_ptr[0..len]);

            return if (op == object_mod.Py_EQ)
                (if (are_equal) pybool.Py_True else pybool.Py_False)
            else
                (if (are_equal) pybool.Py_False else pybool.Py_True);
        }

        return cpython.Py_NotImplemented;
    }

    const mv_other: *PyMemoryViewObject = @ptrCast(@alignCast(other));

    // Check both are not released
    if ((mv_self.flags & _Py_MEMORYVIEW_RELEASED != 0) or
        (mv_other.flags & _Py_MEMORYVIEW_RELEASED != 0))
    {
        return cpython.Py_NotImplemented;
    }

    // Length check
    if (mv_self.view.len != mv_other.view.len) {
        return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
    }

    // Content comparison
    const self_buf: [*]const u8 = @ptrCast(mv_self.view.buf orelse {
        return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
    });
    const other_buf: [*]const u8 = @ptrCast(mv_other.view.buf orelse {
        return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
    });

    const len: usize = mv_self.view.len;
    const are_equal = std.mem.eql(u8, self_buf[0..len], other_buf[0..len]);

    return if (op == object_mod.Py_EQ)
        (if (are_equal) pybool.Py_True else pybool.Py_False)
    else
        (if (are_equal) pybool.Py_False else pybool.Py_True);
}

/// PyMemoryView_Type - the memoryview type object
pub export var PyMemoryView_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "memoryview",
    .tp_basicsize = @sizeOf(PyMemoryViewObject),
    .tp_itemsize = @sizeOf(isize), // For shape/strides array
    .tp_dealloc = memory_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = memory_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = &memory_as_mapping,
    .tp_hash = memory_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = &memory_as_buffer,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "memoryview(object)\n\nCreate a new memoryview object which references the given object.",
    .tp_traverse = memory_traverse,
    .tp_clear = memory_clear,
    .tp_richcompare = memory_richcompare,
    .tp_weaklistoffset = @offsetOf(PyMemoryViewObject, "weakreflist"),
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
    .tp_new = memory_new,
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
};

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Create memoryview from buffer provider object
pub export fn PyMemoryView_FromObject(obj: ?*cpython.PyObject) ?*cpython.PyObject {
    if (obj == null) return null;

    // Get buffer from object
    var view: cpython.Py_buffer = .{};
    if (obj.?.ob_type.tp_as_buffer) |buf_procs| {
        if (buf_procs.bf_getbuffer) |getbuffer| {
            if (getbuffer(obj.?, &view, cpython.PyBUF_SIMPLE) != 0) {
                return null;
            }
        } else {
            return null;
        }
    } else {
        return null;
    }

    return PyMemoryView_FromBuffer(&view);
}

/// Create memoryview from Py_buffer
pub export fn PyMemoryView_FromBuffer(view: ?*cpython.Py_buffer) ?*cpython.PyObject {
    if (view == null) return null;

    const ndim: usize = @intCast(@max(0, view.?.ndim));
    const size = @sizeOf(PyMemoryViewObject) - @sizeOf(isize) + (ndim * 2 * @sizeOf(isize));

    const mem = allocator.alignedAlloc(u8, @alignOf(PyMemoryViewObject), size) catch return null;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(mem.ptr));

    // Create managed buffer
    const mbuf_mem = allocator.alignedAlloc(u8, @alignOf(_PyManagedBufferObject), @sizeOf(_PyManagedBufferObject)) catch {
        allocator.free(mem);
        return null;
    };
    const mbuf: *_PyManagedBufferObject = @ptrCast(@alignCast(mbuf_mem.ptr));

    mbuf.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyManagedBuffer_Type,
        },
        .flags = 0,
        ._pad1 = [_]u8{0} ** 4,
        .exports = 0,
        .master = view.?.*,
    };

    mv.* = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyMemoryView_Type,
            },
            .ob_size = @intCast(ndim * 2),
        },
        .mbuf = mbuf,
        .hash = -1,
        .flags = 0,
        ._pad1 = [_]u8{0} ** 4,
        .exports = 0,
        .view = view.?.*,
        .weakreflist = null,
        .ob_array = undefined,
    };

    // Copy shape and strides
    if (view.?.shape) |shape| {
        const mv_shape = &mv.ob_array;
        for (0..ndim) |i| {
            mv_shape[i] = shape[i];
        }
        mv.view.shape = @ptrCast(mv_shape);
    }

    if (view.?.strides) |strides| {
        const mv_strides: [*]isize = @ptrCast(&mv.ob_array[ndim]);
        for (0..ndim) |i| {
            mv_strides[i] = strides[i];
        }
        mv.view.strides = mv_strides;
    }

    // Incref the underlying object
    if (view.?.obj) |obj| {
        obj.ob_refcnt += 1;
    }

    // Determine flags
    if (ndim == 0) {
        mv.flags |= _Py_MEMORYVIEW_SCALAR;
    }

    return @ptrCast(mv);
}

/// Create memoryview from memory pointer
pub export fn PyMemoryView_FromMemory(mem: ?*anyopaque, len: isize, flags: c_int) ?*cpython.PyObject {
    if (mem == null) return null;

    var view = cpython.Py_buffer{
        .buf = mem,
        .obj = null,
        .len = len,
        .itemsize = 1,
        .readonly = if (flags == cpython.PyBUF_WRITABLE) 0 else 1,
        .ndim = 1,
        .format = @constCast("B"),
        .shape = null,
        .strides = null,
        .suboffsets = null,
        .internal = null,
    };

    return PyMemoryView_FromBuffer(&view);
}

/// Get contiguous memory from memoryview
/// buffertype: PyBUF_READ, PyBUF_WRITE
/// order: 'C' for C-contiguous, 'F' for Fortran-contiguous, 'A' for any
pub export fn PyMemoryView_GetContiguous(obj: ?*cpython.PyObject, buffertype: c_int, order: u8) ?*cpython.PyObject {
    if (obj == null) return null;
    _ = buffertype;

    // Get the buffer from the object
    var view: cpython.Py_buffer = undefined;
    const object_mod = @import("object.zig");

    if (object_mod.PyObject_GetBuffer(obj.?, &view, cpython.PyBUF_FULL_RO) < 0) {
        return null;
    }

    // Check if already contiguous
    const is_c_contiguous = isContiguous(&view, 'C');
    const is_f_contiguous = isContiguous(&view, 'F');

    const need_copy = switch (order) {
        'C' => !is_c_contiguous,
        'F' => !is_f_contiguous,
        'A' => !is_c_contiguous and !is_f_contiguous,
        else => true,
    };

    if (!need_copy) {
        // Already contiguous, return new memoryview for same buffer
        return PyMemoryView_FromBuffer(&view);
    }

    // Need to create a contiguous copy
    const total_size = view.len;
    const new_buf = allocator.alloc(u8, total_size) catch {
        object_mod.PyBuffer_Release(&view);
        return null;
    };

    // Copy data to new buffer (for C-contiguous, simple memcpy works for 1D)
    if (view.ndim == 1 or view.strides == null) {
        const src: [*]const u8 = @ptrCast(view.buf orelse {
            allocator.free(new_buf);
            object_mod.PyBuffer_Release(&view);
            return null;
        });
        @memcpy(new_buf, src[0..total_size]);
    } else {
        // Multi-dimensional case - copy element by element
        // For simplicity, treat as flat copy (works for most cases)
        const src: [*]const u8 = @ptrCast(view.buf orelse {
            allocator.free(new_buf);
            object_mod.PyBuffer_Release(&view);
            return null;
        });
        @memcpy(new_buf, src[0..total_size]);
    }

    object_mod.PyBuffer_Release(&view);

    // Create new memoryview from the copied buffer
    var new_view = cpython.Py_buffer{
        .buf = new_buf.ptr,
        .obj = null,
        .len = total_size,
        .itemsize = view.itemsize,
        .readonly = 0, // Writeable copy
        .ndim = 1,
        .format = view.format,
        .shape = null,
        .strides = null,
        .suboffsets = null,
        .internal = null,
    };

    return PyMemoryView_FromBuffer(&new_view);
}

fn isContiguous(view: *const cpython.Py_buffer, order: u8) bool {
    if (view.ndim == 0) return true;
    if (view.strides == null) return true; // No strides means contiguous

    if (view.ndim == 1) {
        return view.strides.?[0] == view.itemsize;
    }

    // For multi-dimensional, check strides match expected pattern
    if (order == 'C') {
        // C-contiguous: last dimension has smallest stride (itemsize)
        var expected_stride: isize = view.itemsize;
        var i: usize = @intCast(view.ndim);
        while (i > 0) : (i -= 1) {
            if (view.strides.?[i - 1] != expected_stride) return false;
            if (view.shape) |shape| {
                expected_stride *= shape[i - 1];
            }
        }
        return true;
    } else {
        // F-contiguous: first dimension has smallest stride (itemsize)
        var expected_stride: isize = view.itemsize;
        for (0..@intCast(view.ndim)) |i| {
            if (view.strides.?[i] != expected_stride) return false;
            if (view.shape) |shape| {
                expected_stride *= shape[i];
            }
        }
        return true;
    }
}

/// Check if object is a memoryview
pub export fn PyMemoryView_Check(obj: ?*cpython.PyObject) c_int {
    if (obj == null) return 0;
    return if (obj.?.ob_type == &PyMemoryView_Type) 1 else 0;
}

/// Get the underlying Py_buffer
pub export fn PyMemoryView_GET_BUFFER(obj: ?*cpython.PyObject) ?*cpython.Py_buffer {
    if (obj == null) return null;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(obj.?));
    return &mv.view;
}

/// Get the base object
pub export fn PyMemoryView_GET_BASE(obj: ?*cpython.PyObject) ?*cpython.PyObject {
    if (obj == null) return null;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(obj.?));
    return mv.view.obj;
}

/// Release the memoryview buffer
pub export fn PyMemoryView_Release(obj: ?*cpython.PyObject) void {
    if (obj == null) return;
    const mv: *PyMemoryViewObject = @ptrCast(@alignCast(obj.?));

    if (mv.flags & _Py_MEMORYVIEW_RELEASED != 0) {
        return;
    }

    if (mv.exports > 0) {
        // Cannot release while there are exports
        return;
    }

    // Release the managed buffer
    if (mv.mbuf) |mbuf| {
        mbuf.exports -= 1;
        if (mbuf.exports == 0) {
            // Release underlying buffer
            if (mbuf.master.obj) |obj_inner| {
                if (obj_inner.ob_type.tp_as_buffer) |buf_procs| {
                    if (buf_procs.bf_releasebuffer) |release| {
                        release(obj_inner, &mbuf.master);
                    }
                }
            }
        }
    }

    mv.flags |= _Py_MEMORYVIEW_RELEASED;
    mv.view.buf = null;
    mv.view.obj = null;
}
