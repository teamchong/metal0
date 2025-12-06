/// xx Module - Example Extension Module
const cpython = @import("../include/object.zig");

/// Xxo object - example object type
pub const XxoObject = extern struct {
    ob_base: cpython.PyObject,
    x_attr: ?*cpython.PyObject,
};

pub export var xxmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "xx", .m_doc = "Example extension module.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_xx() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&xxmodule); }
