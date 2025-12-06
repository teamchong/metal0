/// _ctypes/stgdict - Storage dictionary for ctypes
///
/// Implements CPython's Modules/_ctypes/stgdict.c
/// Provides StgDict - extended dictionary for ctypes type info
///
/// Reference: cpython/Modules/_ctypes/stgdict.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const ctypes = @import("ctypes.zig");

const allocator = ctypes.allocator;

// ============================================================================
// STGDICT METHODS
// ============================================================================

/// StgDict_new - Create new StgDict object
fn StgDict_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.StgDictObject), @sizeOf(ctypes.StgDictObject)) catch return null;
    const stgdict: *ctypes.StgDictObject = @ptrCast(@alignCast(mem.ptr));

    @memset(@as([*]u8, @ptrCast(stgdict))[0..@sizeOf(ctypes.StgDictObject)], 0);

    stgdict.dict.ob_base.ob_base.ob_refcnt = 1;
    stgdict.dict.ob_base.ob_base.ob_type = &PyStgDict_Type;

    return @ptrCast(stgdict);
}

/// StgDict_init - Initialize StgDict
fn StgDict_init(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = args;
    _ = kwargs;
    if (self == null) return -1;
    return 0;
}

/// StgDict_dealloc - Destructor
fn StgDict_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const stgdict: *ctypes.StgDictObject = @ptrCast(@alignCast(self.?));

    if (stgdict.proto) |p| p.ob_refcnt -= 1;
    if (stgdict.argtypes) |p| p.ob_refcnt -= 1;
    if (stgdict.converters) |p| p.ob_refcnt -= 1;
    if (stgdict.restype) |p| p.ob_refcnt -= 1;
    if (stgdict.checker) |p| p.ob_refcnt -= 1;

    if (stgdict.shape) |shape| {
        const shape_size = @as(usize, @intCast(stgdict.ndim)) * @sizeOf(isize);
        allocator.free(@as([*]u8, @ptrCast(shape))[0..shape_size]);
    }

    const ptr: [*]u8 = @ptrCast(stgdict);
    allocator.free(ptr[0..@sizeOf(ctypes.StgDictObject)]);
}

/// StgDict_clone - Clone a StgDict
pub export fn StgDict_clone(dst: ?*ctypes.StgDictObject, src: ?*ctypes.StgDictObject) callconv(.c) c_int {
    if (dst == null or src == null) return -1;

    dst.?.size = src.?.size;
    dst.?.align_val = src.?.align_val;
    dst.?.length = src.?.length;
    dst.?.ffi_type_pointer = src.?.ffi_type_pointer;
    dst.?.flags = src.?.flags;
    dst.?.ndim = src.?.ndim;
    dst.?.format = src.?.format;

    if (src.?.proto) |p| {
        p.ob_refcnt += 1;
        dst.?.proto = p;
    }
    if (src.?.argtypes) |p| {
        p.ob_refcnt += 1;
        dst.?.argtypes = p;
    }
    if (src.?.converters) |p| {
        p.ob_refcnt += 1;
        dst.?.converters = p;
    }
    if (src.?.restype) |p| {
        p.ob_refcnt += 1;
        dst.?.restype = p;
    }
    if (src.?.checker) |p| {
        p.ob_refcnt += 1;
        dst.?.checker = p;
    }

    dst.?.setfunc = src.?.setfunc;
    dst.?.getfunc = src.?.getfunc;
    dst.?.paramfunc = src.?.paramfunc;

    if (src.?.shape) |shape| {
        const shape_size = @as(usize, @intCast(src.?.ndim)) * @sizeOf(isize);
        const new_shape = allocator.alloc(isize, @intCast(src.?.ndim)) catch return -1;
        @memcpy(@as([*]u8, @ptrCast(new_shape.ptr))[0..shape_size], @as([*]u8, @ptrCast(shape))[0..shape_size]);
        dst.?.shape = new_shape.ptr;
    }

    return 0;
}

/// PyType_stgdict - Get StgDict from a type
pub export fn PyType_stgdict(type_obj: ?*cpython.PyObject) callconv(.c) ?*ctypes.StgDictObject {
    if (type_obj == null) return null;
    const py_type: *cpython.PyTypeObject = @ptrCast(@alignCast(type_obj.?));
    const dict = py_type.tp_dict orelse return null;
    if (dict.ob_type == &PyStgDict_Type) {
        return @ptrCast(@alignCast(dict));
    }
    return null;
}

/// PyObject_stgdict - Get StgDict from an object's type
pub export fn PyObject_stgdict(obj: ?*cpython.PyObject) callconv(.c) ?*ctypes.StgDictObject {
    if (obj == null) return null;
    return PyType_stgdict(@ptrCast(obj.?.ob_type));
}

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyStgDict_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_ctypes.StgDict",
    .tp_basicsize = @sizeOf(ctypes.StgDictObject),
    .tp_itemsize = 0,
    .tp_dealloc = StgDict_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Storage dictionary for ctypes types",
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
    .tp_init = StgDict_init,
    .tp_alloc = null,
    .tp_new = StgDict_new,
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
