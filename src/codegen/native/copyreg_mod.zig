/// Python copyreg module - Register pickle support functions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pickle", h.c("{}") }, .{ "constructor", h.pass("@as(?*const fn() anytype, null)") }, .{ "dispatch_table", h.c("hashmap_helper.AutoHashMap(usize, ?*anyopaque).init(__global_allocator)") },
    .{ "_extension_registry", h.c("hashmap_helper.StringHashMap(i32).init(__global_allocator)") },
    .{ "_inverted_registry", h.c("hashmap_helper.AutoHashMap(i32, []const u8).init(__global_allocator)") },
    .{ "_extension_cache", h.c("hashmap_helper.AutoHashMap(i32, ?*anyopaque).init(__global_allocator)") },
    .{ "add_extension", h.c("{}") }, .{ "remove_extension", h.c("{}") },
    .{ "clear_extension_cache", h.c("{}") }, .{ "__newobj__", h.wrap("newobj_blk: { const cls = ", "; break :newobj_blk cls{}; }", ".{}") }, .{ "__newobj_ex__", h.wrap("newobj_ex_blk: { const cls = ", "; break :newobj_ex_blk cls{}; }", ".{}") },
});
