/// Python copyreg module - Register pickle support functions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pickle", h.c("{}") }, .{ "constructor", h.pass("@as(?*const fn() anytype, null)") }, .{ "dispatch_table", h.c("metal0_runtime.PyDict(usize, @TypeOf(.{ null, null })).init()") },
    .{ "_extension_registry", h.c("metal0_runtime.PyDict(@TypeOf(.{ \"\", \"\" }), i32).init()") },
    .{ "_inverted_registry", h.c("metal0_runtime.PyDict(i32, @TypeOf(.{ \"\", \"\" })).init()") },
    .{ "_extension_cache", h.c("metal0_runtime.PyDict(i32, ?anyopaque).init()") },
    .{ "add_extension", h.c("{}") }, .{ "remove_extension", h.c("{}") },
    .{ "clear_extension_cache", h.c("{}") }, .{ "__newobj__", h.wrap("blk: { const cls = ", "; break :blk cls{}; }", ".{}") }, .{ "__newobj_ex__", h.wrap("blk: { const cls = ", "; break :blk cls{}; }", ".{}") },
});
