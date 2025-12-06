/// _bz2 Module - BZ2 Compression
/// Reference: cpython/Modules/_bz2module.c
const cpython = @import("../include/object.zig");
pub export var _bz2module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_bz2", .m_doc = "BZ2 compression interface.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__bz2() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_bz2module); }
