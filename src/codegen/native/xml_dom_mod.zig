/// Python xml.dom module - DOM support for XML
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "registerDOMImplementation", genRegisterDOMImplementation },
    .{ "getDOMImplementation", genGetDOMImplementation },
    .{ "ELEMENT_NODE", genElementNode },
    .{ "ATTRIBUTE_NODE", genAttributeNode },
    .{ "TEXT_NODE", genTextNode },
    .{ "CDATA_SECTION_NODE", genCdataSectionNode },
    .{ "ENTITY_REFERENCE_NODE", genEntityReferenceNode },
    .{ "ENTITY_NODE", genEntityNode },
    .{ "PROCESSING_INSTRUCTION_NODE", genProcessingInstructionNode },
    .{ "COMMENT_NODE", genCommentNode },
    .{ "DOCUMENT_NODE", genDocumentNode },
    .{ "DOCUMENT_TYPE_NODE", genDocumentTypeNode },
    .{ "DOCUMENT_FRAGMENT_NODE", genDocumentFragmentNode },
    .{ "NOTATION_NODE", genNotationNode },
    .{ "DomstringSizeErr", genDomstringSizeErr },
    .{ "HierarchyRequestErr", genHierarchyRequestErr },
    .{ "IndexSizeErr", genIndexSizeErr },
    .{ "InuseAttributeErr", genInuseAttributeErr },
    .{ "InvalidAccessErr", genInvalidAccessErr },
    .{ "InvalidCharacterErr", genInvalidCharacterErr },
    .{ "InvalidModificationErr", genInvalidModificationErr },
    .{ "InvalidStateErr", genInvalidStateErr },
    .{ "NamespaceErr", genNamespaceErr },
    .{ "NoDataAllowedErr", genNoDataAllowedErr },
    .{ "NoModificationAllowedErr", genNoModificationAllowedErr },
    .{ "NotFoundErr", genNotFoundErr },
    .{ "NotSupportedErr", genNotSupportedErr },
    .{ "SyntaxErr", genSyntaxErr },
    .{ "ValidationErr", genValidationErr },
    .{ "WrongDocumentErr", genWrongDocumentErr },
});

fn genRegisterDOMImplementation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetDOMImplementation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genElementNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genAttributeNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genTextNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genCdataSectionNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genEntityReferenceNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genEntityNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(6), builder_mod.EmitConfig.forExpression());
}

fn genProcessingInstructionNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(7), builder_mod.EmitConfig.forExpression());
}

fn genCommentNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genDocumentNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(9), builder_mod.EmitConfig.forExpression());
}

fn genDocumentTypeNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(10), builder_mod.EmitConfig.forExpression());
}

fn genDocumentFragmentNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(11), builder_mod.EmitConfig.forExpression());
}

fn genNotationNode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(12), builder_mod.EmitConfig.forExpression());
}

fn genDomstringSizeErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.DomstringSizeErr"), builder_mod.EmitConfig.forExpression());
}

fn genHierarchyRequestErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.HierarchyRequestErr"), builder_mod.EmitConfig.forExpression());
}

fn genIndexSizeErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.IndexSizeErr"), builder_mod.EmitConfig.forExpression());
}

fn genInuseAttributeErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.InuseAttributeErr"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidAccessErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.InvalidAccessErr"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidCharacterErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.InvalidCharacterErr"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidModificationErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.InvalidModificationErr"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidStateErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.InvalidStateErr"), builder_mod.EmitConfig.forExpression());
}

fn genNamespaceErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.NamespaceErr"), builder_mod.EmitConfig.forExpression());
}

fn genNoDataAllowedErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.NoDataAllowedErr"), builder_mod.EmitConfig.forExpression());
}

fn genNoModificationAllowedErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.NoModificationAllowedErr"), builder_mod.EmitConfig.forExpression());
}

fn genNotFoundErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.NotFoundErr"), builder_mod.EmitConfig.forExpression());
}

fn genNotSupportedErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.NotSupportedErr"), builder_mod.EmitConfig.forExpression());
}

fn genSyntaxErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SyntaxErr"), builder_mod.EmitConfig.forExpression());
}

fn genValidationErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ValidationErr"), builder_mod.EmitConfig.forExpression());
}

fn genWrongDocumentErr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.WrongDocumentErr"), builder_mod.EmitConfig.forExpression());
}
