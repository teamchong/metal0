/// _blake2 Module - BLAKE2 Hash
const cpython = @import("../include/object.zig");
pub export var blake2module: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_blake2", .m_doc = "BLAKE2 hash functions.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__blake2() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&blake2module); }
