/// Python ast module - Abstract Syntax Trees
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", genParse },
    .{ "literal_eval", genLiteralEval },
    .{ "fix_missing_locations", genFixMissingLocations },
    .{ "increment_lineno", genIncrementLineno },
    .{ "copy_location", genCopyLocation },
    .{ "dump", genDump },
    .{ "unparse", genUnparse },
    .{ "get_docstring", genGetDocstring },
    .{ "get_source_segment", genGetSourceSegment },
    .{ "iter_fields", genIterFields },
    .{ "iter_child_nodes", genIterChildNodes },
    .{ "walk", genWalk },
    .{ "AST", genAst },
    .{ "NodeVisitor", genNodeVisitor },
    .{ "NodeTransformer", genNodeTransformer },
    .{ "Module", genModule },
    .{ "Expression", genExpression },
    .{ "Interactive", genInteractive },
    .{ "FunctionDef", genFunctionDef },
    .{ "AsyncFunctionDef", genAsyncFunctionDef },
    .{ "ClassDef", genClassDef },
    .{ "Return", genReturn },
    .{ "Name", genName },
    .{ "Constant", genConstant },
    .{ "PyCF_ONLY_AST", genPyCfOnlyAst },
    .{ "PyCF_TYPE_COMMENTS", genPyCfTypeComments },
});

fn genParse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genLiteralEval(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genFixMissingLocations(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genIncrementLineno(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genCopyLocation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genDump(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genUnparse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genGetDocstring(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genGetSourceSegment(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genIterFields(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]struct { name: []const u8, value: *anyopaque }{}"), builder_mod.EmitConfig.forExpression());
}

fn genIterChildNodes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genWalk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*anyopaque{}"), builder_mod.EmitConfig.forExpression());
}

fn genAst(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genNodeVisitor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genNodeTransformer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genModule(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .body = &[_]*anyopaque{}, .type_ignores = &[_]*anyopaque{} }"), builder_mod.EmitConfig.forExpression());
}

fn genExpression(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .body = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genInteractive(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .body = &[_]*anyopaque{} }"), builder_mod.EmitConfig.forExpression());
}

fn genFunctionDef(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genAsyncFunctionDef(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genClassDef(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .bases = &[_]*anyopaque{}, .keywords = &[_]*anyopaque{}, .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{} }"), builder_mod.EmitConfig.forExpression());
}

fn genReturn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .value = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genName(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .id = \"\", .ctx = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genConstant(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .value = @as(?*anyopaque, null), .kind = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genPyCfOnlyAst(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x400)"), builder_mod.EmitConfig.forExpression());
}

fn genPyCfTypeComments(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x1000)"), builder_mod.EmitConfig.forExpression());
}
