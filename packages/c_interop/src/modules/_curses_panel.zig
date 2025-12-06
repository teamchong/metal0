/// _curses_panel Module - Curses Panel
/// Reference: cpython/Modules/_curses_panel.c
const cpython = @import("../include/object.zig");
pub export var _curses_panelmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_curses_panel", .m_doc = "Curses panel interface.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__curses_panel() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_curses_panelmodule); }
