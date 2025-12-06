/// signal Module - Signal Handling
const cpython = @import("../include/object.zig");

/// Signal handler type
pub const Sighandler_t = ?*const fn (c_int) callconv(.C) void;

pub export var signalmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "signal", .m_doc = "Signal handling.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit_signal() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&signalmodule); }

/// Check for pending signals
pub export fn PyErr_CheckSignals() c_int {
    return 0;
}

/// Set interrupt handler
pub export fn PyOS_InterruptOccurred() c_int {
    return 0;
}
