/// xxlimited_35 Module - Limited API Test (3.5 version)
const cpython = @import("../include/object.zig");
pub export var xxlimited35module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "xxlimited_35", .m_doc = "Limited API test module (3.5).", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_xxlimited_35() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&xxlimited35module); }
