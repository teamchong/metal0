/// _scproxy Module - macOS System Configuration Proxy
/// Reference: cpython/Modules/_scproxy.c
const cpython = @import("../include/object.zig");
pub export var _scproxymodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_scproxy", .m_doc = "macOS system configuration proxy.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__scproxy() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_scproxymodule); }
