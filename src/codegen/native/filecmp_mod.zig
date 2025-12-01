/// Python filecmp module - File and Directory Comparisons
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "cmp", genCmp },
    .{ "cmpfiles", genCmpfiles },
    .{ "dircmp", genDircmp },
    .{ "clear_cache", genClearCache },
    .{ "DEFAULT_IGNORES", genDEFAULT_IGNORES },
});

/// Generate filecmp.cmp(f1, f2, shallow=True) -> bool
pub fn genCmp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate filecmp.cmpfiles(dir1, dir2, common, shallow=True) -> (match, mismatch, errors)
pub fn genCmpfiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_][]const u8{}, &[_][]const u8{}, &[_][]const u8{} }");
}

/// Generate filecmp.dircmp(a, b, ignore=None, hide=None) -> dircmp object
pub fn genDircmp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("left: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("right: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("left_list: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("right_list: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("common: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("common_dirs: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("common_files: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("common_funny: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("left_only: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("right_only: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("same_files: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("diff_files: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("funny_files: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("subdirs: hashmap_helper.StringHashMap(*@This()) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn report(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn report_partial_closure(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn report_full_closure(self: *@This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate filecmp.clear_cache() -> None
pub fn genClearCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate filecmp.DEFAULT_IGNORES constant
pub fn genDEFAULT_IGNORES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"RCS\", \"CVS\", \"tags\", \".git\", \".hg\", \".bzr\", \"_darcs\", \"__pycache__\" }");
}
