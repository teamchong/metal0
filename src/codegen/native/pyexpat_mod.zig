/// Python pyexpat module - Fast XML parsing using Expat
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ParserCreate", genParserCreate },
    .{ "Parse", genParse },
    .{ "ParseFile", genParseFile },
    .{ "SetBase", genSetBase },
    .{ "GetBase", genGetBase },
    .{ "GetInputContext", genGetInputContext },
    .{ "ExternalEntityParserCreate", genExternalEntityParserCreate },
    .{ "SetParamEntityParsing", genSetParamEntityParsing },
    .{ "UseForeignDTD", genUseForeignDTD },
    .{ "ErrorString", genErrorString },
    .{ "XMLParserType", genXMLParserType },
    .{ "ExpatError", genExpatError },
    .{ "error", genError },
    .{ "XML_PARAM_ENTITY_PARSING_NEVER", genParamNever },
    .{ "XML_PARAM_ENTITY_PARSING_UNLESS_STANDALONE", genParamUnlessStandalone },
    .{ "XML_PARAM_ENTITY_PARSING_ALWAYS", genParamAlways },
    .{ "version_info", genVersionInfo },
    .{ "EXPAT_VERSION", genExpatVersion },
    .{ "native_encoding", genNativeEncoding },
    .{ "features", genFeatures },
    .{ "model", genModel },
    .{ "errors", genErrors },
});

fn genParserCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer_text = false, .buffer_size = 8192, .buffer_used = 0, .ordered_attributes = false, .specified_attributes = false, .returns_unicode = true }"), builder_mod.EmitConfig.forExpression());
}

fn genParse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genParseFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genSetBase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetBase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genGetInputContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genExternalEntityParserCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetParamEntityParsing(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genUseForeignDTD(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genErrorString(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("unknown error"), builder_mod.EmitConfig.forExpression());
}

fn genXMLParserType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{})"), builder_mod.EmitConfig.forExpression());
}

fn genExpatError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ExpatError"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ExpatError"), builder_mod.EmitConfig.forExpression());
}

fn genParamNever(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genParamUnlessStandalone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genParamAlways(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genVersionInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 2), @as(i32, 5), @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genExpatVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("expat_2.5.0"), builder_mod.EmitConfig.forExpression());
}

fn genNativeEncoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("UTF-8"), builder_mod.EmitConfig.forExpression());
}

fn genFeatures(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]struct { []const u8, i32 }{ .{ \"sizeof(XML_Char)\", 1 }, .{ \"sizeof(XML_LChar)\", 1 } }"), builder_mod.EmitConfig.forExpression());
}

fn genModel(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .XML_CTYPE_EMPTY = 1, .XML_CTYPE_ANY = 2, .XML_CTYPE_MIXED = 3, .XML_CTYPE_NAME = 4, .XML_CTYPE_CHOICE = 5, .XML_CTYPE_SEQ = 6, .XML_CQUANT_NONE = 0, .XML_CQUANT_OPT = 1, .XML_CQUANT_REP = 2, .XML_CQUANT_PLUS = 3 }"), builder_mod.EmitConfig.forExpression());
}

fn genErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .XML_ERROR_NO_MEMORY = \"out of memory\", .XML_ERROR_SYNTAX = \"syntax error\", .XML_ERROR_NO_ELEMENTS = \"no element found\", .XML_ERROR_INVALID_TOKEN = \"not well-formed (invalid token)\" }"), builder_mod.EmitConfig.forExpression());
}
