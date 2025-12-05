/// PyModuleObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/internal/pycore_moduleobject.h

const std = @import("std");
const cpython = @import("../include/object.zig");
const traits = @import("typetraits.zig");

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
    const pydict = @import("dictobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    const obj = allocator.create(PyModuleObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyModule_Type;

    // Create empty __dict__
    obj.md_dict = pydict.PyDict_New();

    obj.md_state = null;
    obj.md_weaklist = null;

    // Create __name__ from C string
    obj.md_name = pyunicode.PyUnicode_FromString(name);

    // Set __name__ in __dict__ too
    if (obj.md_dict != null and obj.md_name != null) {
        const name_key = pyunicode.PyUnicode_FromString("__name__");
        if (name_key) |key| {
            _ = pydict.PyDict_SetItem(obj.md_dict.?, key, obj.md_name.?);
            traits.decref(key);
        }
    }

    obj.md_token_is_def = false;
    obj.md_state_size = 0;
    obj.md_state_traverse = null;
    obj.md_state_clear = null;
    obj.md_state_free = null;
    obj.md_token = null;
    obj.md_exec = null;

    return @ptrCast(&obj.ob_base);
}

/// Create module from PyObject name
pub export fn PyModule_NewObject(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pydict = @import("dictobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    const obj = allocator.create(PyModuleObject) catch return null;

    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyModule_Type;

    // Create empty __dict__
    obj.md_dict = pydict.PyDict_New();

    obj.md_state = null;
    obj.md_weaklist = null;
    obj.md_name = traits.incref(name);

    // Set __name__ in __dict__ too
    if (obj.md_dict != null) {
        const name_key = pyunicode.PyUnicode_FromString("__name__");
        if (name_key) |key| {
            _ = pydict.PyDict_SetItem(obj.md_dict.?, key, name);
            traits.decref(key);
        }
    }

    obj.md_token_is_def = false;
    obj.md_state_size = 0;
    obj.md_state_traverse = null;
    obj.md_state_clear = null;
    obj.md_state_free = null;
    obj.md_token = null;
    obj.md_exec = null;

    return @ptrCast(&obj.ob_base);
}

// NOTE: PyModule_GetDict, PyModule_GetName, PyModule_GetState, PyModule_GetDef
// are exported from cpython_module.zig to avoid duplicate exports.
// This file provides PyModuleObject struct and PyModule_Type for the CPython 3.12 layout.

/// Get module name as object (internal helper)
pub fn getNameObject(module: *cpython.PyObject) ?*cpython.PyObject {
    const m: *PyModuleObject = @ptrCast(@alignCast(module));
    return if (m.md_name) |name| traits.incref(name) else null;
}

/// Type checks (internal - cpython_module.zig exports these)
pub fn isModule(obj: *cpython.PyObject) bool {
    return cpython.Py_TYPE(obj) == &PyModule_Type;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn module_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const m: *PyModuleObject = @ptrCast(@alignCast(obj));
    traits.decref(m.md_dict);
    traits.decref(m.md_name);
    allocator.destroy(m);
}
