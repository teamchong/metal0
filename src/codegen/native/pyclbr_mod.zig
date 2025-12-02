/// Python pyclbr module - Python class browser support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "readmodule", genReadmod }, .{ "readmodule_ex", genReadmod }, .{ "Class", genClass }, .{ "Function", genFunc },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .module = \"\", .name = \"\", .super = &[_]@TypeOf(.{}){}, .methods = .{}, .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{} }"); }
fn genFunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .module = \"\", .name = \"\", .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{}, .is_async = false }"); }
fn genReadmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const modname = "); try self.genExpr(args[0]); try self.emit("; _ = modname; break :blk .{}; }"); } else { try self.emit(".{}"); }
}
