/// _hashlib Module - OpenSSL Hash Functions
/// Reference: cpython/Modules/_hashopenssl.c
const cpython = @import("../include/object.zig");
pub export var _hashopensslmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_hashlib", .m_doc = "OpenSSL-based cryptographic hash functions.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__hashlib() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_hashopensslmodule); }
