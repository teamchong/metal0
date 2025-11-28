/// Python sre_constants module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sre_constants.MAGIC constant
pub fn genMagic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 20171005)");
}

/// Generate sre_constants.MAXREPEAT constant
pub fn genMaxrepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4294967295)");
}

/// Generate sre_constants.MAXGROUPS constant
pub fn genMaxgroups(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 100)");
}

/// Generate sre_constants.OPCODES tuple
pub fn genOpcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"FAILURE\", \"SUCCESS\", \"ANY\", \"ANY_ALL\", \"ASSERT\", \"ASSERT_NOT\", \"AT\", \"BRANCH\", \"CALL\", \"CATEGORY\", \"CHARSET\", \"BIGCHARSET\", \"GROUPREF\", \"GROUPREF_EXISTS\", \"IN\", \"INFO\", \"JUMP\", \"LITERAL\", \"MARK\", \"MAX_UNTIL\", \"MIN_UNTIL\", \"NOT_LITERAL\", \"NEGATE\", \"RANGE\", \"REPEAT\", \"REPEAT_ONE\", \"SUBPATTERN\", \"MIN_REPEAT_ONE\", \"ATOMIC_GROUP\", \"POSSESSIVE_REPEAT\", \"POSSESSIVE_REPEAT_ONE\" }");
}

/// Generate sre_constants.ATCODES tuple
pub fn genAtcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"AT_BEGINNING\", \"AT_BEGINNING_LINE\", \"AT_BEGINNING_STRING\", \"AT_BOUNDARY\", \"AT_NON_BOUNDARY\", \"AT_END\", \"AT_END_LINE\", \"AT_END_STRING\" }");
}

/// Generate sre_constants.CHCODES tuple
pub fn genChcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"CATEGORY_DIGIT\", \"CATEGORY_NOT_DIGIT\", \"CATEGORY_SPACE\", \"CATEGORY_NOT_SPACE\", \"CATEGORY_WORD\", \"CATEGORY_NOT_WORD\", \"CATEGORY_LINEBREAK\", \"CATEGORY_NOT_LINEBREAK\" }");
}

/// Generate sre_constants.FAILURE opcode
pub fn genFailure(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0)");
}

/// Generate sre_constants.SUCCESS opcode
pub fn genSuccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1)");
}

/// Generate sre_constants.ANY opcode
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2)");
}

/// Generate sre_constants.ANY_ALL opcode
pub fn genAnyAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 3)");
}

/// Generate sre_constants.ASSERT opcode
pub fn genAssert(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4)");
}

/// Generate sre_constants.ASSERT_NOT opcode
pub fn genAssertNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 5)");
}

/// Generate sre_constants.AT opcode
pub fn genAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 6)");
}

/// Generate sre_constants.BRANCH opcode
pub fn genBranch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 7)");
}

/// Generate sre_constants.CALL opcode
pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 8)");
}

/// Generate sre_constants.CATEGORY opcode
pub fn genCategory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 9)");
}

/// Generate sre_constants.CHARSET opcode
pub fn genCharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 10)");
}

/// Generate sre_constants.BIGCHARSET opcode
pub fn genBigcharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 11)");
}

/// Generate sre_constants.GROUPREF opcode
pub fn genGroupref(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 12)");
}

/// Generate sre_constants.GROUPREF_EXISTS opcode
pub fn genGrouprefExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 13)");
}

/// Generate sre_constants.IN opcode
pub fn genIn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 14)");
}

/// Generate sre_constants.INFO opcode
pub fn genInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 15)");
}

/// Generate sre_constants.JUMP opcode
pub fn genJump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16)");
}

/// Generate sre_constants.LITERAL opcode
pub fn genLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 17)");
}

/// Generate sre_constants.MARK opcode
pub fn genMark(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 18)");
}

/// Generate sre_constants.MAX_UNTIL opcode
pub fn genMaxUntil(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 19)");
}

/// Generate sre_constants.MIN_UNTIL opcode
pub fn genMinUntil(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 20)");
}

/// Generate sre_constants.NOT_LITERAL opcode
pub fn genNotLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 21)");
}

/// Generate sre_constants.NEGATE opcode
pub fn genNegate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 22)");
}

/// Generate sre_constants.RANGE opcode
pub fn genRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 23)");
}

/// Generate sre_constants.REPEAT opcode
pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 24)");
}

/// Generate sre_constants.REPEAT_ONE opcode
pub fn genRepeatOne(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 25)");
}

/// Generate sre_constants.SUBPATTERN opcode
pub fn genSubpattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 26)");
}

/// Generate sre_constants.MIN_REPEAT_ONE opcode
pub fn genMinRepeatOne(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 27)");
}

/// Generate sre_constants.SRE_FLAG_TEMPLATE constant
pub fn genSreFlagTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1)");
}

/// Generate sre_constants.SRE_FLAG_IGNORECASE constant
pub fn genSreFlagIgnorecase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2)");
}

/// Generate sre_constants.SRE_FLAG_LOCALE constant
pub fn genSreFlagLocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4)");
}

/// Generate sre_constants.SRE_FLAG_MULTILINE constant
pub fn genSreFlagMultiline(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 8)");
}

/// Generate sre_constants.SRE_FLAG_DOTALL constant
pub fn genSreFlagDotall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16)");
}

/// Generate sre_constants.SRE_FLAG_UNICODE constant
pub fn genSreFlagUnicode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 32)");
}

/// Generate sre_constants.SRE_FLAG_VERBOSE constant
pub fn genSreFlagVerbose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 64)");
}

/// Generate sre_constants.SRE_FLAG_DEBUG constant
pub fn genSreFlagDebug(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 128)");
}

/// Generate sre_constants.SRE_FLAG_ASCII constant
pub fn genSreFlagAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 256)");
}

/// Generate sre_constants.SRE_INFO_PREFIX constant
pub fn genSreInfoPrefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1)");
}

/// Generate sre_constants.SRE_INFO_LITERAL constant
pub fn genSreInfoLiteral(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2)");
}

/// Generate sre_constants.SRE_INFO_CHARSET constant
pub fn genSreInfoCharset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4)");
}

/// Generate sre_constants.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SreError");
}
