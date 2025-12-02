/// Python xml.dom module - DOM support for XML
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "registerDOMImplementation", h.c("{}") }, .{ "getDOMImplementation", h.c("@as(?*anyopaque, null)") },
    .{ "ELEMENT_NODE", h.I32(1) }, .{ "ATTRIBUTE_NODE", h.I32(2) }, .{ "TEXT_NODE", h.I32(3) },
    .{ "CDATA_SECTION_NODE", h.I32(4) }, .{ "ENTITY_REFERENCE_NODE", h.I32(5) }, .{ "ENTITY_NODE", h.I32(6) },
    .{ "PROCESSING_INSTRUCTION_NODE", h.I32(7) }, .{ "COMMENT_NODE", h.I32(8) }, .{ "DOCUMENT_NODE", h.I32(9) },
    .{ "DOCUMENT_TYPE_NODE", h.I32(10) }, .{ "DOCUMENT_FRAGMENT_NODE", h.I32(11) }, .{ "NOTATION_NODE", h.I32(12) },
    .{ "DomstringSizeErr", h.err("DomstringSizeErr") },
    .{ "HierarchyRequestErr", h.err("HierarchyRequestErr") },
    .{ "IndexSizeErr", h.err("IndexSizeErr") },
    .{ "InuseAttributeErr", h.err("InuseAttributeErr") },
    .{ "InvalidAccessErr", h.err("InvalidAccessErr") },
    .{ "InvalidCharacterErr", h.err("InvalidCharacterErr") },
    .{ "InvalidModificationErr", h.err("InvalidModificationErr") },
    .{ "InvalidStateErr", h.err("InvalidStateErr") },
    .{ "NamespaceErr", h.err("NamespaceErr") },
    .{ "NoDataAllowedErr", h.err("NoDataAllowedErr") },
    .{ "NoModificationAllowedErr", h.err("NoModificationAllowedErr") },
    .{ "NotFoundErr", h.err("NotFoundErr") },
    .{ "NotSupportedErr", h.err("NotSupportedErr") },
    .{ "SyntaxErr", h.err("SyntaxErr") },
    .{ "ValidationErr", h.err("ValidationErr") },
    .{ "WrongDocumentErr", h.err("WrongDocumentErr") },
});
