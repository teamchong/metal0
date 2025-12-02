/// Python spwd module - Shadow password database
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getspnam", h.c("null") }, .{ "getspall", h.c("&[_]@TypeOf(.{}){}") },
    .{ "struct_spwd", h.c(".{ .sp_namp = \"\", .sp_pwdp = \"\", .sp_lstchg = 0, .sp_min = 0, .sp_max = 0, .sp_warn = 0, .sp_inact = 0, .sp_expire = 0, .sp_flag = 0 }") },
});
