/// Python site module - Site-specific configuration hook
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "PREFIXES", h.c("metal0_runtime.PyList([]const u8).init()") },
    .{ "ENABLE_USER_SITE", h.c("true") }, .{ "USER_SITE", h.c("@as(?[]const u8, null)") },
    .{ "USER_BASE", h.c("@as(?[]const u8, null)") },
    .{ "main", h.c("{}") }, .{ "addsitedir", h.c("metal0_runtime.PySet([]const u8).init()") },
    .{ "getsitepackages", h.c("metal0_runtime.PyList([]const u8).init()") },
    .{ "getuserbase", h.c("blk: { const home = std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(metal0_allocator, \"{s}/.local\", .{home}) catch \"\"; }") },
    .{ "getusersitepackages", h.c("blk: { const home = std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(metal0_allocator, \"{s}/.local/lib/python3/site-packages\", .{home}) catch \"\"; }") },
    .{ "removeduppaths", h.c("metal0_runtime.PySet([]const u8).init()") },
});
