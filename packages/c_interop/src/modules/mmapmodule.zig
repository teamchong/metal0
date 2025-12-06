/// mmap Module - Memory-Mapped Files
const cpython = @import("../include/object.zig");

/// mmap object
pub const MmapObject = extern struct {
    ob_base: cpython.PyObject,
    data: ?[*]u8,
    size: isize,
    pos: isize,
    exports: c_int,
    access: c_int,
    fd: c_int,
};

pub export var mmapmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "mmap", .m_doc = "Memory-mapped file support.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_mmap() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&mmapmodule); }
