/// Python _posixshmem module - POSIX shared memory
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "shm_open", h.c("-1") },
    .{ "shm_unlink", h.c("{}") },
});
