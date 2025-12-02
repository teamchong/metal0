/// Python doctest module - Test interactive Python examples
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "testmod", genConst(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }") },
    .{ "testfile", genConst(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }") },
    .{ "run_docstring_examples", genConst("{}") },
    .{ "DocTestSuite", genConst("@as(?*anyopaque, null)") }, .{ "DocFileSuite", genConst("@as(?*anyopaque, null)") },
    .{ "DocTestParser", genConst(".{}") },
    .{ "DocTestRunner", genConst(".{ .verbose = false }") },
    .{ "DocTestFinder", genConst(".{ .verbose = false, .recurse = true }") },
    .{ "DocTest", genConst(".{ .examples = &[_]*anyopaque{}, .globs = @as(?*anyopaque, null), .name = \"\", .filename = @as(?[]const u8, null), .lineno = @as(?i32, null), .docstring = @as(?[]const u8, null) }") },
    .{ "Example", genConst(".{ .source = \"\", .want = \"\", .exc_msg = @as(?[]const u8, null), .lineno = @as(i32, 0), .indent = @as(i32, 0), .options = @as(?*anyopaque, null) }") },
    .{ "OutputChecker", genConst(".{}") }, .{ "DebugRunner", genConst(".{}") },
    .{ "OPTIONFLAGS", genConst("&[_][]const u8{ \"OPTIONFLAGS\", \"DONT_ACCEPT_TRUE_FOR_1\", \"DONT_ACCEPT_BLANKLINE\", \"NORMALIZE_WHITESPACE\", \"ELLIPSIS\", \"SKIP\", \"IGNORE_EXCEPTION_DETAIL\", \"COMPARISON_FLAGS\", \"REPORT_UDIFF\", \"REPORT_CDIFF\", \"REPORT_NDIFF\", \"REPORT_ONLY_FIRST_FAILURE\", \"FAIL_FAST\", \"REPORTING_FLAGS\" }") },
    .{ "ELLIPSIS", genConst("@as(i32, 8)") }, .{ "NORMALIZE_WHITESPACE", genConst("@as(i32, 4)") },
    .{ "DONT_ACCEPT_TRUE_FOR_1", genConst("@as(i32, 1)") }, .{ "DONT_ACCEPT_BLANKLINE", genConst("@as(i32, 2)") },
    .{ "SKIP", genConst("@as(i32, 16)") }, .{ "IGNORE_EXCEPTION_DETAIL", genConst("@as(i32, 32)") },
    .{ "REPORT_UDIFF", genConst("@as(i32, 256)") }, .{ "REPORT_CDIFF", genConst("@as(i32, 512)") }, .{ "REPORT_NDIFF", genConst("@as(i32, 1024)") },
    .{ "REPORT_ONLY_FIRST_FAILURE", genConst("@as(i32, 2048)") }, .{ "FAIL_FAST", genConst("@as(i32, 4096)") },
});
