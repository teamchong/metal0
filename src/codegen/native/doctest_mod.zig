/// Python doctest module - Test interactive Python examples
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "testmod", genTestmod },
    .{ "testfile", genTestfile },
    .{ "run_docstring_examples", genRunDocstringExamples },
    .{ "DocTestSuite", genDocTestSuite },
    .{ "DocFileSuite", genDocFileSuite },
    .{ "DocTestParser", genDocTestParser },
    .{ "DocTestRunner", genDocTestRunner },
    .{ "DocTestFinder", genDocTestFinder },
    .{ "DocTest", genDocTest },
    .{ "Example", genExample },
    .{ "OutputChecker", genOutputChecker },
    .{ "DebugRunner", genDebugRunner },
    .{ "OPTIONFLAGS", genOptionflags },
    .{ "ELLIPSIS", genEllipsis },
    .{ "NORMALIZE_WHITESPACE", genNormalizeWhitespace },
    .{ "DONT_ACCEPT_TRUE_FOR_1", genDontAcceptTrueFor1 },
    .{ "DONT_ACCEPT_BLANKLINE", genDontAcceptBlankline },
    .{ "SKIP", genSkip },
    .{ "IGNORE_EXCEPTION_DETAIL", genIgnoreExceptionDetail },
    .{ "REPORT_UDIFF", genReportUdiff },
    .{ "REPORT_CDIFF", genReportCdiff },
    .{ "REPORT_NDIFF", genReportNdiff },
    .{ "REPORT_ONLY_FIRST_FAILURE", genReportOnlyFirstFailure },
    .{ "FAIL_FAST", genFailFast },
});

fn genTestmod(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genTestfile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genRunDocstringExamples(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDocTestSuite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genDocFileSuite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genDocTestParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genDocTestRunner(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .verbose = false }"), builder_mod.EmitConfig.forExpression());
}

fn genDocTestFinder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .verbose = false, .recurse = true }"), builder_mod.EmitConfig.forExpression());
}

fn genDocTest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .examples = &[_]*anyopaque{}, .globs = @as(?*anyopaque, null), .name = \"\", .filename = @as(?[]const u8, null), .lineno = @as(?i32, null), .docstring = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genExample(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .source = \"\", .want = \"\", .exc_msg = @as(?[]const u8, null), .lineno = @as(i32, 0), .indent = @as(i32, 0), .options = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genOutputChecker(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genDebugRunner(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genOptionflags(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"OPTIONFLAGS\", \"DONT_ACCEPT_TRUE_FOR_1\", \"DONT_ACCEPT_BLANKLINE\", \"NORMALIZE_WHITESPACE\", \"ELLIPSIS\", \"SKIP\", \"IGNORE_EXCEPTION_DETAIL\", \"COMPARISON_FLAGS\", \"REPORT_UDIFF\", \"REPORT_CDIFF\", \"REPORT_NDIFF\", \"REPORT_ONLY_FIRST_FAILURE\", \"FAIL_FAST\", \"REPORTING_FLAGS\" }"), builder_mod.EmitConfig.forExpression());
}

fn genEllipsis(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genNormalizeWhitespace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genDontAcceptTrueFor1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genDontAcceptBlankline(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genSkip(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genIgnoreExceptionDetail(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32), builder_mod.EmitConfig.forExpression());
}

fn genReportUdiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(256), builder_mod.EmitConfig.forExpression());
}

fn genReportCdiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(512), builder_mod.EmitConfig.forExpression());
}

fn genReportNdiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1024), builder_mod.EmitConfig.forExpression());
}

fn genReportOnlyFirstFailure(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2048), builder_mod.EmitConfig.forExpression());
}

fn genFailFast(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4096), builder_mod.EmitConfig.forExpression());
}
