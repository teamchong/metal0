/// Python difflib module - Helpers for computing deltas
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate difflib.SequenceMatcher(isjunk=None, a='', b='', autojunk=True)
pub fn genSequenceMatcher(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("a: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("b: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn set_seqs(self: *@This(), a: []const u8, b: []const u8) void { self.a = a; self.b = b; }\n");
    try self.emitIndent();
    try self.emit("pub fn set_seq1(self: *@This(), a: []const u8) void { self.a = a; }\n");
    try self.emitIndent();
    try self.emit("pub fn set_seq2(self: *@This(), b: []const u8) void { self.b = b; }\n");
    try self.emitIndent();
    try self.emit("pub fn ratio(self: *@This()) f64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self.a.len == 0 and self.b.len == 0) return 1.0;\n");
    try self.emitIndent();
    try self.emit("var matches: usize = 0;\n");
    try self.emitIndent();
    try self.emit("const min_len = @min(self.a.len, self.b.len);\n");
    try self.emitIndent();
    try self.emit("for (0..min_len) |i| { if (self.a[i] == self.b[i]) matches += 1; }\n");
    try self.emitIndent();
    try self.emit("return 2.0 * @as(f64, @floatFromInt(matches)) / @as(f64, @floatFromInt(self.a.len + self.b.len));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn quick_ratio(self: *@This()) f64 { return self.ratio(); }\n");
    try self.emitIndent();
    try self.emit("pub fn real_quick_ratio(self: *@This()) f64 { return self.ratio(); }\n");
    try self.emitIndent();
    try self.emit("pub fn get_matching_blocks(self: *@This()) []struct { a: usize, b: usize, size: usize } { _ = self; return &.{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_opcodes(self: *@This()) []struct { tag: []const u8, i1: usize, i2: usize, j1: usize, j2: usize } { _ = self; return &.{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_grouped_opcodes(self: *@This(), n: usize) [][]struct { tag: []const u8, i1: usize, i2: usize, j1: usize, j2: usize } { _ = self; _ = n; return &.{}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate difflib.Differ(linejunk=None, charjunk=None)
pub fn genDiffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn compare(self: @This(), a: [][]const u8, b: [][]const u8) [][]const u8 { _ = self; _ = a; _ = b; return &[_][]const u8{}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate difflib.HtmlDiff(tabsize=8, wrapcolumn=None, linejunk=None, charjunk=None)
pub fn genHtmlDiff(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("tabsize: i64 = 8,\n");
    try self.emitIndent();
    try self.emit("pub fn make_file(self: @This(), fromlines: anytype, tolines: anytype) []const u8 { _ = self; _ = fromlines; _ = tolines; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn make_table(self: @This(), fromlines: anytype, tolines: anytype) []const u8 { _ = self; _ = fromlines; _ = tolines; return \"\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate difflib.get_close_matches(word, possibilities, n=3, cutoff=0.6)
pub fn genGetCloseMatches(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate difflib.unified_diff(a, b, fromfile='', tofile='', ...)
pub fn genUnifiedDiff(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate difflib.context_diff(a, b, fromfile='', tofile='', ...)
pub fn genContextDiff(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate difflib.ndiff(a, b, linejunk=None, charjunk=None)
pub fn genNdiff(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate difflib.restore(delta, which)
pub fn genRestore(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate difflib.IS_LINE_JUNK(line)
pub fn genIsLineJunk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate difflib.IS_CHARACTER_JUNK(ch)
pub fn genIsCharacterJunk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate difflib.diff_bytes(dfunc, a, b, ...)
pub fn genDiffBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}
