/// unicodedata Module - Unicode Character Database
const cpython = @import("../include/object.zig");

/// UCD object for specific Unicode version
pub const UCDObject = extern struct {
    ob_base: cpython.PyObject,
    version: [*:0]const u8,
};

pub export var unicodedatamodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "unicodedata", .m_doc = "Unicode character database.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_unicodedata() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&unicodedatamodule); }
