/// Python symtable module - Symbol table access
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "symtable", genSymtable },
    .{ "SymbolTable", genSymbolTable },
    .{ "Symbol", genSymbol },
    .{ "Function", genFunction },
    .{ "Class", genClass },
});

fn genSymtable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"<module>\", .type = \"module\", .lineno = 1, .is_optimized = false, .is_nested = false, .has_children = false, .has_exec = false, .has_import_star = false, .has_varargs = false, .has_varkeywords = false }"), builder_mod.EmitConfig.forExpression());
}

fn genSymbolTable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .type = \"module\", .id = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSymbol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .is_referenced = false, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = false, .is_annotated = false, .is_free = false, .is_assigned = false, .is_namespace = false }"), builder_mod.EmitConfig.forExpression());
}

fn genFunction(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .type = \"function\", .id = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genClass(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .type = \"class\", .id = 0 }"), builder_mod.EmitConfig.forExpression());
}
