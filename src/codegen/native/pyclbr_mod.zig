/// Python pyclbr module - Python class browser support
const std = @import("std");
const h = @import("mod_helper.zig");

const genReadmod = h.wrap("blk: { const modname = ", "; _ = modname; break :blk .{}; }", ".{}");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "readmodule", genReadmod }, .{ "readmodule_ex", genReadmod },
    .{ "Class", h.c(".{ .module = \"\", .name = \"\", .super = &[_]@TypeOf(.{}){}, .methods = .{}, .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{} }") },
    .{ "Function", h.c(".{ .module = \"\", .name = \"\", .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{}, .is_async = false }") },
});
