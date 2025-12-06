/// _remote_debugging Module - Remote Debugging
/// Reference: cpython/Modules/_remote_debugging_module.c
const cpython = @import("../include/object.zig");
pub export var _remote_debugging_module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_remote_debugging", .m_doc = "Remote debugging support.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__remote_debugging() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_remote_debugging_module); }
