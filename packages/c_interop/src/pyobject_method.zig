/// PyCFunctionObject / PyCMethodObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/methodobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// PyCFunctionObject - EXACT CPython layout
pub const PyCFunctionObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    m_ml: ?*cpython.PyMethodDef, // Description of C function
    m_self: ?*cpython.PyObject, // Passed as 'self' to C func
    m_module: ?*cpython.PyObject, // The __module__ attribute
    m_weakreflist: ?*cpython.PyObject, // List of weak references
    vectorcall: cpython.vectorcallfunc,
};

/// PyCMethodObject - bound method with class
pub const PyCMethodObject = extern struct {
    func: PyCFunctionObject, // Base
    mm_class: ?*cpython.PyTypeObject, // Class that defines this method
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub var PyCFunction_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "builtin_function_or_method",
    .tp_basicsize = @sizeOf(PyCFunctionObject),
    .tp_itemsize = 0,
    .tp_dealloc = cfunction_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyCFunctionObject, "vectorcall"),
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
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyCFunctionObject, "m_weakreflist"),
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

pub var PyCMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "builtin_method",
    .tp_basicsize = @sizeOf(PyCMethodObject),
    .tp_itemsize = 0,
    .tp_dealloc = cmethod_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyCFunctionObject, "vectorcall"),
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
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyCFunctionObject, "m_weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyCFunction_Type,
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
// API FUNCTIONS
// ============================================================================

/// Create new CFunction from method def and self
pub export fn PyCFunction_NewEx(ml: *cpython.PyMethodDef, self: ?*cpython.PyObject, module: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyCFunctionObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyCFunction_Type;
    obj.m_ml = ml;
    obj.m_self = self;
    obj.m_module = module;
    obj.m_weakreflist = null;
    obj.vectorcall = null;

    if (self) |s| s.ob_refcnt += 1;
    if (module) |m| m.ob_refcnt += 1;

    return @ptrCast(&obj.ob_base);
}

/// Create new CFunction (simplified)
pub export fn PyCFunction_New(ml: *cpython.PyMethodDef, self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyCFunction_NewEx(ml, self, null);
}

/// Get the function pointer
pub export fn PyCFunction_GetFunction(op: *cpython.PyObject) callconv(.c) ?*anyopaque {
    const cf: *PyCFunctionObject = @ptrCast(@alignCast(op));
    if (cf.m_ml) |ml| {
        return ml.ml_meth;
    }
    return null;
}

/// Get self object
pub export fn PyCFunction_GetSelf(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const cf: *PyCFunctionObject = @ptrCast(@alignCast(op));
    return cf.m_self;
}

/// Get flags
pub export fn PyCFunction_GetFlags(op: *cpython.PyObject) callconv(.c) c_int {
    const cf: *PyCFunctionObject = @ptrCast(@alignCast(op));
    if (cf.m_ml) |ml| {
        return ml.ml_flags;
    }
    return 0;
}

/// Type checks
pub export fn PyCFunction_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCFunction_Type) 1 else 0;
}

pub export fn PyCMethod_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCMethod_Type) 1 else 0;
}

pub export fn PyCMethod_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCMethod_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn cfunction_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const cf: *PyCFunctionObject = @ptrCast(@alignCast(obj));
    if (cf.m_self) |s| s.ob_refcnt -= 1;
    if (cf.m_module) |m| m.ob_refcnt -= 1;
    allocator.destroy(cf);
}

fn cmethod_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const cm: *PyCMethodObject = @ptrCast(@alignCast(obj));
    if (cm.func.m_self) |s| s.ob_refcnt -= 1;
    if (cm.func.m_module) |m| m.ob_refcnt -= 1;
    allocator.destroy(cm);
}

// ============================================================================
// TESTS
// ============================================================================

test "PyCFunctionObject layout" {
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(PyCFunctionObject));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyCFunctionObject, "m_ml"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyCFunctionObject, "m_self"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyCFunctionObject, "m_module"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(PyCFunctionObject, "m_weakreflist"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(PyCFunctionObject, "vectorcall"));
}
