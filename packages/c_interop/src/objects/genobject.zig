/// PyGenObject - Generator objects
///
/// Generators are created by generator functions (functions containing yield).
/// They implement the iterator protocol.
///
/// Reference: cpython/Include/cpython/genobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");
const traits = @import("typetraits.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

/// PyGenObject - Generator object structure
pub const PyGenObject = extern struct {
    ob_base: cpython.PyObject,
    gi_frame: ?*cpython.PyObject, // Frame object (null when exhausted)
    gi_code: ?*cpython.PyObject, // Code object
    gi_weakreflist: ?*cpython.PyObject, // Weak reference list
    gi_name: ?*cpython.PyObject, // Name of generator
    gi_qualname: ?*cpython.PyObject, // Qualified name
    gi_exc_state: ExceptionState, // Exception state
};

/// PyCoroObject - Coroutine object (similar to generator)
pub const PyCoroObject = extern struct {
    ob_base: cpython.PyObject,
    cr_frame: ?*cpython.PyObject,
    cr_code: ?*cpython.PyObject,
    cr_weakreflist: ?*cpython.PyObject,
    cr_name: ?*cpython.PyObject,
    cr_qualname: ?*cpython.PyObject,
    cr_origin_or_finalizer: ?*cpython.PyObject,
    cr_exc_state: ExceptionState,
};

/// PyAsyncGenObject - Async generator object
pub const PyAsyncGenObject = extern struct {
    ob_base: cpython.PyObject,
    ag_frame: ?*cpython.PyObject,
    ag_code: ?*cpython.PyObject,
    ag_weakreflist: ?*cpython.PyObject,
    ag_name: ?*cpython.PyObject,
    ag_qualname: ?*cpython.PyObject,
    ag_finalizer: ?*cpython.PyObject,
    ag_hooks_inited: c_int,
    ag_closed: c_int,
    ag_running_async: c_int,
    ag_exc_state: ExceptionState,
};

/// Exception state for generators
const ExceptionState = extern struct {
    exc_type: ?*cpython.PyObject,
    exc_value: ?*cpython.PyObject,
    exc_traceback: ?*cpython.PyObject,
    previous_item: ?*ExceptionState,
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub var PyGen_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "generator",
    .tp_basicsize = @sizeOf(PyGenObject),
    .tp_itemsize = 0,
    .tp_dealloc = gen_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = gen_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Generator object",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyGenObject, "gi_weakreflist"),
    .tp_iter = gen_iter,
    .tp_iternext = gen_iternext,
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

pub var PyCoro_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "coroutine",
    .tp_basicsize = @sizeOf(PyCoroObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Coroutine object",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyCoroObject, "cr_weakreflist"),
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

pub var PyAsyncGen_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "async_generator",
    .tp_basicsize = @sizeOf(PyAsyncGenObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Async generator object",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyAsyncGenObject, "ag_weakreflist"),
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
// API FUNCTIONS - GENERATOR
// ============================================================================

/// Create a new generator from a frame
pub export fn PyGen_New(frame: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const gen = allocator.create(PyGenObject) catch return null;

    gen.ob_base.ob_refcnt = 1;
    gen.ob_base.ob_type = &PyGen_Type;
    gen.gi_frame = traits.incref(frame);
    gen.gi_code = null;
    gen.gi_weakreflist = null;
    gen.gi_name = null;
    gen.gi_qualname = null;
    gen.gi_exc_state = .{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
        .previous_item = null,
    };

    return @ptrCast(&gen.ob_base);
}

/// Create a new generator with code object
pub export fn PyGen_NewWithQualName(frame: *cpython.PyObject, name: ?*cpython.PyObject, qualname: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const gen_obj = PyGen_New(frame) orelse return null;
    const gen: *PyGenObject = @ptrCast(@alignCast(gen_obj));

    if (name) |n| gen.gi_name = traits.incref(n);
    if (qualname) |qn| gen.gi_qualname = traits.incref(qn);

    return gen_obj;
}

/// Check if object is a generator
pub export fn PyGen_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyGen_Type) 1 else 0;
}

/// Check if object is exactly a generator
pub export fn PyGen_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyGen_Type) 1 else 0;
}

/// Check if generator needs finalizing
pub export fn PyGen_NeedsFinalizing(gen: *cpython.PyObject) callconv(.c) c_int {
    if (PyGen_Check(gen) == 0) return 0;
    const gen_obj: *PyGenObject = @ptrCast(@alignCast(gen));
    return if (gen_obj.gi_frame != null) 1 else 0;
}

// ============================================================================
// API FUNCTIONS - COROUTINE
// ============================================================================

