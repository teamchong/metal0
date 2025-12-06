/// pyexpat Module - Expat XML Parser
const cpython = @import("../include/object.zig");

/// XMLParser object
pub const XMLParserObject = extern struct {
    ob_base: cpython.PyObject,
    itself: ?*anyopaque, // XML_Parser
    handlers: [22]?*cpython.PyObject,
    buffer: ?[*]u8,
    buffer_size: isize,
    buffer_used: isize,
    ordered_attributes: c_int,
    specified_attributes: c_int,
    in_callback: c_int,
    intern: ?*cpython.PyObject,
};

pub export var pyexpatmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "pyexpat", .m_doc = "Expat XML parser.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_pyexpat() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&pyexpatmodule); }
