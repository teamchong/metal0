/// Python nis module - NIS (Yellow Pages) interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "match", genEmptyStr }, .{ "cat", genEmpty }, .{ "maps", genStrArr }, .{ "get_default_domain", genEmptyStr }, .{ "error", genError },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genStrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NisError"); }
