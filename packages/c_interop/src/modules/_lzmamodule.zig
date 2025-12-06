/// _lzma Module - LZMA Compression
/// Reference: cpython/Modules/_lzmamodule.c
const cpython = @import("../include/object.zig");
pub export var _lzmamodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_lzma", .m_doc = "LZMA compression.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__lzma() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_lzmamodule); }
