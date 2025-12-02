/// Python codeop module - Compile Python code with compiler flags
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile_command", genNullPtr }, .{ "Compile", genCompile }, .{ "CommandCompiler", genCmdCompiler },
    .{ "PyCF_DONT_IMPLY_DEDENT", genI32_0x200 }, .{ "PyCF_ALLOW_INCOMPLETE_INPUT", genI32_0x4000 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .flags = @as(i32, 0) }"); }
fn genCmdCompiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .compiler = .{ .flags = @as(i32, 0) } }"); }
fn genI32_0x200(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x200)"); }
fn genI32_0x4000(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x4000)"); }
