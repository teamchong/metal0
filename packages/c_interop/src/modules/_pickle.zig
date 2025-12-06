/// _pickle Module - Pickle C Accelerator
/// Implements CPython's Modules/_pickle.c
/// Reference: cpython/Modules/_pickle.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var _picklemodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_pickle",
    .m_doc = "Optimized pickle implementation.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__pickle() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_picklemodule);
}
