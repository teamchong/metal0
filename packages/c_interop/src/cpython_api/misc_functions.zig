/// Miscellaneous Functions
/// PyWrapper, warning types, debug functions, Windows error stubs, and other misc APIs.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pydict = @import("../objects/dictobject.zig");
const pytuple = @import("../objects/tupleobject.zig");
const pyiter = @import("../objects/iterobject.zig");
const pymethod = @import("../objects/methodobject.zig");
const exceptions = @import("../objects/exceptions.zig");
const traits = @import("../objects/typetraits.zig");

// ============================================================================
// ADDITIONAL WARNING EXCEPTION TYPES
// ============================================================================

pub var PyExc_RuntimeWarning: cpython.PyTypeObject = makeWarningType("RuntimeWarning");
pub var PyExc_FutureWarning: cpython.PyTypeObject = makeWarningType("FutureWarning");
pub var PyExc_ImportWarning: cpython.PyTypeObject = makeWarningType("ImportWarning");

fn makeWarningType(comptime name: [:0]const u8) cpython.PyTypeObject {
    return .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1000000, .ob_type = null },
            .ob_size = 0,
        },
        .tp_name = name,
        .tp_basicsize = @sizeOf(exceptions.PyException),
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
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_BASE_EXC_SUBCLASS,
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
        .tp_base = &exceptions.PyExc_Warning,
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
}

// ============================================================================
// DICTPROXY TYPE
// ============================================================================

pub var PyDictProxy_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "mappingproxy",
    .tp_basicsize = @sizeOf(cpython.PyObject) + @sizeOf(*cpython.PyObject),
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub export fn _get_PyDictProxy_Type() callconv(.c) *cpython.PyTypeObject {
    return &PyDictProxy_Type;
}

// ============================================================================
// MISSING API FUNCTIONS
// ============================================================================

/// Py_GenericAlias - Create a generic alias (e.g., list[int])
pub export fn Py_GenericAlias(origin: *cpython.PyObject, args: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const genericalias = @import("../objects/genericaliasobject.zig");
    return genericalias.Py_GenericAlias(origin, args);
}

/// PyDictProxy_New - Create a read-only dict proxy (mappingproxy)
pub export fn PyDictProxy_New(mapping: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const descr = @import("../objects/descrobject.zig");
    return descr.PyDictProxy_New(mapping);
}

/// PySeqIter_New - Create sequence iterator
pub export fn PySeqIter_New(seq: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return pyiter.PySeqIter_New(seq);
}

/// PyMethod_New - Create bound method
pub export fn PyMethod_New(func: *cpython.PyObject, self: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return pymethod.PyMethod_New(func, self);
}

/// PyObject_SelfIter - Return object as its own iterator
pub export fn PyObject_SelfIter(obj: *cpython.PyObject) callconv(.c) *cpython.PyObject {
    traits.incref(obj);
    return obj;
}

/// PyObject_LengthHint - Get length hint (for preallocating)
pub export fn PyObject_LengthHint(obj: *cpython.PyObject, default_val: isize) callconv(.c) isize {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_as_sequence) |seq| {
        if (seq.sq_length) |len_fn| {
            const len = len_fn(obj);
            if (len >= 0) return len;
        }
    }
    return default_val;
}

/// PyObject_AsFileDescriptor - Get file descriptor from object
pub export fn PyObject_AsFileDescriptor(obj: *cpython.PyObject) callconv(.c) c_int {
    const pylong = @import("../objects/longobject.zig");
    if (pylong.PyLong_Check(obj) != 0) {
        return @intCast(pylong.PyLong_AsLong(obj));
    }
    return -1;
}

// ============================================================================
// PYWRAPPER TYPE
// ============================================================================

const PyWrapperObject = extern struct {
    ob_base: cpython.PyObject,
    descr: *cpython.PyObject,
    self: *cpython.PyObject,
};

pub var PyWrapperDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "method-wrapper",
    .tp_basicsize = @sizeOf(PyWrapperObject),
    .tp_itemsize = 0,
    .tp_dealloc = &wrapperDealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = &wrapperCall,
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

fn wrapperDealloc(obj: *cpython.PyObject) callconv(.c) void {
    const wrapper: *PyWrapperObject = @ptrCast(obj);
    traits.decref(wrapper.descr);
    traits.decref(wrapper.self);
    std.heap.c_allocator.destroy(wrapper);
}

fn wrapperCall(self: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const wrapper: *PyWrapperObject = @ptrCast(self);
    const descr_type = cpython.Py_TYPE(wrapper.descr);
    if (descr_type.tp_call) |call| {
        const self_tuple = pytuple.PyTuple_New(1) orelse return null;
        _ = pytuple.PyTuple_SetItem(self_tuple, 0, wrapper.self);
        traits.incref(wrapper.self);

        const nargs = pytuple.PyTuple_Size(args);
        const full_args = pytuple.PyTuple_New(nargs + 1) orelse return null;
        _ = pytuple.PyTuple_SetItem(full_args, 0, wrapper.self);
        traits.incref(wrapper.self);

        var i: isize = 0;
        while (i < nargs) : (i += 1) {
            if (pytuple.PyTuple_GetItem(args, i)) |item| {
                _ = pytuple.PyTuple_SetItem(full_args, i + 1, item);
                traits.incref(item);
            }
        }

        traits.decref(self_tuple);
        return call(wrapper.descr, full_args, kwargs);
    }
    return null;
}

