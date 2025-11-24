/// CPython Module System
///
/// Implements PyModule_* functions for creating and managing Python modules.
/// This is critical for loading C extensions like NumPy.

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// ============================================================================
/// MODULE TYPE OBJECTS
/// ============================================================================

/// PyModuleObject - Python module object
///
/// CPython layout from Include/moduleobject.h:
/// ```c
/// typedef struct {
///     PyObject_HEAD
///     PyObject *md_dict;
///     struct PyModuleDef *md_def;
///     void *md_state;
///     PyObject *md_weaklist;
///     PyObject *md_name;
/// } PyModuleObject;
/// ```
pub const PyModuleObject = extern struct {
    ob_base: cpython.PyObject,
    md_dict: ?*cpython.PyObject,
    md_def: ?*PyModuleDef,
    md_state: ?*anyopaque,
    md_weaklist: ?*cpython.PyObject,
    md_name: ?*cpython.PyObject,
};

/// PyModuleDef_Base - Module definition base
pub const PyModuleDef_Base = extern struct {
    ob_base: cpython.PyObject,
    m_init: ?*const fn () callconv(.c) ?*cpython.PyObject,
    m_index: isize,
    m_copy: ?*cpython.PyObject,
};

/// PyModuleDef - Module definition structure
///
/// CPython layout:
/// ```c
/// typedef struct PyModuleDef {
///     PyModuleDef_Base m_base;
///     const char *m_name;
///     const char *m_doc;
///     Py_ssize_t m_size;
///     PyMethodDef *m_methods;
///     struct PyModuleDef_Slot *m_slots;
///     traverseproc m_traverse;
///     inquiry m_clear;
///     freefunc m_free;
/// } PyModuleDef;
/// ```
pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base,
    m_name: [*:0]const u8,
    m_doc: ?[*:0]const u8,
    m_size: isize,
    m_methods: ?[*]PyMethodDef,
    m_slots: ?*anyopaque,
    m_traverse: ?*anyopaque,
    m_clear: ?*anyopaque,
    m_free: ?*anyopaque,
};

/// PyMethodDef - Method definition
///
/// CPython layout:
/// ```c
/// typedef struct PyMethodDef {
///     const char *ml_name;
///     PyCFunction ml_meth;
///     int ml_flags;
///     const char *ml_doc;
/// } PyMethodDef;
/// ```
pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8,
    ml_meth: ?PyCFunction,
    ml_flags: c_int,
    ml_doc: ?[*:0]const u8,
};

/// PyCFunction - C function pointer type
pub const PyCFunction = *const fn (?*cpython.PyObject, ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject;

/// Method flags
pub const METH_VARARGS: c_int = 0x0001;
pub const METH_KEYWORDS: c_int = 0x0002;
pub const METH_NOARGS: c_int = 0x0004;
pub const METH_O: c_int = 0x0008;

/// Dummy module type (for now)
var PyModule_Type: cpython.PyTypeObject = undefined;
var module_type_initialized = false;

fn initModuleType() void {
    if (module_type_initialized) return;

    PyModule_Type = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyModule_Type, // Self-reference
            },
            .ob_size = 0,
        },
        .tp_name = "module",
        .tp_basicsize = @sizeOf(PyModuleObject),
        .tp_itemsize = 0,
        .tp_dealloc = null,
        .tp_repr = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
    };

    module_type_initialized = true;
}

/// ============================================================================
/// MODULE CREATION FUNCTIONS
/// ============================================================================

