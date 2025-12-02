/// Python sre_constants module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
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
    .{ "SRE_FLAG_TEMPLATE", genSreFlagTemplate },
    .{ "SRE_FLAG_IGNORECASE", genSreFlagIgnorecase },
    .{ "SRE_FLAG_LOCALE", genSreFlagLocale },
    .{ "SRE_FLAG_MULTILINE", genSreFlagMultiline },
    .{ "SRE_FLAG_DOTALL", genSreFlagDotall },
    .{ "SRE_FLAG_UNICODE", genSreFlagUnicode },
    .{ "SRE_FLAG_VERBOSE", genSreFlagVerbose },
    .{ "SRE_FLAG_DEBUG", genSreFlagDebug },
    .{ "SRE_FLAG_ASCII", genSreFlagAscii },
    .{ "SRE_INFO_PREFIX", genSreInfoPrefix },
    .{ "SRE_INFO_LITERAL", genSreInfoLiteral },
    .{ "SRE_INFO_CHARSET", genSreInfoCharset },
    .{ "error", genError },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// Helper for constants
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void {
    _ = args;
    try self.emit(value);
}

// Magic/limits
pub fn genMagic(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 20171005)"); }
pub fn genMaxrepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 4294967295)"); }
pub fn genMaxgroups(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 100)"); }

// Code tuples
pub fn genOpcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"FAILURE\", \"SUCCESS\", \"ANY\", \"ANY_ALL\", \"ASSERT\", \"ASSERT_NOT\", \"AT\", \"BRANCH\", \"CALL\", \"CATEGORY\", \"CHARSET\", \"BIGCHARSET\", \"GROUPREF\", \"GROUPREF_EXISTS\", \"IN\", \"INFO\", \"JUMP\", \"LITERAL\", \"MARK\", \"MAX_UNTIL\", \"MIN_UNTIL\", \"NOT_LITERAL\", \"NEGATE\", \"RANGE\", \"REPEAT\", \"REPEAT_ONE\", \"SUBPATTERN\", \"MIN_REPEAT_ONE\", \"ATOMIC_GROUP\", \"POSSESSIVE_REPEAT\", \"POSSESSIVE_REPEAT_ONE\" }"); }
pub fn genAtcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"AT_BEGINNING\", \"AT_BEGINNING_LINE\", \"AT_BEGINNING_STRING\", \"AT_BOUNDARY\", \"AT_NON_BOUNDARY\", \"AT_END\", \"AT_END_LINE\", \"AT_END_STRING\" }"); }
pub fn genChcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"CATEGORY_DIGIT\", \"CATEGORY_NOT_DIGIT\", \"CATEGORY_SPACE\", \"CATEGORY_NOT_SPACE\", \"CATEGORY_WORD\", \"CATEGORY_NOT_WORD\", \"CATEGORY_LINEBREAK\", \"CATEGORY_NOT_LINEBREAK\" }"); }

// Opcodes
pub fn genFailure(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0)"); }
pub fn genSuccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 1)"); }
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 2)"); }
pub fn genAnyAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 3)"); }
pub fn genAssert(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 4)"); }
pub fn genAssertNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 5)"); }
pub fn genAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 6)"); }
pub fn genBranch(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 7)"); }
pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 8)"); }
pub fn genCategory(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 9)"); }
pub fn genCharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 10)"); }
pub fn genBigcharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 11)"); }
pub fn genGroupref(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 12)"); }
pub fn genGrouprefExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 13)"); }
pub fn genIn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 14)"); }
pub fn genInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 15)"); }
pub fn genJump(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 16)"); }
pub fn genLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 17)"); }
pub fn genMark(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 18)"); }
pub fn genMaxUntil(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 19)"); }
pub fn genMinUntil(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 20)"); }
pub fn genNotLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 21)"); }
pub fn genNegate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 22)"); }
pub fn genRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 23)"); }
pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 24)"); }
pub fn genRepeatOne(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 25)"); }
pub fn genSubpattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 26)"); }
pub fn genMinRepeatOne(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 27)"); }

// SRE flags
pub fn genSreFlagTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 1)"); }
pub fn genSreFlagIgnorecase(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 2)"); }
pub fn genSreFlagLocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 4)"); }
pub fn genSreFlagMultiline(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 8)"); }
pub fn genSreFlagDotall(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 16)"); }
pub fn genSreFlagUnicode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 32)"); }
pub fn genSreFlagVerbose(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 64)"); }
pub fn genSreFlagDebug(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 128)"); }
pub fn genSreFlagAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 256)"); }

// SRE info
pub fn genSreInfoPrefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 1)"); }
pub fn genSreInfoLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 2)"); }
pub fn genSreInfoCharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 4)"); }

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SreError"); }
