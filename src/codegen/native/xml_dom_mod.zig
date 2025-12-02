/// Python xml.dom module - DOM support for XML
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "registerDOMImplementation", genConst("{}") }, .{ "getDOMImplementation", genConst("@as(?*anyopaque, null)") },
    .{ "ELEMENT_NODE", genI32(1) }, .{ "ATTRIBUTE_NODE", genI32(2) }, .{ "TEXT_NODE", genI32(3) },
    .{ "CDATA_SECTION_NODE", genI32(4) }, .{ "ENTITY_REFERENCE_NODE", genI32(5) }, .{ "ENTITY_NODE", genI32(6) },
    .{ "PROCESSING_INSTRUCTION_NODE", genI32(7) }, .{ "COMMENT_NODE", genI32(8) }, .{ "DOCUMENT_NODE", genI32(9) },
    .{ "DOCUMENT_TYPE_NODE", genI32(10) }, .{ "DOCUMENT_FRAGMENT_NODE", genI32(11) }, .{ "NOTATION_NODE", genI32(12) },
    .{ "DomstringSizeErr", genConst("error.DomstringSizeErr") },
    .{ "HierarchyRequestErr", genConst("error.HierarchyRequestErr") },
    .{ "IndexSizeErr", genConst("error.IndexSizeErr") },
    .{ "InuseAttributeErr", genConst("error.InuseAttributeErr") },
    .{ "InvalidAccessErr", genConst("error.InvalidAccessErr") },
    .{ "InvalidCharacterErr", genConst("error.InvalidCharacterErr") },
    .{ "InvalidModificationErr", genConst("error.InvalidModificationErr") },
    .{ "InvalidStateErr", genConst("error.InvalidStateErr") },
    .{ "NamespaceErr", genConst("error.NamespaceErr") },
    .{ "NoDataAllowedErr", genConst("error.NoDataAllowedErr") },
    .{ "NoModificationAllowedErr", genConst("error.NoModificationAllowedErr") },
    .{ "NotFoundErr", genConst("error.NotFoundErr") },
    .{ "NotSupportedErr", genConst("error.NotSupportedErr") },
    .{ "SyntaxErr", genConst("error.SyntaxErr") },
    .{ "ValidationErr", genConst("error.ValidationErr") },
    .{ "WrongDocumentErr", genConst("error.WrongDocumentErr") },
});
