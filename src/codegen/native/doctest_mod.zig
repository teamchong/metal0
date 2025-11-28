/// Python doctest module - Test interactive Python examples
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate doctest.testmod(m=None, verbose=None, report=True, ...)
pub fn genTestmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }");
}

/// Generate doctest.testfile(filename, module_relative=True, ...)
pub fn genTestfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }");
}

/// Generate doctest.run_docstring_examples(f, globs, verbose=False, ...)
pub fn genRun_docstring_examples(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate doctest.DocTestSuite class
pub fn genDocTestSuite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate doctest.DocFileSuite class
pub fn genDocFileSuite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate doctest.DocTestParser class
pub fn genDocTestParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate doctest.DocTestRunner class
pub fn genDocTestRunner(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .verbose = false }");
}

/// Generate doctest.DocTestFinder class
pub fn genDocTestFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .verbose = false, .recurse = true }");
}

/// Generate doctest.DocTest class
pub fn genDocTest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .examples = &[_]*anyopaque{}, .globs = @as(?*anyopaque, null), .name = \"\", .filename = @as(?[]const u8, null), .lineno = @as(?i32, null), .docstring = @as(?[]const u8, null) }");
}

/// Generate doctest.Example class
pub fn genExample(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .source = \"\", .want = \"\", .exc_msg = @as(?[]const u8, null), .lineno = @as(i32, 0), .indent = @as(i32, 0), .options = @as(?*anyopaque, null) }");
}

/// Generate doctest.OutputChecker class
pub fn genOutputChecker(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate doctest.DebugRunner class
pub fn genDebugRunner(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// Option flag constants
// ============================================================================

pub fn genOPTIONFLAGS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"OPTIONFLAGS\", \"DONT_ACCEPT_TRUE_FOR_1\", \"DONT_ACCEPT_BLANKLINE\", \"NORMALIZE_WHITESPACE\", \"ELLIPSIS\", \"SKIP\", \"IGNORE_EXCEPTION_DETAIL\", \"COMPARISON_FLAGS\", \"REPORT_UDIFF\", \"REPORT_CDIFF\", \"REPORT_NDIFF\", \"REPORT_ONLY_FIRST_FAILURE\", \"FAIL_FAST\", \"REPORTING_FLAGS\" }");
}

pub fn genELLIPSIS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genNORMALIZE_WHITESPACE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genDONT_ACCEPT_TRUE_FOR_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genDONT_ACCEPT_BLANKLINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genSKIP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

pub fn genIGNORE_EXCEPTION_DETAIL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 32)");
}

pub fn genREPORT_UDIFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 256)");
}

pub fn genREPORT_CDIFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 512)");
}

pub fn genREPORT_NDIFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1024)");
}

pub fn genREPORT_ONLY_FIRST_FAILURE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2048)");
}

pub fn genFAIL_FAST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4096)");
}
