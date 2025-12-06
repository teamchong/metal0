/// _struct Module - Struct Packing/Unpacking C Implementation
/// Implements CPython's Modules/_struct.c
/// Reference: cpython/Modules/_struct.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var _structmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_struct",
    .m_doc = "Functions to convert between Python values and C structs.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__struct() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_structmodule);
}