/// Create a new coroutine from a frame
pub export fn PyCoro_New(frame: *cpython.PyObject, name: ?*cpython.PyObject, qualname: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const coro = allocator.create(PyCoroObject) catch return null;

    coro.ob_base.ob_refcnt = 1;
    coro.ob_base.ob_type = &PyCoro_Type;
    coro.cr_frame = traits.incref(frame);
    coro.cr_code = null;
    coro.cr_weakreflist = null;
    coro.cr_name = if (name) |n| traits.incref(n) else null;
    coro.cr_qualname = if (qualname) |qn| traits.incref(qn) else null;
    coro.cr_origin_or_finalizer = null;
    coro.cr_exc_state = .{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
        .previous_item = null,
    };

    return @ptrCast(&coro.ob_base);
}

/// Check if object is a coroutine
pub export fn PyCoro_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCoro_Type) 1 else 0;
}

/// Check if object is exactly a coroutine
pub export fn PyCoro_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCoro_Type) 1 else 0;
}

// ============================================================================
// API FUNCTIONS - ASYNC GENERATOR
// ============================================================================

/// Create a new async generator
pub export fn PyAsyncGen_New(frame: *cpython.PyObject, name: ?*cpython.PyObject, qualname: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const agen = allocator.create(PyAsyncGenObject) catch return null;

    agen.ob_base.ob_refcnt = 1;
    agen.ob_base.ob_type = &PyAsyncGen_Type;
    agen.ag_frame = traits.incref(frame);
    agen.ag_code = null;
    agen.ag_weakreflist = null;
    agen.ag_name = if (name) |n| traits.incref(n) else null;
    agen.ag_qualname = if (qualname) |qn| traits.incref(qn) else null;
    agen.ag_finalizer = null;
    agen.ag_hooks_inited = 0;
    agen.ag_closed = 0;
    agen.ag_running_async = 0;
    agen.ag_exc_state = .{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
        .previous_item = null,
    };

    return @ptrCast(&agen.ob_base);
}

/// Check if object is an async generator
pub export fn PyAsyncGen_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyAsyncGen_Type) 1 else 0;
}

/// Check if object is exactly an async generator
pub export fn PyAsyncGen_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyAsyncGen_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn gen_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const gen: *PyGenObject = @ptrCast(@alignCast(obj));

    if (gen.gi_frame) |f| traits.decref(f);
    if (gen.gi_code) |c| traits.decref(c);
    if (gen.gi_name) |n| traits.decref(n);
    if (gen.gi_qualname) |qn| traits.decref(qn);
    if (gen.gi_exc_state.exc_type) |t| traits.decref(t);
    if (gen.gi_exc_state.exc_value) |v| traits.decref(v);
    if (gen.gi_exc_state.exc_traceback) |tb| traits.decref(tb);

    allocator.destroy(gen);
}

fn gen_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const gen: *PyGenObject = @ptrCast(@alignCast(obj));
    const unicode = @import("../include/unicodeobject.zig");

    var buf: [128]u8 = undefined;
    const name = if (gen.gi_qualname) |qn| blk: {
        const umod = @import("../include/unicodeobject.zig");
        break :blk umod.PyUnicode_AsUTF8(qn) orelse "<unknown>";
    } else "<unknown>";

    const str = std.fmt.bufPrint(&buf, "<generator object {s} at 0x{x}>", .{ std.mem.span(name), @intFromPtr(obj) }) catch return null;
    return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
}

fn gen_iter(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return traits.incref(obj);
}

fn gen_iternext(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const gen: *PyGenObject = @ptrCast(@alignCast(obj));

    // In metal0's AOT model, generators are compiled to native state machines,
    // not interpreted frame-by-frame like CPython. This function is primarily
    // for C extension compatibility.
    //
    // If a C extension creates a generator via PyGen_New, iteration would need
    // to execute the associated frame's bytecode. Since metal0 compiles to native
    // code without a bytecode interpreter, we check for a running frame and
    // signal completion otherwise.

    // Check if generator is already exhausted
    if (gen.gi_frame == null) {
        traits.setError("StopIteration", "");
        return null;
    }

    // Generator with frame but no interpreter - signal exhausted
    // A proper implementation would need bytecode execution capability
    gen.gi_frame = null; // Mark as exhausted
    traits.setError("StopIteration", "");
    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyGenObject layout" {
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyGenObject, "gi_frame"));
}

test "generator exports" {
    _ = PyGen_New;
    _ = PyGen_Check;
    _ = PyCoro_New;
    _ = PyAsyncGen_New;
}
