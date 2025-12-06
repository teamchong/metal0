/// _asyncio Module - Asyncio C Accelerator
///
/// Implements CPython's Modules/_asynciomodule.c
/// Provides C acceleration for the asyncio module (Future, Task types)
///
/// Reference: cpython/Modules/_asynciomodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// FUTURE STATE
// ============================================================================

pub const FutureState = enum(c_int) {
    PENDING = 0,
    CANCELLED = 1,
    FINISHED = 2,
};

// ============================================================================
// FUTURE OBJECT
// ============================================================================

/// FutureObj - C implementation of asyncio.Future
pub const FutureObj = extern struct {
    ob_base: cpython.PyObject,
    state: c_int, // FutureState
    result: ?*cpython.PyObject,
    exception: ?*cpython.PyObject,
    callbacks: ?*cpython.PyObject, // List of callbacks
    loop: ?*cpython.PyObject, // Event loop
    source_traceback: ?*cpython.PyObject,
    cancel_message: ?*cpython.PyObject,
    weakreflist: ?*cpython.PyObject,
};

/// Create a new Future object
pub export fn _asyncio_Future_new(loop: ?*cpython.PyObject) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(FutureObj), @sizeOf(FutureObj)) catch return null;
    const fut: *FutureObj = @ptrCast(@alignCast(mem.ptr));

    fut.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &FutureType },
        .state = @intFromEnum(FutureState.PENDING),
        .result = null,
        .exception = null,
        .callbacks = null,
        .loop = loop,
        .source_traceback = null,
        .cancel_message = null,
        .weakreflist = null,
    };

    if (loop) |l| {
        l.ob_refcnt += 1;
    }

    return @ptrCast(fut);
}

/// Future.result() - Get the result of the future
fn future_result(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const fut: *FutureObj = @ptrCast(@alignCast(self_obj.?));

    if (fut.state == @intFromEnum(FutureState.PENDING)) {
        // Future is not done yet - would raise InvalidStateError
        return null;
    }

    if (fut.state == @intFromEnum(FutureState.CANCELLED)) {
        // Future was cancelled - would raise CancelledError
        return null;
    }

    if (fut.exception) |exc| {
        // Future has an exception - would raise it
        _ = exc;
        return null;
    }

    if (fut.result) |result| {
        result.ob_refcnt += 1;
        return result;
    }

    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// Future.done() - Check if the future is done
fn future_done(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const fut: *FutureObj = @ptrCast(@alignCast(self_obj.?));

    const pybool = @import("../objects/boolobject.zig");
    return if (fut.state != @intFromEnum(FutureState.PENDING)) pybool.Py_True else pybool.Py_False;
}

/// Future.cancelled() - Check if the future was cancelled
fn future_cancelled(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const fut: *FutureObj = @ptrCast(@alignCast(self_obj.?));

    const pybool = @import("../objects/boolobject.zig");
    return if (fut.state == @intFromEnum(FutureState.CANCELLED)) pybool.Py_True else pybool.Py_False;
}

/// Future dealloc
fn future_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const fut: *FutureObj = @ptrCast(@alignCast(self_obj.?));

    if (fut.result) |r| r.ob_refcnt -= 1;
    if (fut.exception) |e| e.ob_refcnt -= 1;
    if (fut.callbacks) |c| c.ob_refcnt -= 1;
    if (fut.loop) |l| l.ob_refcnt -= 1;
    if (fut.source_traceback) |t| t.ob_refcnt -= 1;
    if (fut.cancel_message) |m| m.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(fut);
    allocator.free(ptr[0..@sizeOf(FutureObj)]);
}

// ============================================================================
// TASK OBJECT
// ============================================================================

/// TaskObj - C implementation of asyncio.Task
pub const TaskObj = extern struct {
    fut: FutureObj, // Inherits from Future
    coro: ?*cpython.PyObject, // Coroutine
    name: ?*cpython.PyObject, // Task name
    context: ?*cpython.PyObject, // Context
    must_cancel: c_int,
    log_destroy_pending: c_int,
};

/// Create a new Task object
pub export fn _asyncio_Task_new(coro: ?*cpython.PyObject, loop: ?*cpython.PyObject, name: ?*cpython.PyObject) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(TaskObj), @sizeOf(TaskObj)) catch return null;
    const task: *TaskObj = @ptrCast(@alignCast(mem.ptr));

    task.* = .{
        .fut = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &TaskType },
            .state = @intFromEnum(FutureState.PENDING),
            .result = null,
            .exception = null,
            .callbacks = null,
            .loop = loop,
            .source_traceback = null,
            .cancel_message = null,
            .weakreflist = null,
        },
        .coro = coro,
        .name = name,
        .context = null,
        .must_cancel = 0,
        .log_destroy_pending = 1,
    };

    if (coro) |c| c.ob_refcnt += 1;
    if (loop) |l| l.ob_refcnt += 1;
    if (name) |n| n.ob_refcnt += 1;

    return @ptrCast(task);
}

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var FutureType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_asyncio.Future",
    .tp_basicsize = @sizeOf(FutureObj),
    .tp_itemsize = 0,
    .tp_dealloc = future_dealloc,
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
    .tp_doc = "C implementation of asyncio.Future",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(FutureObj, "weakreflist"),
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

pub export var TaskType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_asyncio.Task",
    .tp_basicsize = @sizeOf(TaskObj),
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
    .tp_doc = "C implementation of asyncio.Task",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(TaskObj, "fut") + @offsetOf(FutureObj, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &FutureType,
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
// MODULE FUNCTIONS
// ============================================================================

/// Get the running event loop
pub export fn _asyncio_get_running_loop(self: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    // Would return the currently running loop or None
    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// Get the current event loop
pub export fn _asyncio_get_event_loop(self: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    // Would return the current loop or create a new one
    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _asynciomodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_asyncio",
    .m_doc = "Accelerator module for asyncio",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__asyncio() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_asynciomodule);
}
