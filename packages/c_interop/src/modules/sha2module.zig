/// _sha2 Module - SHA-2 Hash Family (SHA-256, SHA-512)
const cpython = @import("../include/object.zig");
pub export var sha2module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_sha2", .m_doc = "SHA-2 hash functions (SHA-256, SHA-512).", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__sha2() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&sha2module); }
