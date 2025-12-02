/// Python lib2to3 module - Python 2 to 3 conversion library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "main", genConst("0") }, .{ "refactoring_tool", genConst(".{}") }, .{ "base_fix", genConst(".{}") },
    .{ "base", genConst(".{}") }, .{ "node", genConst(".{}") }, .{ "leaf", genConst(".{}") },
    .{ "python_grammar", genConst(".{}") }, .{ "python_grammar_no_print_statement", genConst(".{}") },
});
