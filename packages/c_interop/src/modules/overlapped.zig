/// _overlapped Module - Windows Overlapped I/O (stub for non-Windows)
const cpython = @import("../include/object.zig");
pub export var overlappedmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_overlapped", .m_doc = "Overlapped I/O support (Windows).", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__overlapped() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&overlappedmodule); }
