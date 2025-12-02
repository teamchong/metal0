/// Python ast module - Abstract Syntax Trees
const std = @import("std");
const ast_types = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast_types.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genNullPtr }, .{ "literal_eval", genNullPtr }, .{ "fix_missing_locations", genNullPtr },
    .{ "increment_lineno", genNullPtr }, .{ "copy_location", genNullPtr },
    .{ "dump", genEmptyStr }, .{ "unparse", genEmptyStr },
    .{ "get_docstring", genNull }, .{ "get_source_segment", genNull },
    .{ "iter_fields", genIterFields }, .{ "iter_child_nodes", genPtrList }, .{ "walk", genPtrList },
    .{ "AST", genEmpty }, .{ "NodeVisitor", genEmpty }, .{ "NodeTransformer", genEmpty },
    .{ "Module", genModule }, .{ "Expression", genExpression }, .{ "Interactive", genInteractive },
    .{ "FunctionDef", genFunctionDef }, .{ "AsyncFunctionDef", genFunctionDef },
    .{ "ClassDef", genClassDef }, .{ "Return", genReturn }, .{ "Name", genName }, .{ "Constant", genConstant },
    .{ "PyCF_ONLY_AST", genPyCF_ONLY_AST }, .{ "PyCF_TYPE_COMMENTS", genPyCF_TYPE_COMMENTS },
});

fn genConst(self: *NativeCodegen, args: []ast_types.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNullPtr(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genNull(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmpty(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genPtrList(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "&[_]*anyopaque{}"); }
fn genIterFields(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "&[_]struct { name: []const u8, value: *anyopaque }{}"); }
fn genModule(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .body = &[_]*anyopaque{}, .type_ignores = &[_]*anyopaque{} }"); }
fn genExpression(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .body = @as(?*anyopaque, null) }"); }
fn genInteractive(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .body = &[_]*anyopaque{} }"); }
fn genFunctionDef(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }"); }
fn genClassDef(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .bases = &[_]*anyopaque{}, .keywords = &[_]*anyopaque{}, .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{} }"); }
fn genReturn(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .value = @as(?*anyopaque, null) }"); }
fn genName(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .id = \"\", .ctx = @as(?*anyopaque, null) }"); }
fn genConstant(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, ".{ .value = @as(?*anyopaque, null), .kind = @as(?[]const u8, null) }"); }
fn genPyCF_ONLY_AST(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x400)"); }
fn genPyCF_TYPE_COMMENTS(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x1000)"); }
