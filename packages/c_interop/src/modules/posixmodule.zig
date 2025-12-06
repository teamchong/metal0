/// posix Module - POSIX System Calls
const cpython = @import("../include/object.zig");

/// stat_result structure
pub const StatResultObject = extern struct {
    ob_base: cpython.PyObject,
    st_mode: u32,
    st_ino: u64,
    st_dev: u64,
    st_nlink: u64,
    st_uid: u32,
    st_gid: u32,
    st_size: i64,
    st_atime: i64,
    st_mtime: i64,
    st_ctime: i64,
};

pub export var posixmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "posix", .m_doc = "POSIX system calls.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_posix() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&posixmodule); }
