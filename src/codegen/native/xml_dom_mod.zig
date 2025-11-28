/// Python xml.dom module - DOM support for XML
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate xml.dom.registerDOMImplementation(name, factory)
pub fn genRegisterDOMImplementation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate xml.dom.getDOMImplementation(name=None, features=())
pub fn genGetDOMImplementation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

// ============================================================================
// Node type constants
// ============================================================================

pub fn genELEMENT_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genATTRIBUTE_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genTEXT_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genCDATA_SECTION_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genENTITY_REFERENCE_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genENTITY_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genPROCESSING_INSTRUCTION_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

pub fn genCOMMENT_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genDOCUMENT_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9)");
}

pub fn genDOCUMENT_TYPE_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10)");
}

pub fn genDOCUMENT_FRAGMENT_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 11)");
}

pub fn genNOTATION_NODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 12)");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genDomstringSizeErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.DomstringSizeErr");
}

pub fn genHierarchyRequestErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.HierarchyRequestErr");
}

pub fn genIndexSizeErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IndexSizeErr");
}

pub fn genInuseAttributeErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InuseAttributeErr");
}

pub fn genInvalidAccessErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidAccessErr");
}

pub fn genInvalidCharacterErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidCharacterErr");
}

pub fn genInvalidModificationErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidModificationErr");
}

pub fn genInvalidStateErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidStateErr");
}

pub fn genNamespaceErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NamespaceErr");
}

pub fn genNoDataAllowedErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NoDataAllowedErr");
}

pub fn genNoModificationAllowedErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NoModificationAllowedErr");
}

pub fn genNotFoundErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NotFoundErr");
}

pub fn genNotSupportedErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NotSupportedErr");
}

pub fn genSyntaxErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SyntaxErr");
}

pub fn genValidationErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ValidationErr");
}

pub fn genWrongDocumentErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.WrongDocumentErr");
}
