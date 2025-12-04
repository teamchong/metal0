/// PyCFunctionObject / PyCMethodObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/methodobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

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

    if (self) |s| _ = traits.incref(s);
    if (module) |m| _ = traits.incref(m);

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
// BOUND METHOD (PyMethod) - wraps function + self
// ============================================================================

/// PyMethodObject - bound method
pub const PyMethodObject = extern struct {
    ob_base: cpython.PyObject,
    im_func: ?*cpython.PyObject, // The callable (function)
    im_self: ?*cpython.PyObject, // The instance (bound to)
    im_weakreflist: ?*cpython.PyObject,
};

pub var PyMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "method",
    .tp_basicsize = @sizeOf(PyMethodObject),
    .tp_itemsize = 0,
    .tp_dealloc = method_dealloc,
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
};

/// Create bound method from function and self
pub export fn PyMethod_New(func: *cpython.PyObject, self: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyMethodObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyMethod_Type;
    obj.im_func = func;
    obj.im_self = self;
    obj.im_weakreflist = null;

    _ = traits.incref(func);
    _ = traits.incref(self);

    return @ptrCast(&obj.ob_base);
}

/// Get the function object from bound method
pub export fn PyMethod_Function(method: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const m: *PyMethodObject = @ptrCast(@alignCast(method));
    return m.im_func;
}

/// Get the self object from bound method
pub export fn PyMethod_Self(method: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const m: *PyMethodObject = @ptrCast(@alignCast(method));
    return m.im_self;
}

/// Check if object is a bound method
pub export fn PyMethod_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyMethod_Type) 1 else 0;
}

fn method_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const m: *PyMethodObject = @ptrCast(@alignCast(obj));
    if (m.im_func) |f| traits.decref(f);
    if (m.im_self) |s| traits.decref(s);
    allocator.destroy(m);
}

// ============================================================================
// INSTANCE METHOD (PyInstanceMethod) - unbound method descriptor
// ============================================================================

/// PyInstanceMethodObject - instance method descriptor
pub const PyInstanceMethodObject = extern struct {
    ob_base: cpython.PyObject,
    func: ?*cpython.PyObject,
};

pub var PyInstanceMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "instancemethod",
    .tp_basicsize = @sizeOf(PyInstanceMethodObject),
    .tp_itemsize = 0,
    .tp_dealloc = instancemethod_dealloc,
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
    .tp_descr_get = instancemethod_descr_get,
};

/// Create instance method from function
pub export fn PyInstanceMethod_New(func: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyInstanceMethodObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyInstanceMethod_Type;
    obj.func = func;

    _ = traits.incref(func);

    return @ptrCast(&obj.ob_base);
}

/// Get the function from instance method
pub export fn PyInstanceMethod_Function(im: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj: *PyInstanceMethodObject = @ptrCast(@alignCast(im));
    return obj.func;
}

/// Macro form - no type checking
pub export fn PyInstanceMethod_GET_FUNCTION(im: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj: *PyInstanceMethodObject = @ptrCast(@alignCast(im));
    return obj.func;
}

/// Check if object is instance method
pub export fn PyInstanceMethod_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyInstanceMethod_Type) 1 else 0;
}

fn instancemethod_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(obj));
    if (im.func) |f| traits.decref(f);
    allocator.destroy(im);
}

fn instancemethod_descr_get(descr: *cpython.PyObject, obj: ?*cpython.PyObject, type_: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = type_;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(descr));

    if (obj == null) {
        // Unbound - return the function
        if (im.func) |f| {
            _ = traits.incref(f);
            return f;
        }
        return null;
    }

    // Bound - create bound method
    if (im.func) |f| {
        return PyMethod_New(f, obj.?);
    }
    return null;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn cfunction_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const cf: *PyCFunctionObject = @ptrCast(@alignCast(obj));
    if (cf.m_self) |s| traits.decref(s);
    if (cf.m_module) |m| traits.decref(m);
    allocator.destroy(cf);
}

fn cmethod_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const cm: *PyCMethodObject = @ptrCast(@alignCast(obj));
    if (cm.func.m_self) |s| traits.decref(s);
    if (cm.func.m_module) |m| traits.decref(m);
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
