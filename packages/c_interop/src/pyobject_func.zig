/// PyFunctionObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/funcobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// PyFunctionObject - EXACT CPython layout
pub const PyFunctionObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    func_globals: ?*cpython.PyObject,
    func_builtins: ?*cpython.PyObject,
    func_name: ?*cpython.PyObject,
    func_qualname: ?*cpython.PyObject,
    func_code: ?*cpython.PyObject, // Code object
    func_defaults: ?*cpython.PyObject, // NULL or tuple
    func_kwdefaults: ?*cpython.PyObject, // NULL or dict
    func_closure: ?*cpython.PyObject, // NULL or tuple of cells
    func_doc: ?*cpython.PyObject, // __doc__
    func_dict: ?*cpython.PyObject, // __dict__
    func_weakreflist: ?*cpython.PyObject,
    func_module: ?*cpython.PyObject, // __module__
    func_annotations: ?*cpython.PyObject, // Annotations dict
    func_annotate: ?*cpython.PyObject, // Callable to fill annotations
    func_typeparams: ?*cpython.PyObject, // Tuple of type vars
    vectorcall: cpython.vectorcallfunc,
    func_version: u32,
    _pad: [4]u8 = undefined, // Alignment padding
};

/// PyFrameConstructor - frame constructor
pub const PyFrameConstructor = extern struct {
    fc_globals: ?*cpython.PyObject,
    fc_builtins: ?*cpython.PyObject,
    fc_name: ?*cpython.PyObject,
    fc_qualname: ?*cpython.PyObject,
    fc_code: ?*cpython.PyObject,
    fc_defaults: ?*cpython.PyObject,
    fc_kwdefaults: ?*cpython.PyObject,
    fc_closure: ?*cpython.PyObject,
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub var PyFunction_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "function",
    .tp_basicsize = @sizeOf(PyFunctionObject),
    .tp_itemsize = 0,
    .tp_dealloc = function_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyFunctionObject, "vectorcall"),
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
    .tp_weaklistoffset = @offsetOf(PyFunctionObject, "func_weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyFunctionObject, "func_dict"),
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

pub var PyClassMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "classmethod",
    .tp_basicsize = @sizeOf(cpython.PyObject) + @sizeOf(?*cpython.PyObject),
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "classmethod(function) -> method",
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

pub var PyStaticMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "staticmethod",
    .tp_basicsize = @sizeOf(cpython.PyObject) + @sizeOf(?*cpython.PyObject),
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "staticmethod(function) -> method",
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
// API FUNCTIONS
// ============================================================================

/// Create function from code and globals
pub export fn PyFunction_New(code: *cpython.PyObject, globals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyFunction_NewWithQualName(code, globals, null);
}

/// Create function with qualified name
pub export fn PyFunction_NewWithQualName(code: *cpython.PyObject, globals: *cpython.PyObject, qualname: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyFunctionObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyFunction_Type;
    obj.func_globals = globals;
    globals.ob_refcnt += 1;
    obj.func_builtins = null;
    obj.func_name = null;
    obj.func_qualname = qualname;
    if (qualname) |q| q.ob_refcnt += 1;
    obj.func_code = code;
    code.ob_refcnt += 1;
    obj.func_defaults = null;
    obj.func_kwdefaults = null;
    obj.func_closure = null;
    obj.func_doc = null;
    obj.func_dict = null;
    obj.func_weakreflist = null;
    obj.func_module = null;
    obj.func_annotations = null;
    obj.func_annotate = null;
    obj.func_typeparams = null;
    obj.vectorcall = null;
    obj.func_version = 0;

    return @ptrCast(&obj.ob_base);
}

/// Get code object
pub export fn PyFunction_GetCode(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_code;
}

/// Get globals dict
pub export fn PyFunction_GetGlobals(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_globals;
}

/// Get module
pub export fn PyFunction_GetModule(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_module;
}

/// Get defaults
pub export fn PyFunction_GetDefaults(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_defaults;
}

/// Set defaults
pub export fn PyFunction_SetDefaults(op: *cpython.PyObject, defaults: ?*cpython.PyObject) callconv(.c) c_int {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    if (f.func_defaults) |d| d.ob_refcnt -= 1;
    f.func_defaults = defaults;
    if (defaults) |d| d.ob_refcnt += 1;
    return 0;
}

/// Get kwdefaults
pub export fn PyFunction_GetKwDefaults(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_kwdefaults;
}

/// Set kwdefaults
pub export fn PyFunction_SetKwDefaults(op: *cpython.PyObject, kwdefaults: ?*cpython.PyObject) callconv(.c) c_int {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    if (f.func_kwdefaults) |d| d.ob_refcnt -= 1;
    f.func_kwdefaults = kwdefaults;
    if (kwdefaults) |d| d.ob_refcnt += 1;
    return 0;
}

/// Get closure
pub export fn PyFunction_GetClosure(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_closure;
}

/// Set closure
pub export fn PyFunction_SetClosure(op: *cpython.PyObject, closure: ?*cpython.PyObject) callconv(.c) c_int {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    if (f.func_closure) |c| c.ob_refcnt -= 1;
    f.func_closure = closure;
    if (closure) |c| c.ob_refcnt += 1;
    return 0;
}

/// Get annotations
pub export fn PyFunction_GetAnnotations(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    return f.func_annotations;
}

/// Set annotations
pub export fn PyFunction_SetAnnotations(op: *cpython.PyObject, annotations: ?*cpython.PyObject) callconv(.c) c_int {
    const f: *PyFunctionObject = @ptrCast(@alignCast(op));
    if (f.func_annotations) |a| a.ob_refcnt -= 1;
    f.func_annotations = annotations;
    if (annotations) |a| a.ob_refcnt += 1;
    return 0;
}

/// Type check
pub export fn PyFunction_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFunction_Type) 1 else 0;
}

/// Create classmethod
pub export fn PyClassMethod_New(callable: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = callable;
    // TODO: Implement
    return null;
}

/// Create staticmethod
pub export fn PyStaticMethod_New(callable: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = callable;
    // TODO: Implement
    return null;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn function_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const f: *PyFunctionObject = @ptrCast(@alignCast(obj));

    if (f.func_globals) |g| g.ob_refcnt -= 1;
    if (f.func_builtins) |b| b.ob_refcnt -= 1;
    if (f.func_name) |n| n.ob_refcnt -= 1;
    if (f.func_qualname) |q| q.ob_refcnt -= 1;
    if (f.func_code) |c| c.ob_refcnt -= 1;
    if (f.func_defaults) |d| d.ob_refcnt -= 1;
    if (f.func_kwdefaults) |k| k.ob_refcnt -= 1;
    if (f.func_closure) |c| c.ob_refcnt -= 1;
    if (f.func_doc) |d| d.ob_refcnt -= 1;
    if (f.func_dict) |d| d.ob_refcnt -= 1;
    if (f.func_module) |m| m.ob_refcnt -= 1;
    if (f.func_annotations) |a| a.ob_refcnt -= 1;
    if (f.func_annotate) |a| a.ob_refcnt -= 1;
    if (f.func_typeparams) |t| t.ob_refcnt -= 1;

    allocator.destroy(f);
}
