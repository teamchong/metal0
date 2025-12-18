/// Python difflib module - Helpers for computing deltas
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SequenceMatcher", genSequenceMatcher },
    .{ "Differ", genDiffer },
    .{ "HtmlDiff", genHtmlDiff },
    .{ "get_close_matches", genGetCloseMatches },
    .{ "unified_diff", genUnifiedDiff },
    .{ "context_diff", genContextDiff },
    .{ "ndiff", genNdiff },
    .{ "restore", genRestore },
    .{ "IS_LINE_JUNK", genIsLineJunk },
    .{ "IS_CHARACTER_JUNK", genIsCharacterJunk },
    .{ "diff_bytes", genDiffBytes },
});

fn genSequenceMatcher(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { a: []const u8 = \"\", b: []const u8 = \"\", pub fn set_seqs(__self: *@This(), a: []const u8, b: []const u8) void { __self.a = a; __self.b = b; } pub fn set_seq1(__self: *@This(), a: []const u8) void { __self.a = a; } pub fn set_seq2(__self: *@This(), b: []const u8) void { __self.b = b; } pub fn ratio(__self: *@This()) f64 { if (__self.a.len == 0 and __self.b.len == 0) return 1.0; var matches: usize = 0; const min_len = @min(__self.a.len, __self.b.len); for (0..min_len) |i| { if (__self.a[i] == __self.b[i]) matches += 1; } return 2.0 * @as(f64, @floatFromInt(matches)) / @as(f64, @floatFromInt(__self.a.len + __self.b.len)); } pub fn quick_ratio(__self: *@This()) f64 { return __self.ratio(); } pub fn real_quick_ratio(__self: *@This()) f64 { return __self.ratio(); } pub fn get_matching_blocks(__self: *@This()) []struct { a: usize, b: usize, size: usize } { return &.{}; } pub fn get_opcodes(__self: *@This()) []struct { tag: []const u8, i1: usize, i2: usize, j1: usize, j2: usize } { return &.{}; } pub fn get_grouped_opcodes(__self: *@This(), n: usize) [][]struct { tag: []const u8, i1: usize, i2: usize, j1: usize, j2: usize } { _ = n; return &.{}; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genDiffer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pub fn compare(__self: @This(), a: [][]const u8, b: [][]const u8) [][]const u8 { _ = &__self; _ = a; _ = b; return &[_][]const u8{}; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genHtmlDiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { tabsize: i64 = 8, pub fn make_file(__self: @This(), fromlines: anytype, tolines: anytype) []const u8 { _ = &__self; _ = fromlines; _ = tolines; return \"\"; } pub fn make_table(__self: @This(), fromlines: anytype, tolines: anytype) []const u8 { _ = &__self; _ = fromlines; _ = tolines; return \"\"; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetCloseMatches(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnifiedDiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genContextDiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genNdiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genRestore(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genIsLineJunk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genIsCharacterJunk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genDiffBytes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}
