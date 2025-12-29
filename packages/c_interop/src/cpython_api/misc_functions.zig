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

// ============================================================================
// INTERNAL FUNCTIONS REQUIRED BY NUMPY
// ============================================================================

/// _Py_ascii_whitespace - ASCII whitespace character table
/// Each byte is 1 if the character at that index is whitespace, 0 otherwise
pub export var _Py_ascii_whitespace: [256]u8 = blk: {
    var table = [_]u8{0} ** 256;
    // Standard ASCII whitespace: space, tab, newline, carriage return, vertical tab, form feed
    table[' '] = 1;
    table['\t'] = 1;
    table['\n'] = 1;
    table['\r'] = 1;
    table[0x0b] = 1; // vertical tab
    table[0x0c] = 1; // form feed
    break :blk table;
};

/// _PyErr_BadInternalCall - Report internal error
pub export fn _PyErr_BadInternalCall(filename: [*:0]const u8, lineno: c_int) callconv(.c) void {
    _ = filename;
    _ = lineno;
    exceptions.PyErr_SetString(&exceptions.PyExc_SystemError, "bad argument to internal function");
}

/// _PyObject_CallFunction_SizeT - Call function with size_t-aware argument parsing
pub export fn _PyObject_CallFunction_SizeT(callable: *cpython.PyObject, format: ?[*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    const abstract = @import("../include/abstract.zig");
    if (format == null) {
        // No arguments, call with empty tuple
        const empty_tuple = @import("../objects/tupleobject.zig").PyTuple_New(0) orelse return null;
        return abstract.PyObject_Call(callable, empty_tuple, null);
    }
    // Build args from format
    var va = @cVaStart();
    defer @cVaEnd(&va);
    const args = @import("../include/modsupport.zig").Py_VaBuildValue(format.?, &va) orelse return null;
    // If args is a tuple, use directly; otherwise wrap in tuple
    if (@import("../objects/tupleobject.zig").PyTuple_Check(args) != 0) {
        return abstract.PyObject_Call(callable, args, null);
    }
    const tuple = @import("../objects/tupleobject.zig").PyTuple_Pack(1, args) orelse return null;
    return abstract.PyObject_Call(callable, tuple, null);
}

/// _PyObject_CallMethod_SizeT - Call method with size_t-aware argument parsing
pub export fn _PyObject_CallMethod_SizeT(obj: *cpython.PyObject, name: [*:0]const u8, format: ?[*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    const abstract = @import("../include/abstract.zig");
    const method = abstract.PyObject_GetAttrString(obj, name) orelse return null;
    if (format == null) {
        const empty_tuple = @import("../objects/tupleobject.zig").PyTuple_New(0) orelse return null;
        return abstract.PyObject_Call(method, empty_tuple, null);
    }
    var va = @cVaStart();
    defer @cVaEnd(&va);
    const args = @import("../include/modsupport.zig").Py_VaBuildValue(format.?, &va) orelse return null;
    if (@import("../objects/tupleobject.zig").PyTuple_Check(args) != 0) {
        return abstract.PyObject_Call(method, args, null);
    }
    const tuple = @import("../objects/tupleobject.zig").PyTuple_Pack(1, args) orelse return null;
    return abstract.PyObject_Call(method, tuple, null);
}

/// _PyObject_LookupAttr - Look up attribute, don't raise AttributeError if not found
/// Returns: 1 if attribute found (stored in *result), 0 if not found, -1 on error
pub export fn _PyObject_LookupAttr(obj: *cpython.PyObject, name: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    const abstract = @import("../include/abstract.zig");
    result.* = abstract.PyObject_GetAttr(obj, name);
    if (result.* != null) {
        return 1; // Found
    }
    // Check if it was an AttributeError (not found) or real error
    if (exceptions.PyErr_Occurred()) |exc| {
        if (exceptions.PyErr_GivenExceptionMatches(exc, @ptrCast(&exceptions.PyExc_AttributeError)) != 0) {
            exceptions.PyErr_Clear();
            return 0; // Not found, no error
        }
        return -1; // Real error
    }
    return 0; // Not found
}

// ============================================================================
// PANDAS/PYTORCH COMPATIBILITY (additional internal APIs)
// ============================================================================

/// _Py_FatalErrorFunc - Fatal error function pointer (stub)
pub export var _Py_FatalErrorFunc: ?*const fn ([*:0]const u8) callconv(.c) noreturn = null;

/// _PyByteArray_empty_string - Empty bytearray singleton
pub export var _PyByteArray_empty_string: [1]u8 = .{0};

/// _PyLong_Copy - Copy a long object
pub export fn _PyLong_Copy(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pylong = @import("../objects/longobject.zig");
    if (pylong.PyLong_Check(obj) == 0) return null;
    const val = pylong.PyLong_AsLongLong(obj);
    return pylong.PyLong_FromLongLong(val);
}

/// _PyObject_GenericGetAttrWithDict - Get attr with custom dict
pub export fn _PyObject_GenericGetAttrWithDict(obj: *cpython.PyObject, name: *cpython.PyObject, dict: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = dict; // Use object's own dict
    const abstract = @import("../include/abstract.zig");
    return abstract.PyObject_GenericGetAttr(obj, name);
}

/// _PyObject_GetDictPtr - Get pointer to object's __dict__
pub export fn _PyObject_GetDictPtr(obj: *cpython.PyObject) callconv(.c) ?*?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_dictoffset == 0) return null;
    const offset: usize = if (type_obj.tp_dictoffset > 0)
        @intCast(type_obj.tp_dictoffset)
    else
        @intCast(@as(isize, @intCast(@sizeOf(cpython.PyObject))) + type_obj.tp_dictoffset);
    const base: [*]u8 = @ptrCast(obj);
    return @ptrCast(@alignCast(base + offset));
}

