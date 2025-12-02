/// Python doctest module - Test interactive Python examples
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genTestResult(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "testmod", genTestResult }, .{ "testfile", genTestResult }, .{ "run_docstring_examples", genUnit },
    .{ "DocTestSuite", genNullPtr }, .{ "DocFileSuite", genNullPtr },
    .{ "DocTestParser", genEmpty }, .{ "DocTestRunner", genDocTestRunner }, .{ "DocTestFinder", genDocTestFinder },
    .{ "DocTest", genDocTest }, .{ "Example", genExample }, .{ "OutputChecker", genEmpty }, .{ "DebugRunner", genEmpty },
    .{ "OPTIONFLAGS", genOPTIONFLAGS },
    .{ "ELLIPSIS", genELLIPSIS }, .{ "NORMALIZE_WHITESPACE", genNORMALIZE_WHITESPACE },
    .{ "DONT_ACCEPT_TRUE_FOR_1", genDONT_ACCEPT_TRUE_FOR_1 }, .{ "DONT_ACCEPT_BLANKLINE", genDONT_ACCEPT_BLANKLINE },
    .{ "SKIP", genSKIP }, .{ "IGNORE_EXCEPTION_DETAIL", genIGNORE_EXCEPTION_DETAIL },
    .{ "REPORT_UDIFF", genREPORT_UDIFF }, .{ "REPORT_CDIFF", genREPORT_CDIFF }, .{ "REPORT_NDIFF", genREPORT_NDIFF },
    .{ "REPORT_ONLY_FIRST_FAILURE", genREPORT_ONLY_FIRST_FAILURE }, .{ "FAIL_FAST", genFAIL_FAST },
});

fn genDocTestRunner(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .verbose = false }"); }
fn genDocTestFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .verbose = false, .recurse = true }"); }
fn genDocTest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .examples = &[_]*anyopaque{}, .globs = @as(?*anyopaque, null), .name = \"\", .filename = @as(?[]const u8, null), .lineno = @as(?i32, null), .docstring = @as(?[]const u8, null) }"); }
fn genExample(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .source = \"\", .want = \"\", .exc_msg = @as(?[]const u8, null), .lineno = @as(i32, 0), .indent = @as(i32, 0), .options = @as(?*anyopaque, null) }"); }
fn genOPTIONFLAGS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"OPTIONFLAGS\", \"DONT_ACCEPT_TRUE_FOR_1\", \"DONT_ACCEPT_BLANKLINE\", \"NORMALIZE_WHITESPACE\", \"ELLIPSIS\", \"SKIP\", \"IGNORE_EXCEPTION_DETAIL\", \"COMPARISON_FLAGS\", \"REPORT_UDIFF\", \"REPORT_CDIFF\", \"REPORT_NDIFF\", \"REPORT_ONLY_FIRST_FAILURE\", \"FAIL_FAST\", \"REPORTING_FLAGS\" }"); }
fn genELLIPSIS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genNORMALIZE_WHITESPACE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genDONT_ACCEPT_TRUE_FOR_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genDONT_ACCEPT_BLANKLINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genSKIP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genIGNORE_EXCEPTION_DETAIL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 32)"); }
fn genREPORT_UDIFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 256)"); }
fn genREPORT_CDIFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 512)"); }
fn genREPORT_NDIFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1024)"); }
fn genREPORT_ONLY_FIRST_FAILURE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2048)"); }
fn genFAIL_FAST(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4096)"); }
