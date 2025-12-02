/// Python lib2to3 module - Python 2 to 3 conversion library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "main", genI64_0 }, .{ "refactoring_tool", genEmpty }, .{ "base_fix", genEmpty }, .{ "base", genEmpty }, .{ "node", genEmpty }, .{ "leaf", genEmpty }, .{ "python_grammar", genEmpty }, .{ "python_grammar_no_print_statement", genEmpty },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
