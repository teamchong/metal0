/// Python platform module - Access to underlying platform's identifying data
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "system", h.c("@tagName(@import(\"builtin\").os.tag)") },
    .{ "machine", h.c("@tagName(@import(\"builtin\").cpu.arch)") },
    .{ "node", h.c("\"localhost\"") },
    .{ "release", h.c("\"\"") }, .{ "version", h.c("\"\"") },
    .{ "platform", h.c("@tagName(@import(\"builtin\").os.tag) ++ \"-\" ++ @tagName(@import(\"builtin\").cpu.arch)") },
    .{ "processor", h.c("@tagName(@import(\"builtin\").cpu.arch)") },
    .{ "python_implementation", h.c("\"metal0\"") },
    .{ "python_version", h.c("\"3.12.0\"") },
    .{ "python_version_tuple", h.c(".{ \"3\", \"12\", \"0\" }") },
    .{ "python_branch", h.c("\"\"") }, .{ "python_revision", h.c("\"\"") },
    .{ "python_build", h.c(".{ \"\", \"\" }") },
    .{ "python_compiler", h.c("\"Zig\"") },
    .{ "uname", h.c("struct { system: []const u8 = @tagName(@import(\"builtin\").os.tag), node: []const u8 = \"localhost\", release: []const u8 = \"\", version: []const u8 = \"\", machine: []const u8 = @tagName(@import(\"builtin\").cpu.arch), processor: []const u8 = @tagName(@import(\"builtin\").cpu.arch) }{}") },
    .{ "architecture", h.c(".{ \"64bit\", \"\" }") },
    .{ "mac_ver", h.c(".{ \"\", .{ \"\", \"\", \"\" }, \"\" }") },
    .{ "win32_ver", h.c(".{ \"\", \"\", \"\", \"\" }") },
    .{ "win32_edition", h.c("\"\"") }, .{ "win32_is_iot", h.c("false") },
    .{ "libc_ver", h.c(".{ \"glibc\", \"\" }") },
    .{ "freedesktop_os_release", h.c("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
});
