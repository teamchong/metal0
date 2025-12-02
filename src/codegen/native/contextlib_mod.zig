/// Python contextlib module - Context managers
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "contextmanager", h.c("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap") },
    .{ "suppress", h.c("struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) bool { _ = self; _ = exc; return true; } }{}") },
    .{ "redirect_stdout", h.c("struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = self; _ = exc; } }{}") },
    .{ "redirect_stderr", h.c("struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = self; _ = exc; } }{}") },
    .{ "closing", h.pass("void{}") }, .{ "nullcontext", h.pass("null") },
    .{ "ExitStack", h.c("struct { stack: std.ArrayList(*anyopaque) = .{}, pub fn enter_context(__self: *@This(), cm: anytype) void { _ = __self; _ = cm; } pub fn close(__self: *@This()) void { __self.stack.deinit(__global_allocator); } }{}") },
});
