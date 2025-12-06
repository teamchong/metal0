/// zlib Module - Compression Library
const cpython = @import("../include/object.zig");

/// Compressor object
pub const CompObject = extern struct {
    ob_base: cpython.PyObject,
    zst: extern struct {
        next_in: ?[*]const u8,
        avail_in: c_uint,
        total_in: c_ulong,
        next_out: ?[*]u8,
        avail_out: c_uint,
        total_out: c_ulong,
        msg: ?[*:0]const u8,
        state: ?*anyopaque,
        zalloc: ?*anyopaque,
        zfree: ?*anyopaque,
        opaque: ?*anyopaque,
        data_type: c_int,
        adler: c_ulong,
        reserved: c_ulong,
    },
    unused_data: ?*cpython.PyObject,
    unconsumed_tail: ?*cpython.PyObject,
    zdict: ?*cpython.PyObject,
    eof: c_int,
    is_initialised: c_int,
    lock: ?*anyopaque,
};

pub export var zlibmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "zlib", .m_doc = "Compression and decompression using zlib.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_zlib() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&zlibmodule); }
