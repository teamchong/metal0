/// Python pwd module - Unix password database access
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpwnam", h.c(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }") },
    .{ "getpwuid", h.c(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }") },
    .{ "getpwall", h.c("&[_]@TypeOf(.{ .pw_name = \"\", .pw_passwd = \"\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"\", .pw_shell = \"\" }){}") },
    .{ "struct_passwd", h.c("struct { pw_name: []const u8, pw_passwd: []const u8, pw_uid: u32, pw_gid: u32, pw_gecos: []const u8, pw_dir: []const u8, pw_shell: []const u8 }") },
});
