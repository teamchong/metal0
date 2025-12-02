/// Python _osx_support module - macOS platform support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "find_build_tool", h.c("\"\"") }, .{ "read_output", h.c("\"\"") }, .{ "find_appropriate_compiler", h.c("\"\"") },
    .{ "remove_original_values", h.c(".{}") }, .{ "save_modified_value", h.c("{}") }, .{ "supports_universal_builds", h.c("true") },
    .{ "find_sdk_root", h.c("\"/\"") }, .{ "get_system_version", h.c("\"14.0\"") }, .{ "customize_config_vars", h.c(".{}") },
    .{ "customize_compiler", h.c("{}") }, .{ "get_platform_osx", h.c("\"darwin\"") },
});
