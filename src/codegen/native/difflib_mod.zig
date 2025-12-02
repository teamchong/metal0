/// Python difflib module - Helpers for computing deltas
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SequenceMatcher", genConst("struct { a: []const u8 = \"\", b: []const u8 = \"\", pub fn set_seqs(__self: *@This(), a: []const u8, b: []const u8) void { __self.a = a; __self.b = b; } pub fn set_seq1(__self: *@This(), a: []const u8) void { __self.a = a; } pub fn set_seq2(__self: *@This(), b: []const u8) void { __self.b = b; } pub fn ratio(__self: *@This()) f64 { if (__self.a.len == 0 and __self.b.len == 0) return 1.0; var matches: usize = 0; const min_len = @min(__self.a.len, __self.b.len); for (0..min_len) |i| { if (__self.a[i] == __self.b[i]) matches += 1; } return 2.0 * @as(f64, @floatFromInt(matches)) / @as(f64, @floatFromInt(__self.a.len + __self.b.len)); } pub fn quick_ratio(__self: *@This()) f64 { return __self.ratio(); } pub fn real_quick_ratio(__self: *@This()) f64 { return __self.ratio(); } pub fn get_matching_blocks(__self: *@This()) []struct { a: usize, b: usize, size: usize } { return &.{}; } pub fn get_opcodes(__self: *@This()) []struct { tag: []const u8, i1: usize, i2: usize, j1: usize, j2: usize } { return &.{}; } pub fn get_grouped_opcodes(__self: *@This(), n: usize) [][]struct { tag: []const u8, i1: usize, i2: usize, j1: usize, j2: usize } { _ = n; return &.{}; } }{}") },
    .{ "Differ", genConst("struct { pub fn compare(self: @This(), a: [][]const u8, b: [][]const u8) [][]const u8 { _ = a; _ = b; return &[_][]const u8{}; } }{}") },
    .{ "HtmlDiff", genConst("struct { tabsize: i64 = 8, pub fn make_file(self: @This(), fromlines: anytype, tolines: anytype) []const u8 { _ = fromlines; _ = tolines; return \"\"; } pub fn make_table(self: @This(), fromlines: anytype, tolines: anytype) []const u8 { _ = fromlines; _ = tolines; return \"\"; } }{}") },
    .{ "get_close_matches", genConst("&[_][]const u8{}") }, .{ "unified_diff", genConst("&[_][]const u8{}") },
    .{ "context_diff", genConst("&[_][]const u8{}") }, .{ "ndiff", genConst("&[_][]const u8{}") },
    .{ "restore", genConst("&[_][]const u8{}") }, .{ "IS_LINE_JUNK", genConst("false") },
    .{ "IS_CHARACTER_JUNK", genConst("false") }, .{ "diff_bytes", genConst("&[_][]const u8{}") },
});