/// Create module from definition (Python 3 API)
///
/// CPython: PyObject* PyModule_Create2(struct PyModuleDef *def, int module_api_version)
export fn PyModule_Create2(def: *PyModuleDef, api_version: c_int) callconv(.c) ?*cpython.PyObject {
    _ = api_version; // TODO: Validate API version

    initModuleType();

    // Allocate module object
    const module = allocator.create(PyModuleObject) catch return null;

    module.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = &PyModule_Type,
    };

    // Create module dict
    const dict = PyDict_New();
    if (dict == null) {
        allocator.destroy(module);
        return null;
    }

    module.md_dict = dict;
    module.md_def = def;
    module.md_state = null;
    module.md_weaklist = null;
    module.md_name = null;

    // Add __name__
    const name_obj = PyUnicode_FromString(def.m_name);
    if (name_obj) |name| {
        _ = PyDict_SetItemString(dict.?, "__name__", name);
        module.md_name = name;
    }

    // Add __doc__
    if (def.m_doc) |doc| {
        const doc_obj = PyUnicode_FromString(doc);
        if (doc_obj) |d| {
            _ = PyDict_SetItemString(dict.?, "__doc__", d);
            Py_DECREF(d);
        }
    }

    // Add methods
    if (def.m_methods) |methods| {
        var i: usize = 0;
        while (methods[i].ml_name != null) : (i += 1) {
            const method = &methods[i];
            const func = PyCFunction_NewEx(method, @ptrCast(module), null);
            if (func) |f| {
                _ = PyDict_SetItemString(dict.?, method.ml_name.?, f);
                Py_DECREF(f);
            }
        }
    }

    return @ptrCast(&module.ob_base);
}

/// Get module dictionary
///
/// CPython: PyObject* PyModule_GetDict(PyObject *module)
export fn PyModule_GetDict(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const mod = @as(*PyModuleObject, @ptrCast(module));
    return mod.md_dict;
}

/// Get module name (returns borrowed reference)
///
/// CPython: const char* PyModule_GetName(PyObject *module)
export fn PyModule_GetName(module: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    const mod = @as(*PyModuleObject, @ptrCast(module));

    if (mod.md_name) |name| {
        return PyUnicode_AsUTF8(name);
    }

    return null;
}

/// Get module filename
///
/// CPython: const char* PyModule_GetFilename(PyObject *module)
export fn PyModule_GetFilename(module: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    const mod = @as(*PyModuleObject, @ptrCast(module));

    if (mod.md_dict) |dict| {
        const filename = PyDict_GetItemString(dict, "__file__");
        if (filename) |f| {
            return PyUnicode_AsUTF8(f);
        }
    }

    return null;
}

/// Add object to module (steals reference on success)
///
/// CPython: int PyModule_AddObject(PyObject *module, const char *name, PyObject *value)
export fn PyModule_AddObject(module: *cpython.PyObject, name: [*:0]const u8, obj: *cpython.PyObject) callconv(.c) c_int {
    const mod = @as(*PyModuleObject, @ptrCast(module));

    if (mod.md_dict) |dict| {
        const result = PyDict_SetItemString(dict, name, obj);
        if (result == 0) {
            // Success - steal reference
            Py_DECREF(obj);
        }
        return result;
    }

    return -1;
}

/// Add object to module (keeps reference)
///
/// CPython: int PyModule_AddObjectRef(PyObject *module, const char *name, PyObject *value)
export fn PyModule_AddObjectRef(module: *cpython.PyObject, name: [*:0]const u8, obj: *cpython.PyObject) callconv(.c) c_int {
    const mod = @as(*PyModuleObject, @ptrCast(module));

    if (mod.md_dict) |dict| {
        return PyDict_SetItemString(dict, name, obj);
    }

    return -1;
}

/// Add integer constant to module
///
/// CPython: int PyModule_AddIntConstant(PyObject *module, const char *name, long value)
export fn PyModule_AddIntConstant(module: *cpython.PyObject, name: [*:0]const u8, value: c_long) callconv(.c) c_int {
    const int_obj = PyLong_FromLong(value);
    if (int_obj == null) return -1;

    const result = PyModule_AddObject(module, name, int_obj.?);
    if (result != 0) {
        Py_DECREF(int_obj.?);
    }

    return result;
}

/// Add string constant to module
///
/// CPython: int PyModule_AddStringConstant(PyObject *module, const char *name, const char *value)
export fn PyModule_AddStringConstant(module: *cpython.PyObject, name: [*:0]const u8, value: [*:0]const u8) callconv(.c) c_int {
    const str_obj = PyUnicode_FromString(value);
    if (str_obj == null) return -1;

    const result = PyModule_AddObject(module, name, str_obj.?);
    if (result != 0) {
        Py_DECREF(str_obj.?);
    }

    return result;
}

