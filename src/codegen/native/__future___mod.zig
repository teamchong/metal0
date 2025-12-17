/// Python __future__ module - Future statement definitions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "annotations", genAnnotations },
    .{ "division", genDivision },
    .{ "absolute_import", genAbsoluteImport },
    .{ "with_statement", genWithStatement },
    .{ "print_function", genPrintFunction },
    .{ "unicode_literals", genUnicodeLiterals },
    .{ "generator_stop", genGeneratorStop },
    .{ "nested_scopes", genNestedScopes },
    .{ "generators", genGenerators },
});

fn genAnnotations(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x100000 }"), builder_mod.EmitConfig.forExpression());
}

fn genDivision(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x2000 }"), builder_mod.EmitConfig.forExpression());
}

fn genAbsoluteImport(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x4000 }"), builder_mod.EmitConfig.forExpression());
}

fn genWithStatement(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x8000 }"), builder_mod.EmitConfig.forExpression());
}

fn genPrintFunction(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x10000 }"), builder_mod.EmitConfig.forExpression());
}

fn genUnicodeLiterals(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x20000 }"), builder_mod.EmitConfig.forExpression());
}

fn genGeneratorStop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x80000 }"), builder_mod.EmitConfig.forExpression());
}

fn genNestedScopes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x10 }"), builder_mod.EmitConfig.forExpression());
}

fn genGenerators(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler_flag = 0x1000 }"), builder_mod.EmitConfig.forExpression());
}
