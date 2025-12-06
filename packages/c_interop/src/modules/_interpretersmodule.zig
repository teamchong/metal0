/// _interpreters Module - Sub-interpreters Support
/// Reference: cpython/Modules/_interpretersmodule.c
const cpython = @import("../include/object.zig");
pub export var _interpretersmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_interpreters", .m_doc = "Sub-interpreters support.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__interpreters() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_interpretersmodule); }
