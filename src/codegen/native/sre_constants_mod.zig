/// Python sre_constants module - Internal support module for sre
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "MAGIC", genMagic },
    .{ "MAXREPEAT", genMaxrepeat },
    .{ "MAXGROUPS", genMaxgroups },
    .{ "OPCODES", genOpcodes },
    .{ "ATCODES", genAtcodes },
    .{ "CHCODES", genChcodes },
    .{ "FAILURE", genFailure },
    .{ "SUCCESS", genSuccess },
    .{ "ANY", genAny },
    .{ "ANY_ALL", genAnyAll },
    .{ "ASSERT", genAssert },
    .{ "ASSERT_NOT", genAssertNot },
    .{ "AT", genAt },
    .{ "BRANCH", genBranch },
    .{ "CALL", genCall },
    .{ "CATEGORY", genCategory },
    .{ "CHARSET", genCharset },
    .{ "BIGCHARSET", genBigcharset },
    .{ "GROUPREF", genGroupref },
    .{ "GROUPREF_EXISTS", genGrouprefExists },
    .{ "IN", genIn },
    .{ "INFO", genInfo },
    .{ "JUMP", genJump },
    .{ "LITERAL", genLiteral },
    .{ "MARK", genMark },
    .{ "MAX_UNTIL", genMaxUntil },
    .{ "MIN_UNTIL", genMinUntil },
    .{ "NOT_LITERAL", genNotLiteral },
    .{ "NEGATE", genNegate },
    .{ "RANGE", genRange },
    .{ "REPEAT", genRepeat },
    .{ "REPEAT_ONE", genRepeatOne },
    .{ "SUBPATTERN", genSubpattern },
    .{ "MIN_REPEAT_ONE", genMinRepeatOne },
    .{ "SRE_FLAG_TEMPLATE", genFlagTemplate },
    .{ "SRE_FLAG_IGNORECASE", genFlagIgnorecase },
    .{ "SRE_FLAG_LOCALE", genFlagLocale },
    .{ "SRE_FLAG_MULTILINE", genFlagMultiline },
    .{ "SRE_FLAG_DOTALL", genFlagDotall },
    .{ "SRE_FLAG_UNICODE", genFlagUnicode },
    .{ "SRE_FLAG_VERBOSE", genFlagVerbose },
    .{ "SRE_FLAG_DEBUG", genFlagDebug },
    .{ "SRE_FLAG_ASCII", genFlagAscii },
    .{ "SRE_INFO_PREFIX", genInfoPrefix },
    .{ "SRE_INFO_LITERAL", genInfoLiteral },
    .{ "SRE_INFO_CHARSET", genInfoCharset },
    .{ "error", genError },
});

fn genMagic(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 20171005)"), builder_mod.EmitConfig.forExpression());
}

fn genMaxrepeat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 4294967295)"), builder_mod.EmitConfig.forExpression());
}

fn genMaxgroups(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 100)"), builder_mod.EmitConfig.forExpression());
}

fn genOpcodes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"FAILURE\", \"SUCCESS\", \"ANY\", \"ANY_ALL\", \"ASSERT\", \"ASSERT_NOT\", \"AT\", \"BRANCH\", \"CALL\", \"CATEGORY\", \"CHARSET\", \"BIGCHARSET\", \"GROUPREF\", \"GROUPREF_EXISTS\", \"IN\", \"INFO\", \"JUMP\", \"LITERAL\", \"MARK\", \"MAX_UNTIL\", \"MIN_UNTIL\", \"NOT_LITERAL\", \"NEGATE\", \"RANGE\", \"REPEAT\", \"REPEAT_ONE\", \"SUBPATTERN\", \"MIN_REPEAT_ONE\", \"ATOMIC_GROUP\", \"POSSESSIVE_REPEAT\", \"POSSESSIVE_REPEAT_ONE\" }"), builder_mod.EmitConfig.forExpression());
}

fn genAtcodes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"AT_BEGINNING\", \"AT_BEGINNING_LINE\", \"AT_BEGINNING_STRING\", \"AT_BOUNDARY\", \"AT_NON_BOUNDARY\", \"AT_END\", \"AT_END_LINE\", \"AT_END_STRING\" }"), builder_mod.EmitConfig.forExpression());
}

fn genChcodes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"CATEGORY_DIGIT\", \"CATEGORY_NOT_DIGIT\", \"CATEGORY_SPACE\", \"CATEGORY_NOT_SPACE\", \"CATEGORY_WORD\", \"CATEGORY_NOT_WORD\", \"CATEGORY_LINEBREAK\", \"CATEGORY_NOT_LINEBREAK\" }"), builder_mod.EmitConfig.forExpression());
}

fn genFailure(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genSuccess(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genAny(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genAnyAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genAssert(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genAssertNot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 5)"), builder_mod.EmitConfig.forExpression());
}

fn genAt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn genBranch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 7)"), builder_mod.EmitConfig.forExpression());
}

fn genCall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 8)"), builder_mod.EmitConfig.forExpression());
}

fn genCategory(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 9)"), builder_mod.EmitConfig.forExpression());
}

fn genCharset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 10)"), builder_mod.EmitConfig.forExpression());
}

fn genBigcharset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 11)"), builder_mod.EmitConfig.forExpression());
}

fn genGroupref(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 12)"), builder_mod.EmitConfig.forExpression());
}

fn genGrouprefExists(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 13)"), builder_mod.EmitConfig.forExpression());
}

fn genIn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 14)"), builder_mod.EmitConfig.forExpression());
}

fn genInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 15)"), builder_mod.EmitConfig.forExpression());
}

fn genJump(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 16)"), builder_mod.EmitConfig.forExpression());
}

fn genLiteral(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 17)"), builder_mod.EmitConfig.forExpression());
}

fn genMark(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 18)"), builder_mod.EmitConfig.forExpression());
}

fn genMaxUntil(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 19)"), builder_mod.EmitConfig.forExpression());
}

fn genMinUntil(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 20)"), builder_mod.EmitConfig.forExpression());
}

fn genNotLiteral(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 21)"), builder_mod.EmitConfig.forExpression());
}

fn genNegate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 22)"), builder_mod.EmitConfig.forExpression());
}

fn genRange(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 23)"), builder_mod.EmitConfig.forExpression());
}

fn genRepeat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 24)"), builder_mod.EmitConfig.forExpression());
}

fn genRepeatOne(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 25)"), builder_mod.EmitConfig.forExpression());
}

fn genSubpattern(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 26)"), builder_mod.EmitConfig.forExpression());
}

fn genMinRepeatOne(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 27)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagTemplate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagIgnorecase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagLocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagMultiline(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 8)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagDotall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 16)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagUnicode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 32)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagVerbose(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 64)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagDebug(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 128)"), builder_mod.EmitConfig.forExpression());
}

fn genFlagAscii(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 256)"), builder_mod.EmitConfig.forExpression());
}

fn genInfoPrefix(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genInfoLiteral(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genInfoCharset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SreError"), builder_mod.EmitConfig.forExpression());
}
