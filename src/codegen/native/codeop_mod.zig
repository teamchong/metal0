/// Python codeop module - Compile Python code with compiler flags
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile_command", genConst("@as(?*anyopaque, null)") }, .{ "Compile", genConst(".{ .flags = @as(i32, 0) }") },
    .{ "CommandCompiler", genConst(".{ .compiler = .{ .flags = @as(i32, 0) } }") },
    .{ "PyCF_DONT_IMPLY_DEDENT", genConst("@as(i32, 0x200)") }, .{ "PyCF_ALLOW_INCOMPLETE_INPUT", genConst("@as(i32, 0x4000)") },
});