/// Add type to module
///
/// CPython: int PyModule_AddType(PyObject *module, PyTypeObject *type)
export fn PyModule_AddType(module: *cpython.PyObject, type_obj: *cpython.PyTypeObject) callconv(.c) c_int {
    const type_name = std.mem.span(type_obj.tp_name);

    // Find last component of dotted name
    var name_start: usize = 0;
    if (std.mem.lastIndexOf(u8, type_name, ".")) |dot_idx| {
        name_start = dot_idx + 1;
    }

    const short_name = type_name[name_start..];

    // Add to module (need null-terminated string)
    var name_buf: [256]u8 = undefined;
    if (short_name.len >= name_buf.len) return -1;

    @memcpy(name_buf[0..short_name.len], short_name);
    name_buf[short_name.len] = 0;

    return PyModule_AddObjectRef(module, @ptrCast(&name_buf), @ptrCast(&type_obj.ob_base.ob_base));
}

/// Set module docstring
///
/// CPython: int PyModule_SetDocString(PyObject *module, const char *doc)
export fn PyModule_SetDocString(module: *cpython.PyObject, doc: [*:0]const u8) callconv(.c) c_int {
    const mod = @as(*PyModuleObject, @ptrCast(module));

    if (mod.md_dict) |dict| {
        const doc_obj = PyUnicode_FromString(doc);
        if (doc_obj) |d| {
            const result = PyDict_SetItemString(dict, "__doc__", d);
            Py_DECREF(d);
            return result;
        }
    }

    return -1;
}

/// Get module state
///
/// CPython: void* PyModule_GetState(PyObject *module)
export fn PyModule_GetState(module: *cpython.PyObject) callconv(.c) ?*anyopaque {
    const mod = @as(*PyModuleObject, @ptrCast(module));
    return mod.md_state;
}

/// Get module definition
///
/// CPython: struct PyModuleDef* PyModule_GetDef(PyObject *module)
export fn PyModule_GetDef(module: *cpython.PyObject) callconv(.c) ?*PyModuleDef {
    const mod = @as(*PyModuleObject, @ptrCast(module));
    return mod.md_def;
}

/// Initialize module definition
///
/// CPython: PyObject* PyModuleDef_Init(struct PyModuleDef *def)
export fn PyModuleDef_Init(def: *PyModuleDef) callconv(.c) ?*cpython.PyObject {
    // Initialize m_base
    def.m_base.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = &PyModule_Type,
    };
    def.m_base.m_init = null;
    def.m_base.m_index = 0;
    def.m_base.m_copy = null;

    return @ptrCast(&def.m_base.ob_base);
}

/// ============================================================================
/// HELPER FUNCTIONS (External dependencies)
/// ============================================================================

extern fn PyDict_New() callconv(.c) ?*cpython.PyObject;
extern fn PyDict_SetItemString(*cpython.PyObject, [*:0]const u8, *cpython.PyObject) callconv(.c) c_int;
extern fn PyDict_GetItemString(*cpython.PyObject, [*:0]const u8) callconv(.c) ?*cpython.PyObject;
extern fn PyUnicode_FromString([*:0]const u8) callconv(.c) ?*cpython.PyObject;
extern fn PyUnicode_AsUTF8(*cpython.PyObject) callconv(.c) ?[*:0]const u8;
extern fn PyLong_FromLong(c_long) callconv(.c) ?*cpython.PyObject;
extern fn PyCFunction_NewEx(*const PyMethodDef, ?*cpython.PyObject, ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject;
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// ============================================================================
/// TESTS
/// ============================================================================

test "PyModuleDef layout" {
    // Verify sizes match CPython expectations
    try std.testing.expect(@sizeOf(PyModuleObject) > 0);
    try std.testing.expect(@sizeOf(PyModuleDef) > 0);
    try std.testing.expect(@sizeOf(PyMethodDef) > 0);
}
