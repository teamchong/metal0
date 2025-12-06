/// _weakref Module - Weak References
const cpython = @import("../include/object.zig");
pub export var _weakrefmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_weakref", .m_doc = "Weak reference support.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__weakref() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_weakrefmodule); }
