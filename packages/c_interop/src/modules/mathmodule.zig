/// math Module - Math Functions C Implementation
/// Implements CPython's Modules/mathmodule.c
/// Reference: cpython/Modules/mathmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var mathmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "math",
    .m_doc = "Mathematical functions defined by the C standard.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit_math() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&mathmodule);
}
