/// Python site module - Site-specific configuration hook
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "PREFIXES", h.c("runtime.NativeList.init()") },
    .{ "ENABLE_USER_SITE", h.c("true") }, .{ "USER_SITE", h.c("@as(?[]const u8, null)") },
    .{ "USER_BASE", h.c("@as(?[]const u8, null)") },
    .{ "main", h.c("{}") }, .{ "addsitedir", h.c("hashmap_helper.StringHashMap(void).init(__global_allocator)") },
    .{ "getsitepackages", h.c("runtime.NativeList.init()") },
    .{ "getuserbase", h.c("blk: { const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :blk std.fmt.allocPrint(__global_allocator, \"{s}/.local\", .{home}) catch \"\"; }") },
    .{ "getusersitepackages", h.c("blk: { const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :blk std.fmt.allocPrint(__global_allocator, \"{s}/.local/lib/python3/site-packages\", .{home}) catch \"\"; }") },
    .{ "removeduppaths", h.c("hashmap_helper.StringHashMap(void).init(__global_allocator)") },
});