/// _PySet_NextEntry - Iterate over set entries (internal API)
pub export fn _PySet_NextEntry(set_obj: *cpython.PyObject, pos: *isize, key: *?*cpython.PyObject, hash: *isize) callconv(.c) c_int {
    const setobject = @import("../objects/setobject.zig");
    // Use PySet_Next which has similar semantics
    if (setobject.PySet_Next(set_obj, pos, key) != 0) {
        // Compute hash of key
        if (key.*) |k| {
            hash.* = @import("../include/abstract.zig").PyObject_Hash(k);
        }
        return 1;
    }
    return 0;
}

/// _PyType_Lookup - Look up attribute in type's MRO
pub export fn _PyType_Lookup(type_obj: *cpython.PyTypeObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Check type's tp_dict first
    if (type_obj.tp_dict) |dict| {
        const pydict = @import("../objects/dictobject.zig");
        if (pydict.PyDict_GetItem(@ptrCast(dict), name)) |val| {
            return val;
        }
    }
    // Check base types
    if (type_obj.tp_base) |base| {
        return _PyType_Lookup(base, name);
    }
    return null;
}

/// _PyUnicode_FastCopyCharacters - Fast character copy (internal)
pub export fn _PyUnicode_FastCopyCharacters(to: *cpython.PyObject, to_start: isize, from: *cpython.PyObject, from_start: isize, how_many: isize) callconv(.c) c_int {
    // Our unicode implementation is immutable, so this is a no-op stub
    _ = to;
    _ = to_start;
    _ = from;
    _ = from_start;
    _ = how_many;
    return 0; // Success (nothing to copy in immutable strings)
}

/// PyObject_CallFinalizerFromDealloc - Call tp_finalize from dealloc
pub export fn PyObject_CallFinalizerFromDealloc(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_finalize) |finalize| {
        finalize(obj);
    }
    return 0;
}

/// PyUnicode_New - Create new unicode object with given size and maxchar
pub export fn PyUnicode_New(size: isize, maxchar: u32) callconv(.c) ?*cpython.PyObject {
    _ = maxchar; // We use UTF-8 internally, maxchar is for optimization
    if (size <= 0) {
        return @import("../objects/unicodeobject.zig").PyUnicode_FromString("");
    }
    // Allocate buffer and return empty unicode that can be written to
    const buf = std.heap.c_allocator.alloc(u8, @intCast(size + 1)) catch return null;
    @memset(buf, 0);
    return @import("../objects/unicodeobject.zig").PyUnicode_FromString(@ptrCast(buf.ptr));
}

/// PyByteArray_Type - bytearray type object
pub export var PyByteArray_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "bytearray",
    .tp_basicsize = @sizeOf(cpython.PyObject) + @sizeOf(isize) + @sizeOf([*]u8),
    .tp_itemsize = 1,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "bytearray()",
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

// ============================================================================
// PYTORCH COMPATIBILITY (additional type objects and APIs)
// ============================================================================

/// PyCell_Type - cell type object
pub export var PyCell_Type: cpython.PyTypeObject = makeSimpleType("cell");

