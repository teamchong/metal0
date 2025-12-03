/// PyModuleObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/internal/pycore_moduleobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// PyModuleObject - EXACT CPython layout
pub const PyModuleObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    md_dict: ?*cpython.PyObject,
    md_state: ?*anyopaque,
    md_weaklist: ?*cpython.PyObject,
    md_name: ?*cpython.PyObject,
    md_token_is_def: bool,
    // Padding for alignment
    _pad1: [7]u8 = undefined,
    md_state_size: isize,
    md_state_traverse: cpython.traverseproc,
    md_state_clear: cpython.inquiry,
    md_state_free: cpython.freefunc,
    md_token: ?*anyopaque,
    md_exec: ?*const fn (*cpython.PyObject) callconv(.c) c_int,
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyModule_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "module",
    .tp_basicsize = @sizeOf(PyModuleObject),
    .tp_itemsize = 0,
    .tp_dealloc = module_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "module(name, doc=None)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyModuleObject, "md_weaklist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyModuleObject, "md_dict"),
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

pub var PyModuleDef_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "moduledef",
    .tp_basicsize = @sizeOf(cpython.PyModuleDef),
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

// ============================================================================
// API FUNCTIONS
// ============================================================================

/// Create module from name string
pub export fn PyModule_New(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyModuleObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyModule_Type;
    obj.md_dict = null; // TODO: Create empty dict
    obj.md_state = null;
    obj.md_weaklist = null;
    obj.md_name = null; // TODO: Create unicode from name
    obj.md_token_is_def = false;
    obj.md_state_size = 0;
    obj.md_state_traverse = null;
    obj.md_state_clear = null;
    obj.md_state_free = null;
    obj.md_token = null;
    obj.md_exec = null;

    _ = name;

    return @ptrCast(&obj.ob_base);
}

/// Create module from PyObject name
pub export fn PyModule_NewObject(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyModuleObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyModule_Type;
    obj.md_dict = null;
    obj.md_state = null;
    obj.md_weaklist = null;
    obj.md_name = name;
    name.ob_refcnt += 1;
    obj.md_token_is_def = false;
    obj.md_state_size = 0;
    obj.md_state_traverse = null;
    obj.md_state_clear = null;
    obj.md_state_free = null;
    obj.md_token = null;
    obj.md_exec = null;

    return @ptrCast(&obj.ob_base);
}

/// Get module dict
pub export fn PyModule_GetDict(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const m: *PyModuleObject = @ptrCast(@alignCast(module));
    return m.md_dict;
}

/// Get module name as string
pub export fn PyModule_GetName(module: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    const m: *PyModuleObject = @ptrCast(@alignCast(module));
    _ = m;
    // TODO: Get name from md_name
    return null;
}

/// Get module name as object
pub export fn PyModule_GetNameObject(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const m: *PyModuleObject = @ptrCast(@alignCast(module));
    if (m.md_name) |name| {
        name.ob_refcnt += 1;
        return name;
    }
    return null;
}

/// Get module def
pub export fn PyModule_GetDef(module: *cpython.PyObject) callconv(.c) ?*cpython.PyModuleDef {
    const m: *PyModuleObject = @ptrCast(@alignCast(module));
    if (m.md_token_is_def) {
        return @ptrCast(@alignCast(m.md_token));
    }
    return null;
}

/// Get module state
pub export fn PyModule_GetState(module: *cpython.PyObject) callconv(.c) ?*anyopaque {
    const m: *PyModuleObject = @ptrCast(@alignCast(module));
    return m.md_state;
}

/// Type checks
pub export fn PyModule_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const tp = cpython.Py_TYPE(obj);
    return if (tp == &PyModule_Type) 1 else 0;
}

pub export fn PyModule_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyModule_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn module_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const m: *PyModuleObject = @ptrCast(@alignCast(obj));
    if (m.md_dict) |d| d.ob_refcnt -= 1;
    if (m.md_name) |n| n.ob_refcnt -= 1;
    allocator.destroy(m);
}
