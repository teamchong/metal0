/// readline Module - GNU Readline Interface
const cpython = @import("../include/object.zig");
pub export var readlinemodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "readline", .m_doc = "GNU readline interface.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_readline() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&readlinemodule); }