/// PyFrame_Type - frame type object
pub export var PyFrame_Type: cpython.PyTypeObject = makeSimpleType("frame");

/// PyFunction_Type - function type object
pub export var PyFunction_Type: cpython.PyTypeObject = makeSimpleType("function");

/// PyGen_Type - generator type object
pub export var PyGen_Type: cpython.PyTypeObject = makeSimpleType("generator");

/// PyModule_Type - module type object
pub export var PyModule_Type: cpython.PyTypeObject = makeSimpleType("module");

/// PyStaticMethod_Type - staticmethod type object
pub export var PyStaticMethod_Type: cpython.PyTypeObject = makeSimpleType("staticmethod");

fn makeSimpleType(comptime name: [:0]const u8) cpython.PyTypeObject {
    return .{
        .ob_base = .{
            .ob_base = .{ .ob_refcnt = 1000000, .ob_type = null },
            .ob_size = 0,
        },
        .tp_name = name,
        .tp_basicsize = @sizeOf(cpython.PyObject),
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
}

/// Dict watcher stubs (3.12+ feature, not implemented)
pub export fn PyDict_AddWatcher(callback: ?*anyopaque) callconv(.c) c_int {
    _ = callback;
    return 0; // Return watcher ID 0
}

pub export fn PyDict_Watch(watcher_id: c_int, dict: *cpython.PyObject) callconv(.c) c_int {
    _ = watcher_id;
    _ = dict;
    return 0; // Success
}

pub export fn PyDict_Unwatch(watcher_id: c_int, dict: *cpython.PyObject) callconv(.c) c_int {
    _ = watcher_id;
    _ = dict;
    return 0; // Success
}

/// Thread state stubs
pub export fn _PyThreadState_GetCurrent() callconv(.c) ?*anyopaque {
    return null; // No thread state in AOT
}

pub export fn PyThreadState_DeleteCurrent() callconv(.c) void {
    // No-op
}

pub export fn PyThreadState_Next(tstate: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = tstate;
    return null; // No next thread state
}

pub export fn PyInterpreterState_ThreadHead(interp: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = interp;
    return null; // No thread head
}

/// Eval stubs (interpreter internals)
pub export fn _Py_NewReference(obj: *cpython.PyObject) callconv(.c) void {
    obj.ob_refcnt = 1;
}

pub export fn _PyEval_EvalFrameDefault(tstate: ?*anyopaque, frame: ?*anyopaque, throwflag: c_int) callconv(.c) ?*cpython.PyObject {
    _ = tstate;
    _ = frame;
    _ = throwflag;
    return null; // Not implemented - AOT doesn't use frame evaluation
}

pub export fn _PyEval_SliceIndex(obj: *cpython.PyObject, result: *isize) callconv(.c) c_int {
    const pylong = @import("../objects/longobject.zig");
    if (pylong.PyLong_Check(obj) != 0) {
        result.* = pylong.PyLong_AsSsize_t(obj);
        return 1;
    }
    return 0;
}

pub export fn _PyInterpreterState_GetEvalFrameFunc(interp: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = interp;
    return null;
}

pub export fn _PyInterpreterState_SetEvalFrameFunc(interp: ?*anyopaque, func: ?*anyopaque) callconv(.c) void {
    _ = interp;
    _ = func;
}

pub export fn PyEval_SetProfile(func: ?*anyopaque, arg: ?*cpython.PyObject) callconv(.c) void {
    _ = func;
    _ = arg;
    // Profiling not supported in AOT
}

pub export fn PyObject_GET_WEAKREFS_LISTPTR(obj: *cpython.PyObject) callconv(.c) ?*?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_weaklistoffset == 0) return null;
    const offset: usize = @intCast(type_obj.tp_weaklistoffset);
    const base: [*]u8 = @ptrCast(obj);
    return @ptrCast(@alignCast(base + offset));
}

pub export fn PyObject_GetArenaAllocator(allocator_ptr: ?*anyopaque) callconv(.c) void {
    _ = allocator_ptr;
    // Arena allocator not exposed in AOT
}

pub export fn PyUnstable_Eval_RequestCodeExtraIndex(func: ?*anyopaque) callconv(.c) isize {
    _ = func;
    return -1; // Not implemented
}

/// PyTraceBack_Type - traceback type object
pub export var PyTraceBack_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "traceback",
    .tp_basicsize = @sizeOf(cpython.PyObject) + 4 * @sizeOf(*cpython.PyObject),
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
