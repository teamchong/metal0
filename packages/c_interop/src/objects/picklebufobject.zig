/// PickleBuffer Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/picklebufobject.c
/// PickleBuffer wraps a buffer-providing object for pickle protocol 5
///
/// Reference: cpython/Objects/picklebufobject.c
/// Memory layout matches CPython 3.8+ exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// PyPickleBufferObject - PickleBuffer for out-of-band data
/// Reference: cpython/Objects/picklebufobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     Py_buffer view;
///     PyObject *weakreflist;
/// } PyPickleBufferObject;
pub const PyPickleBufferObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    view: cpython.Py_buffer, // buffer view (variable size, ~88 bytes)
    weakreflist: ?*cpython.PyObject, // 8 bytes - weak references
};

// ============================================================================
// PICKLEBUFFER TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for PickleBuffer
fn picklebuf_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(self_obj.?));

    // Clear weak references
    const weakref = @import("weakrefobject.zig");
    weakref.PyObject_ClearWeakRefs(self_obj);

    // Release the buffer
    if (pb.view.obj) |obj| {
        // Call bf_releasebuffer if available
        if (obj.ob_type.tp_as_buffer) |buf_procs| {
            if (buf_procs.bf_releasebuffer) |release| {
                release(obj, &pb.view);
            }
        }
        obj.ob_refcnt -= 1;
        pb.view.obj = null;
    }

    // Free the object
    const ptr: [*]u8 = @ptrCast(pb);
    allocator.free(ptr[0..@sizeOf(PyPickleBufferObject)]);
}

/// Traverse for PickleBuffer (GC)
fn picklebuf_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (pb.view.obj) |obj| {
            const result = v(obj, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for PickleBuffer (GC)
fn picklebuf_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(self_obj.?));

    // Release the buffer
    if (pb.view.obj) |obj| {
        if (obj.ob_type.tp_as_buffer) |buf_procs| {
            if (buf_procs.bf_releasebuffer) |release| {
                release(obj, &pb.view);
            }
        }
        obj.ob_refcnt -= 1;
        pb.view.obj = null;
    }
    return 0;
}

/// Repr for PickleBuffer
fn picklebuf_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(self_obj.?));

    const pyunicode = @import("unicodeobject.zig");

    if (pb.view.obj == null) {
        return pyunicode.PyUnicode_FromString("<released PickleBuffer>");
    }

    return pyunicode.PyUnicode_FromString("<PickleBuffer>");
}

/// New for PickleBuffer
fn picklebuf_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = kwargs;

    // PickleBuffer requires a buffer-providing object argument
    if (args == null) return null;

    // Get the base object from args (first positional argument)
    const tuple = @import("tupleobject.zig");
    const size = tuple.PyTuple_Size(args.?);
    if (size < 1) return null;

    const base = tuple.PyTuple_GetItem(args.?, 0);
    if (base == null) return null;

    return PyPickleBuffer_FromObject(base);
}

/// Get buffer for PickleBuffer
fn picklebuf_getbuffer(self_obj: *cpython.PyObject, view: *cpython.Py_buffer, flags: c_int) callconv(.C) c_int {
    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(self_obj));

    if (pb.view.obj == null) {
        // Buffer has been released
        return -1;
    }

    // Check flags compatibility
    if ((flags & cpython.PyBUF_WRITABLE) != 0 and pb.view.readonly != 0) {
        return -1;
    }

    // Copy view info
    view.* = pb.view;
    view.obj = self_obj;
    self_obj.ob_refcnt += 1;

    return 0;
}

/// Release buffer for PickleBuffer
fn picklebuf_releasebuffer(self_obj: *cpython.PyObject, view: *cpython.Py_buffer) callconv(.C) void {
    _ = self_obj;
    _ = view;
    // Nothing to do - the actual buffer is owned by the underlying object
}

/// Buffer procs for PickleBuffer
var picklebuf_as_buffer = cpython.PyBufferProcs{
    .bf_getbuffer = picklebuf_getbuffer,
    .bf_releasebuffer = picklebuf_releasebuffer,
};

/// PyPickleBuffer_Type - the PickleBuffer type object
pub export var PyPickleBuffer_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "pickle.PickleBuffer",
    .tp_basicsize = @sizeOf(PyPickleBufferObject),
    .tp_itemsize = 0,
    .tp_dealloc = picklebuf_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = picklebuf_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null, // Unhashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = &picklebuf_as_buffer,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Wrapper for a buffer object to be pickled with protocol 5 and above.",
    .tp_traverse = picklebuf_traverse,
    .tp_clear = picklebuf_clear,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyPickleBufferObject, "weakreflist"),
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
    .tp_new = picklebuf_new,
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

/// Check if object is a PickleBuffer
pub export fn PyPickleBuffer_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &PyPickleBuffer_Type) 1 else 0;
}

/// Create a PickleBuffer from a buffer-providing object
pub export fn PyPickleBuffer_FromObject(base: ?*cpython.PyObject) ?*cpython.PyObject {
    if (base == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyPickleBufferObject), @sizeOf(PyPickleBufferObject)) catch return null;
    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(mem.ptr));

    pb.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyPickleBuffer_Type,
        },
        .view = .{},
        .weakreflist = null,
    };

    // Get buffer from base object
    if (base.?.ob_type.tp_as_buffer) |buf_procs| {
        if (buf_procs.bf_getbuffer) |getbuffer| {
            if (getbuffer(base.?, &pb.view, cpython.PyBUF_SIMPLE) != 0) {
                const ptr: [*]u8 = @ptrCast(pb);
                allocator.free(ptr[0..@sizeOf(PyPickleBufferObject)]);
                return null;
            }
        } else {
            const ptr: [*]u8 = @ptrCast(pb);
            allocator.free(ptr[0..@sizeOf(PyPickleBufferObject)]);
            return null;
        }
    } else {
        const ptr: [*]u8 = @ptrCast(pb);
        allocator.free(ptr[0..@sizeOf(PyPickleBufferObject)]);
        return null;
    }

    return @ptrCast(pb);
}

/// Get the buffer from a PickleBuffer
pub export fn PyPickleBuffer_GetBuffer(op: ?*cpython.PyObject) ?*const cpython.Py_buffer {
    if (op == null) return null;
    if (PyPickleBuffer_Check(op) == 0) return null;

    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(op.?));

    if (pb.view.obj == null) {
        // Buffer has been released
        return null;
    }

    return &pb.view;
}

/// Release the buffer held by a PickleBuffer
pub export fn PyPickleBuffer_Release(op: ?*cpython.PyObject) c_int {
    if (op == null) return -1;
    if (PyPickleBuffer_Check(op) == 0) return -1;

    const pb: *PyPickleBufferObject = @ptrCast(@alignCast(op.?));

    if (pb.view.obj) |obj| {
        if (obj.ob_type.tp_as_buffer) |buf_procs| {
            if (buf_procs.bf_releasebuffer) |release| {
                release(obj, &pb.view);
            }
        }
        obj.ob_refcnt -= 1;
        pb.view.obj = null;
        pb.view.buf = null;
    }

    return 0;
}
