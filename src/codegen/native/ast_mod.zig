/// Python ast module - Abstract Syntax Trees
const std = @import("std");
const ast_types = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast_types.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genParse },
    .{ "literal_eval", genLiteral_eval },
    .{ "dump", genDump },
    .{ "unparse", genUnparse },
    .{ "fix_missing_locations", genFix_missing_locations },
    .{ "increment_lineno", genIncrement_lineno },
    .{ "copy_location", genCopy_location },
    .{ "iter_fields", genIter_fields },
    .{ "iter_child_nodes", genIter_child_nodes },
    .{ "walk", genWalk },
    .{ "get_docstring", genGet_docstring },
    .{ "get_source_segment", genGet_source_segment },
    .{ "AST", genAST },
    .{ "Module", genModule },
    .{ "Expression", genExpression },
    .{ "Interactive", genInteractive },
    .{ "FunctionDef", genFunctionDef },
    .{ "AsyncFunctionDef", genAsyncFunctionDef },
    .{ "ClassDef", genClassDef },
    .{ "Return", genReturn },
    .{ "Name", genName },
    .{ "Constant", genConstant },
    .{ "NodeVisitor", genNodeVisitor },
    .{ "NodeTransformer", genNodeTransformer },
    .{ "PyCF_ONLY_AST", genPyCF_ONLY_AST },
    .{ "PyCF_TYPE_COMMENTS", genPyCF_TYPE_COMMENTS },
});

/// Generate ast.parse(source, filename, mode, ...)
pub fn genParse(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate ast.literal_eval(node_or_string)
pub fn genLiteral_eval(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate ast.dump(node, annotate_fields=True, include_attributes=False, ...)
pub fn genDump(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ast.unparse(ast_obj) - produce source code from AST
pub fn genUnparse(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ast.fix_missing_locations(node)
pub fn genFix_missing_locations(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate ast.increment_lineno(node, n=1)
pub fn genIncrement_lineno(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate ast.copy_location(new_node, old_node)
pub fn genCopy_location(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate ast.iter_fields(node)
pub fn genIter_fields(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { name: []const u8, value: *anyopaque }{}");
}

/// Generate ast.iter_child_nodes(node)
pub fn genIter_child_nodes(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*anyopaque{}");
}

/// Generate ast.walk(node) - recursively walk AST
pub fn genWalk(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*anyopaque{}");
}

/// Generate ast.get_docstring(node, clean=True)
pub fn genGet_docstring(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ast.get_source_segment(source, node, padded=False)
pub fn genGet_source_segment(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

// ============================================================================
// AST Node type classes (stubs)
// ============================================================================

/// Generate ast.AST base class
pub fn genAST(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate ast.Module
pub fn genModule(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .body = &[_]*anyopaque{}, .type_ignores = &[_]*anyopaque{} }");
}

/// Generate ast.Expression
pub fn genExpression(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .body = @as(?*anyopaque, null) }");
}

/// Generate ast.Interactive
pub fn genInteractive(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .body = &[_]*anyopaque{} }");
}

/// Generate ast.FunctionDef
pub fn genFunctionDef(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }");
}

/// Generate ast.AsyncFunctionDef
pub fn genAsyncFunctionDef(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }");
}

/// Generate ast.ClassDef
pub fn genClassDef(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .bases = &[_]*anyopaque{}, .keywords = &[_]*anyopaque{}, .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{} }");
}

/// Generate ast.Return
pub fn genReturn(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = @as(?*anyopaque, null) }");
}

/// Generate ast.Name
pub fn genName(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .id = \"\", .ctx = @as(?*anyopaque, null) }");
}

/// Generate ast.Constant
pub fn genConstant(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = @as(?*anyopaque, null), .kind = @as(?[]const u8, null) }");
}

/// Generate ast.NodeVisitor class
pub fn genNodeVisitor(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate ast.NodeTransformer class
pub fn genNodeTransformer(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// Parse mode constants
// ============================================================================

pub fn genPyCF_ONLY_AST(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x400)");
}

pub fn genPyCF_TYPE_COMMENTS(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x1000)");
}
