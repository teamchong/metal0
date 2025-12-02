/// Python py_compile module - Compile Python source files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile", genConst("@as(?[]const u8, null)") },
    .{ "main", genConst("@as(i32, 0)") },
    .{ "PyCompileError", genConst("error.PyCompileError") },
    .{ "PycInvalidationMode", genConst(".{ .TIMESTAMP = @as(i32, 1), .CHECKED_HASH = @as(i32, 2), .UNCHECKED_HASH = @as(i32, 3) }") },
});
