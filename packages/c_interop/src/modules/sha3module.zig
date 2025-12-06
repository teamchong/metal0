/// _sha3 Module - SHA-3 Hash Family
const cpython = @import("../include/object.zig");
pub export var sha3module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_sha3", .m_doc = "SHA-3 hash functions.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__sha3() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&sha3module); }
