/// _ctypes/callbacks - Callback implementation
///
/// Implements CPython's Modules/_ctypes/callbacks.c
/// Provides callback thunks for Python functions called from C
///
/// Reference: cpython/Modules/_ctypes/callbacks.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const ctypes = @import("ctypes.zig");

const allocator = ctypes.allocator;

// ============================================================================
// CALLBACK THUNK METHODS
// ============================================================================

/// CThunk_new - Create new callback thunk
fn CThunk_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.CThunkObject), @sizeOf(ctypes.CThunkObject)) catch return null;
    const thunk: *ctypes.CThunkObject = @ptrCast(@alignCast(mem.ptr));

    thunk.* = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyCThunk_Type }, .ob_size = 0 },
        .pcl_write = null,
        .pcl_exec = null,
        .cif = undefined,
        .flags = 0,
        .converters = null,
        .callable = null,
        .restype = null,
        .setfunc = null,
        .ffi_restype = null,
        .atypes = .{null},
    };

    return @ptrCast(thunk);
}

/// CThunk_dealloc - Destructor
fn CThunk_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const thunk: *ctypes.CThunkObject = @ptrCast(@alignCast(self.?));

    if (thunk.converters) |p| p.ob_refcnt -= 1;
    if (thunk.callable) |p| p.ob_refcnt -= 1;
    if (thunk.restype) |p| p.ob_refcnt -= 1;

    // Free closure memory if allocated
    // In CPython this uses ffi_closure_free

    const ptr: [*]u8 = @ptrCast(thunk);
    allocator.free(ptr[0..@sizeOf(ctypes.CThunkObject)]);
}

/// CThunk_traverse - GC traversal
fn CThunk_traverse(self: ?*cpython.PyObject, visit: ?*const fn (?*cpython.PyObject, ?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) c_int {
    if (self == null) return 0;
    const thunk: *ctypes.CThunkObject = @ptrCast(@alignCast(self.?));

    if (thunk.converters) |p| {
        if (visit) |v| {
            const result = v(p, arg);
            if (result != 0) return result;
        }
    }
    if (thunk.callable) |p| {
        if (visit) |v| {
            const result = v(p, arg);
            if (result != 0) return result;
        }
    }
    if (thunk.restype) |p| {
        if (visit) |v| {
            const result = v(p, arg);
            if (result != 0) return result;
        }
    }

    return 0;
}

/// CThunk_clear - Clear references for GC
fn CThunk_clear(self: ?*cpython.PyObject) callconv(.c) c_int {
    if (self == null) return 0;
    const thunk: *ctypes.CThunkObject = @ptrCast(@alignCast(self.?));

    if (thunk.converters) |p| {
        p.ob_refcnt -= 1;
        thunk.converters = null;
    }
    if (thunk.callable) |p| {
        p.ob_refcnt -= 1;
        thunk.callable = null;
    }
    if (thunk.restype) |p| {
        p.ob_refcnt -= 1;
        thunk.restype = null;
    }

    return 0;
}

// ============================================================================
// CALLBACK CREATION
// ============================================================================

/// _ctypes_alloc_callback - Allocate a callback thunk
pub export fn _ctypes_alloc_callback(
    callable: ?*cpython.PyObject,
    converters: ?*cpython.PyObject,
    restype: ?*cpython.PyObject,
    flags: c_int,
) callconv(.c) ?*ctypes.CThunkObject {
    if (callable == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.CThunkObject), @sizeOf(ctypes.CThunkObject)) catch return null;
    const thunk: *ctypes.CThunkObject = @ptrCast(@alignCast(mem.ptr));

    thunk.* = .{
        .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyCThunk_Type }, .ob_size = 0 },
        .pcl_write = null,
        .pcl_exec = null,
        .cif = undefined,
        .flags = flags,
        .converters = converters,
        .callable = callable,
        .restype = restype,
        .setfunc = null,
        .ffi_restype = null,
        .atypes = .{null},
    };

    // Incref referenced objects
    if (callable != null) callable.?.ob_refcnt += 1;
    if (converters != null) converters.?.ob_refcnt += 1;
    if (restype != null) restype.?.ob_refcnt += 1;

    // TODO: Allocate ffi closure and set up callback trampoline
    // This requires platform-specific code using libffi

    return thunk;
}

/// _ctypes_free_callback - Free a callback thunk
pub export fn _ctypes_free_callback(thunk: ?*ctypes.CThunkObject) callconv(.c) void {
    if (thunk == null) return;
    CThunk_dealloc(@ptrCast(thunk));
}

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyCThunk_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_ctypes.CThunk",
    .tp_basicsize = @sizeOf(ctypes.CThunkObject),
    .tp_itemsize = @sizeOf(?*anyopaque),
    .tp_dealloc = CThunk_dealloc,
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
    .tp_doc = "CThunk callback object",
    .tp_traverse = CThunk_traverse,
    .tp_clear = CThunk_clear,
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
    .tp_new = CThunk_new,
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
