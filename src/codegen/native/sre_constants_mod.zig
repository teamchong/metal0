/// Python sre_constants module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genU32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(u32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "MAGIC", genMagic }, .{ "MAXREPEAT", genMaxrepeat }, .{ "MAXGROUPS", genU32(100) },
    .{ "OPCODES", genOpcodes }, .{ "ATCODES", genAtcodes }, .{ "CHCODES", genChcodes },
    .{ "FAILURE", genU32(0) }, .{ "SUCCESS", genU32(1) }, .{ "ANY", genU32(2) }, .{ "ANY_ALL", genU32(3) },
    .{ "ASSERT", genU32(4) }, .{ "ASSERT_NOT", genU32(5) }, .{ "AT", genU32(6) }, .{ "BRANCH", genU32(7) },
    .{ "CALL", genU32(8) }, .{ "CATEGORY", genU32(9) }, .{ "CHARSET", genU32(10) }, .{ "BIGCHARSET", genU32(11) },
    .{ "GROUPREF", genU32(12) }, .{ "GROUPREF_EXISTS", genU32(13) }, .{ "IN", genU32(14) }, .{ "INFO", genU32(15) },
    .{ "JUMP", genU32(16) }, .{ "LITERAL", genU32(17) }, .{ "MARK", genU32(18) }, .{ "MAX_UNTIL", genU32(19) },
    .{ "MIN_UNTIL", genU32(20) }, .{ "NOT_LITERAL", genU32(21) }, .{ "NEGATE", genU32(22) }, .{ "RANGE", genU32(23) },
    .{ "REPEAT", genU32(24) }, .{ "REPEAT_ONE", genU32(25) }, .{ "SUBPATTERN", genU32(26) }, .{ "MIN_REPEAT_ONE", genU32(27) },
    .{ "SRE_FLAG_TEMPLATE", genU32(1) }, .{ "SRE_FLAG_IGNORECASE", genU32(2) }, .{ "SRE_FLAG_LOCALE", genU32(4) },
    .{ "SRE_FLAG_MULTILINE", genU32(8) }, .{ "SRE_FLAG_DOTALL", genU32(16) }, .{ "SRE_FLAG_UNICODE", genU32(32) },
    .{ "SRE_FLAG_VERBOSE", genU32(64) }, .{ "SRE_FLAG_DEBUG", genU32(128) }, .{ "SRE_FLAG_ASCII", genU32(256) },
    .{ "SRE_INFO_PREFIX", genU32(1) }, .{ "SRE_INFO_LITERAL", genU32(2) }, .{ "SRE_INFO_CHARSET", genU32(4) },
    .{ "error", genErr },
});

fn genMagic(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 20171005)"); }
fn genMaxrepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 4294967295)"); }
fn genOpcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"FAILURE\", \"SUCCESS\", \"ANY\", \"ANY_ALL\", \"ASSERT\", \"ASSERT_NOT\", \"AT\", \"BRANCH\", \"CALL\", \"CATEGORY\", \"CHARSET\", \"BIGCHARSET\", \"GROUPREF\", \"GROUPREF_EXISTS\", \"IN\", \"INFO\", \"JUMP\", \"LITERAL\", \"MARK\", \"MAX_UNTIL\", \"MIN_UNTIL\", \"NOT_LITERAL\", \"NEGATE\", \"RANGE\", \"REPEAT\", \"REPEAT_ONE\", \"SUBPATTERN\", \"MIN_REPEAT_ONE\", \"ATOMIC_GROUP\", \"POSSESSIVE_REPEAT\", \"POSSESSIVE_REPEAT_ONE\" }"); }
fn genAtcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"AT_BEGINNING\", \"AT_BEGINNING_LINE\", \"AT_BEGINNING_STRING\", \"AT_BOUNDARY\", \"AT_NON_BOUNDARY\", \"AT_END\", \"AT_END_LINE\", \"AT_END_STRING\" }"); }
fn genChcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"CATEGORY_DIGIT\", \"CATEGORY_NOT_DIGIT\", \"CATEGORY_SPACE\", \"CATEGORY_NOT_SPACE\", \"CATEGORY_WORD\", \"CATEGORY_NOT_WORD\", \"CATEGORY_LINEBREAK\", \"CATEGORY_NOT_LINEBREAK\" }"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SreError"); }
