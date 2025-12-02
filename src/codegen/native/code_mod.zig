/// Python code module - Interactive interpreter base classes
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "InteractiveConsole", h.c(".{ .locals = @as(?*anyopaque, null), .filename = \"<console>\" }") },
    .{ "InteractiveInterpreter", h.c(".{ .locals = @as(?*anyopaque, null) }") },
    .{ "compile_command", h.c("@as(?*anyopaque, null)") },
    .{ "interact", h.c("{}") },
});
