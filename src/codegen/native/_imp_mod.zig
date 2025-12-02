/// Python _imp module - Internal import machinery support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "lock_held", h.c("false") }, .{ "acquire_lock", h.c("{}") }, .{ "release_lock", h.c("{}") },
    .{ "get_frozen_object", h.c("null") }, .{ "is_frozen", h.c("false") }, .{ "is_builtin", h.I32(0) },
    .{ "is_frozen_package", h.c("false") }, .{ "create_builtin", h.c("null") }, .{ "create_dynamic", h.c("null") },
    .{ "exec_builtin", h.I32(0) }, .{ "exec_dynamic", h.I32(0) }, .{ "extension_suffixes", h.c("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }") },
    .{ "source_hash", h.c("\"\\x00\" ** 8") }, .{ "check_hash_based_pycs", h.c("\"default\"") },
});
