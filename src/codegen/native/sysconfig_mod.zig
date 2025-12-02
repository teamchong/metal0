/// Python sysconfig module - Python configuration information
const std = @import("std");
const h = @import("mod_helper.zig");

const configVarBody = "; if (std.mem.eql(u8, name, \"prefix\")) break :blk \"/usr/local\" else if (std.mem.eql(u8, name, \"exec_prefix\")) break :blk \"/usr/local\" else if (std.mem.eql(u8, name, \"EXT_SUFFIX\")) break :blk \".so\" else break :blk null; }";
const getPathBody = "; if (std.mem.eql(u8, name, \"stdlib\")) break :blk \"/usr/local/lib/python3.12\" else if (std.mem.eql(u8, name, \"purelib\")) break :blk \"/usr/local/lib/python3.12/site-packages\" else if (std.mem.eql(u8, name, \"scripts\")) break :blk \"/usr/local/bin\" else break :blk null; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_config_vars", h.c(".{ .prefix = \"/usr/local\", .exec_prefix = \"/usr/local\", .py_version = \"3.12\", .py_version_short = \"3.12\", .py_version_nodot = \"312\", .installed_base = \"/usr/local\", .installed_platbase = \"/usr/local\", .platbase = \"/usr/local\", .projectbase = \"/usr/local\", .abiflags = \"\", .SOABI = \"cpython-312\", .EXT_SUFFIX = \".so\" }") },
    .{ "get_config_var", h.wrap("blk: { const name = ", configVarBody, "null") },
    .{ "get_scheme_names", h.c("&[_][]const u8{ \"posix_home\", \"posix_prefix\", \"posix_user\", \"nt\", \"nt_user\", \"osx_framework_user\" }") },
    .{ "get_default_scheme", h.c("\"posix_prefix\"") }, .{ "get_preferred_scheme", h.c("\"posix_prefix\"") },
    .{ "get_path_names", h.c("&[_][]const u8{ \"stdlib\", \"platstdlib\", \"purelib\", \"platlib\", \"include\", \"platinclude\", \"scripts\", \"data\" }") },
    .{ "get_paths", h.c(".{ .stdlib = \"/usr/local/lib/python3.12\", .platstdlib = \"/usr/local/lib/python3.12\", .purelib = \"/usr/local/lib/python3.12/site-packages\", .platlib = \"/usr/local/lib/python3.12/site-packages\", .include = \"/usr/local/include/python3.12\", .platinclude = \"/usr/local/include/python3.12\", .scripts = \"/usr/local/bin\", .data = \"/usr/local\" }") },
    .{ "get_path", h.wrap("blk: { const name = ", getPathBody, "null") },
    .{ "get_python_lib", h.c("\"/usr/local/lib/python3.12/site-packages\"") },
    .{ "get_platform", h.c("\"darwin-arm64\"") },
    .{ "get_makefile_filename", h.c("\"/usr/local/lib/python3.12/config-3.12/Makefile\"") },
    .{ "parse_config_h", h.c(".{}") }, .{ "is_python_build", h.c("false") },
});