pub export fn PyWrapper_New(descr: *cpython.PyObject, self: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const wrapper = std.heap.c_allocator.create(PyWrapperObject) catch return null;
    wrapper.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyWrapperDescr_Type,
        },
        .descr = descr,
        .self = self,
    };
    traits.incref(descr);
    traits.incref(self);
    return @ptrCast(wrapper);
}

pub export fn _get_PyWrapperDescr_Type() callconv(.c) *cpython.PyTypeObject {
    return &PyWrapperDescr_Type;
}

// ============================================================================
// DEBUG/INTERNAL REFERENCE COUNTING
// ============================================================================

pub export fn Py_DECREF_DecRefTotal() callconv(.c) void {}

pub export fn Py_DecRefShared(obj: *cpython.PyObject) callconv(.c) void {
    traits.decref(obj);
}

pub export fn Py_DecRefSharedDebug(obj: *cpython.PyObject, filename: [*:0]const u8, lineno: c_int) callconv(.c) void {
    _ = filename;
    _ = lineno;
    traits.decref(obj);
}

pub export fn Py_INCREF_IncRefTotal() callconv(.c) void {}

pub export fn Py_MergeZeroLocalRefcount(obj: *cpython.PyObject) callconv(.c) void {
    _ = obj;
}

pub export fn Py_NegativeRefcount(filename: [*:0]const u8, lineno: c_int, obj: *cpython.PyObject) callconv(.c) void {
    _ = filename;
    _ = lineno;
    _ = obj;
}

// ============================================================================
// DEPRECATED/OLD FUNCTION TYPES
// ============================================================================

pub export fn Py_OldFunction() callconv(.c) ?*cpython.PyObject {
    return null;
}

// ============================================================================
// VERSION PACKING MACROS
// ============================================================================

pub export fn Py_PACK_FULL_VERSION(major: c_int, minor: c_int, micro: c_int, level: c_int, serial: c_int) callconv(.c) c_ulong {
    return @as(c_ulong, @intCast(major)) << 24 |
        @as(c_ulong, @intCast(minor)) << 16 |
        @as(c_ulong, @intCast(micro)) << 8 |
        @as(c_ulong, @intCast(level)) << 4 |
        @as(c_ulong, @intCast(serial));
}

pub export fn Py_PACK_VERSION(major: c_int, minor: c_int) callconv(.c) c_ulong {
    return @as(c_ulong, @intCast(major)) << 24 | @as(c_ulong, @intCast(minor)) << 16;
}

// ============================================================================
// API MARKERS
// ============================================================================

pub export fn PyAPI_FUNC() callconv(.c) void {}

pub export fn Py_DEPRECATED(version: c_int) callconv(.c) void {
    _ = version;
}

pub export fn PyUnstable_Module_SetGIL(module: *cpython.PyObject, gil: c_int) callconv(.c) c_int {
    _ = module;
    _ = gil;
    return 0;
}

// ============================================================================
// WINDOWS ERROR FUNCTIONS (stubs for cross-platform compatibility)
// ============================================================================

pub export fn PyErr_SetExcFromWindowsErr(exc: *cpython.PyTypeObject, ierr: c_int) callconv(.c) ?*cpython.PyObject {
    _ = ierr;
    exceptions.PyErr_SetString(exc, "Windows error (not on Windows)");
    return null;
}

pub export fn PyErr_SetExcFromWindowsErrWithFilename(exc: *cpython.PyTypeObject, ierr: c_int, filename: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = ierr;
    _ = filename;
    exceptions.PyErr_SetString(exc, "Windows error (not on Windows)");
    return null;
}

pub export fn PyErr_SetExcFromWindowsErrWithFilenameObject(exc: *cpython.PyTypeObject, ierr: c_int, filename: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = ierr;
    _ = filename;
    exceptions.PyErr_SetString(exc, "Windows error (not on Windows)");
    return null;
}

pub export fn PyErr_SetExcFromWindowsErrWithFilenameObjects(exc: *cpython.PyTypeObject, ierr: c_int, filename: ?*cpython.PyObject, filename2: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = ierr;
    _ = filename;
    _ = filename2;
    exceptions.PyErr_SetString(exc, "Windows error (not on Windows)");
    return null;
}

pub export fn PyErr_SetFromWindowsErr(ierr: c_int) callconv(.c) ?*cpython.PyObject {
    _ = ierr;
    exceptions.PyErr_SetString(&exceptions.PyExc_OSError, "Windows error (not on Windows)");
    return null;
}

pub export fn PyErr_SetFromWindowsErrWithFilename(ierr: c_int, filename: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = ierr;
    _ = filename;
    exceptions.PyErr_SetString(&exceptions.PyExc_OSError, "Windows error (not on Windows)");
    return null;
}
