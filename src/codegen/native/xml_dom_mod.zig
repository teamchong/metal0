/// Python xml.dom module - DOM support for XML
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "registerDOMImplementation", genUnit }, .{ "getDOMImplementation", genNullPtr },
    .{ "ELEMENT_NODE", genI32_1 }, .{ "ATTRIBUTE_NODE", genI32_2 }, .{ "TEXT_NODE", genI32_3 },
    .{ "CDATA_SECTION_NODE", genI32_4 }, .{ "ENTITY_REFERENCE_NODE", genI32_5 }, .{ "ENTITY_NODE", genI32_6 },
    .{ "PROCESSING_INSTRUCTION_NODE", genI32_7 }, .{ "COMMENT_NODE", genI32_8 }, .{ "DOCUMENT_NODE", genI32_9 },
    .{ "DOCUMENT_TYPE_NODE", genI32_10 }, .{ "DOCUMENT_FRAGMENT_NODE", genI32_11 }, .{ "NOTATION_NODE", genI32_12 },
    .{ "DomstringSizeErr", genErrDomstringSize }, .{ "HierarchyRequestErr", genErrHierarchyRequest },
    .{ "IndexSizeErr", genErrIndexSize }, .{ "InuseAttributeErr", genErrInuseAttribute },
    .{ "InvalidAccessErr", genErrInvalidAccess }, .{ "InvalidCharacterErr", genErrInvalidCharacter },
    .{ "InvalidModificationErr", genErrInvalidModification }, .{ "InvalidStateErr", genErrInvalidState },
    .{ "NamespaceErr", genErrNamespace }, .{ "NoDataAllowedErr", genErrNoDataAllowed },
    .{ "NoModificationAllowedErr", genErrNoModificationAllowed }, .{ "NotFoundErr", genErrNotFound },
    .{ "NotSupportedErr", genErrNotSupported }, .{ "SyntaxErr", genErrSyntax },
    .{ "ValidationErr", genErrValidation }, .{ "WrongDocumentErr", genErrWrongDocument },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 7)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 9)"); }
fn genI32_10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genI32_11(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 11)"); }
fn genI32_12(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 12)"); }
fn genErrDomstringSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.DomstringSizeErr"); }
fn genErrHierarchyRequest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.HierarchyRequestErr"); }
fn genErrIndexSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IndexSizeErr"); }
fn genErrInuseAttribute(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InuseAttributeErr"); }
fn genErrInvalidAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidAccessErr"); }
fn genErrInvalidCharacter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidCharacterErr"); }
fn genErrInvalidModification(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidModificationErr"); }
fn genErrInvalidState(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidStateErr"); }
fn genErrNamespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NamespaceErr"); }
fn genErrNoDataAllowed(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NoDataAllowedErr"); }
fn genErrNoModificationAllowed(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NoModificationAllowedErr"); }
fn genErrNotFound(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NotFoundErr"); }
fn genErrNotSupported(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NotSupportedErr"); }
fn genErrSyntax(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SyntaxErr"); }
fn genErrValidation(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ValidationErr"); }
fn genErrWrongDocument(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.WrongDocumentErr"); }
