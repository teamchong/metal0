/// _curses Module - Curses Terminal Interface
/// Reference: cpython/Modules/_cursesmodule.c
const cpython = @import("../include/object.zig");
pub export var _cursesmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_curses", .m_doc = "Curses terminal interface.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__curses() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_cursesmodule); }
