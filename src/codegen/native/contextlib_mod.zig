/// Python contextlib module - Context managers
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "contextmanager", h.c("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap") },
    .{ "suppress", h.c("struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) bool { _ = self; _ = exc; return true; } }{}") },
    .{ "redirect_stdout", h.c("struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = self; _ = exc; } }{}") },
    .{ "redirect_stderr", h.c("struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = self; _ = exc; } }{}") },
    .{ "closing", genClosing }, .{ "nullcontext", genNullcontext },
    .{ "ExitStack", h.c("struct { stack: std.ArrayList(*anyopaque) = .{}, pub fn enter_context(__self: *@This(), cm: anytype) void { _ = __self; _ = cm; } pub fn close(__self: *@This()) void { __self.stack.deinit(__global_allocator); } }{}") },
});

fn genClosing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.genExpr(args[0]);
}

fn genNullcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("null");
}
