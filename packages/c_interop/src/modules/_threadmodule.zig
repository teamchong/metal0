/// _thread Module - Threading Primitives C Implementation
/// Implements CPython's Modules/_threadmodule.c
/// Reference: cpython/Modules/_threadmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var _threadmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_thread",
    .m_doc = "This module provides primitive operations to write multi-threaded programs.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__thread() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_threadmodule);
}
