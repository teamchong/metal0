/// Python py_compile module - Compile Python source files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile", genNull }, .{ "main", genI32_0 }, .{ "PyCompileError", genError }, .{ "PycInvalidationMode", genMode },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[]const u8, null)"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.PyCompileError"); }
fn genMode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .TIMESTAMP = @as(i32, 1), .CHECKED_HASH = @as(i32, 2), .UNCHECKED_HASH = @as(i32, 3) }"); }
