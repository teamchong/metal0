/// Python linecache module - Random access to text lines
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getline", h.c("\"\"") }, .{ "getlines", h.c("&[_][]const u8{}") },
    .{ "clearcache", h.c("{}") }, .{ "checkcache", h.c("{}") },
    .{ "updatecache", h.c("&[_][]const u8{}") }, .{ "lazycache", h.c("false") },
    .{ "cache", h.c("hashmap_helper.StringHashMap([][]const u8).init(__global_allocator)") },
});
