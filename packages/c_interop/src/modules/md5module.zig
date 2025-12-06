/// _md5 Module - MD5 Hash
const cpython = @import("../include/object.zig");
pub export var md5module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_md5", .m_doc = "MD5 hash function.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__md5() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&md5module); }
