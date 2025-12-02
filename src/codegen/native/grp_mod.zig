/// Python grp module - Unix group database access
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getgrnam", h.c(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }") },
    .{ "getgrgid", h.c(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }") },
    .{ "getgrall", h.c("&[_]@TypeOf(.{ .gr_name = \"\", .gr_passwd = \"\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }){}") },
    .{ "struct_group", h.c("struct { gr_name: []const u8, gr_passwd: []const u8, gr_gid: u32, gr_mem: []const []const u8 }") },
});
