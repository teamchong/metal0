/// Python contextlib module - Context managers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "contextmanager", genContextmanager }, .{ "suppress", genSuppress },
    .{ "redirect_stdout", genRedirect }, .{ "redirect_stderr", genRedirect },
    .{ "closing", genClosing }, .{ "nullcontext", genNullcontext }, .{ "ExitStack", genExitStack },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genContextmanager(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap"); }
fn genSuppress(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) bool { _ = self; _ = exc; return true; } }{}"); }
fn genRedirect(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { pub fn __enter__(self: @This()) void { _ = self; } pub fn __exit__(self: @This(), exc: anytype) void { _ = self; _ = exc; } }{}"); }
fn genExitStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { stack: std.ArrayList(*anyopaque) = .{}, pub fn enter_context(__self: *@This(), cm: anytype) void { _ = __self; _ = cm; } pub fn close(__self: *@This()) void { __self.stack.deinit(__global_allocator); } }{}"); }

fn genClosing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.genExpr(args[0]);
}

fn genNullcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("null");
}
