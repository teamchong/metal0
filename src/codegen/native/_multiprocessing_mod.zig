/// Python _multiprocessing module - Internal multiprocessing support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sem_lock", h.c(".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }") }, .{ "sem_unlink", h.c("{}") }, .{ "address_of_buffer", h.c(".{ @as(usize, 0), @as(usize, 0) }") },
    .{ "flags", h.c(".{ .HAVE_SEM_OPEN = true, .HAVE_SEM_TIMEDWAIT = true, .HAVE_FD_TRANSFER = true, .HAVE_BROKEN_SEM_GETVALUE = false }") },
    .{ "connection", h.c(".{ .handle = null, .readable = true, .writable = true }") }, .{ "send", h.c("{}") }, .{ "recv", h.c("null") },
    .{ "poll", h.c("false") }, .{ "send_bytes", h.c("{}") }, .{ "recv_bytes", h.c("\"\"") },
    .{ "recv_bytes_into", h.c("@as(usize, 0)") }, .{ "close", h.c("{}") }, .{ "fileno", h.I32(-1) },
    .{ "acquire", h.c("true") }, .{ "release", h.c("{}") }, .{ "count", h.I32(0) }, .{ "is_mine", h.c("false") },
    .{ "get_value", h.I32(1) }, .{ "is_zero", h.c("false") }, .{ "rebuild", h.c(".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }") },
});
