/// itertools Module - Iterator Tools C Implementation
/// Implements CPython's Modules/itertoolsmodule.c
/// Reference: cpython/Modules/itertoolsmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var itertoolsmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "itertools",
    .m_doc = "Functional tools for creating and using iterators.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit_itertools() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&itertoolsmodule);
}
