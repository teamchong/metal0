/// _random Module - Random Number Generator C Implementation
/// Implements CPython's Modules/_randommodule.c (Mersenne Twister)
/// Reference: cpython/Modules/_randommodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub export var _randommodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_random",
    .m_doc = "Random number generator.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__random() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_randommodule);
}
