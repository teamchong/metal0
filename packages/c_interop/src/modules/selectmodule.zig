/// select Module - I/O Multiplexing C Implementation
/// Implements CPython's Modules/selectmodule.c
/// Reference: cpython/Modules/selectmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var selectmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "select",
    .m_doc = "Wait for I/O completion on multiple streams.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit_select() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&selectmodule);
}
