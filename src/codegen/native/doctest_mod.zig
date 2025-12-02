/// Python doctest module - Test interactive Python examples
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "testmod", h.c(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }") },
    .{ "testfile", h.c(".{ .attempted = @as(i32, 0), .failed = @as(i32, 0) }") },
    .{ "run_docstring_examples", h.c("{}") },
    .{ "DocTestSuite", h.c("@as(?*anyopaque, null)") }, .{ "DocFileSuite", h.c("@as(?*anyopaque, null)") },
    .{ "DocTestParser", h.c(".{}") },
    .{ "DocTestRunner", h.c(".{ .verbose = false }") },
    .{ "DocTestFinder", h.c(".{ .verbose = false, .recurse = true }") },
    .{ "DocTest", h.c(".{ .examples = &[_]*anyopaque{}, .globs = @as(?*anyopaque, null), .name = \"\", .filename = @as(?[]const u8, null), .lineno = @as(?i32, null), .docstring = @as(?[]const u8, null) }") },
    .{ "Example", h.c(".{ .source = \"\", .want = \"\", .exc_msg = @as(?[]const u8, null), .lineno = @as(i32, 0), .indent = @as(i32, 0), .options = @as(?*anyopaque, null) }") },
    .{ "OutputChecker", h.c(".{}") }, .{ "DebugRunner", h.c(".{}") },
    .{ "OPTIONFLAGS", h.c("&[_][]const u8{ \"OPTIONFLAGS\", \"DONT_ACCEPT_TRUE_FOR_1\", \"DONT_ACCEPT_BLANKLINE\", \"NORMALIZE_WHITESPACE\", \"ELLIPSIS\", \"SKIP\", \"IGNORE_EXCEPTION_DETAIL\", \"COMPARISON_FLAGS\", \"REPORT_UDIFF\", \"REPORT_CDIFF\", \"REPORT_NDIFF\", \"REPORT_ONLY_FIRST_FAILURE\", \"FAIL_FAST\", \"REPORTING_FLAGS\" }") },
    .{ "ELLIPSIS", h.I32(8) }, .{ "NORMALIZE_WHITESPACE", h.I32(4) },
    .{ "DONT_ACCEPT_TRUE_FOR_1", h.I32(1) }, .{ "DONT_ACCEPT_BLANKLINE", h.I32(2) },
    .{ "SKIP", h.I32(16) }, .{ "IGNORE_EXCEPTION_DETAIL", h.I32(32) },
    .{ "REPORT_UDIFF", h.I32(256) }, .{ "REPORT_CDIFF", h.I32(512) }, .{ "REPORT_NDIFF", h.I32(1024) },
    .{ "REPORT_ONLY_FIRST_FAILURE", h.I32(2048) }, .{ "FAIL_FAST", h.I32(4096) },
});
