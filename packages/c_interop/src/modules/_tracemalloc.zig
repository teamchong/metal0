/// _tracemalloc Module - Memory Tracing
const cpython = @import("../include/object.zig");
pub export var _tracemallocmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_tracemalloc", .m_doc = "Memory allocation tracing.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__tracemalloc() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_tracemallocmodule); }
