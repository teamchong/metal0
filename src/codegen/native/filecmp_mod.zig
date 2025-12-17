/// Python filecmp module - File and Directory Comparisons
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "cmp", genCmp },
    .{ "cmpfiles", genCmpfiles },
    .{ "dircmp", genDircmp },
    .{ "clear_cache", genClearCache },
    .{ "DEFAULT_IGNORES", genDefaultIgnores },
});

fn genCmp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genCmpfiles(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ &[_][]const u8{}, &[_][]const u8{}, &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genDircmp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { left: []const u8 = \"\", right: []const u8 = \"\", left_list: [][]const u8 = &[_][]const u8{}, right_list: [][]const u8 = &[_][]const u8{}, common: [][]const u8 = &[_][]const u8{}, common_dirs: [][]const u8 = &[_][]const u8{}, common_files: [][]const u8 = &[_][]const u8{}, common_funny: [][]const u8 = &[_][]const u8{}, left_only: [][]const u8 = &[_][]const u8{}, right_only: [][]const u8 = &[_][]const u8{}, same_files: [][]const u8 = &[_][]const u8{}, diff_files: [][]const u8 = &[_][]const u8{}, funny_files: [][]const u8 = &[_][]const u8{}, subdirs: hashmap_helper.StringHashMap(*@This()) = .{}, pub fn report(__self: *@This()) void { _ = __self; } pub fn report_partial_closure(__self: *@This()) void { _ = __self; } pub fn report_full_closure(__self: *@This()) void { _ = __self; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genClearCache(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDefaultIgnores(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"RCS\", \"CVS\", \"tags\", \".git\", \".hg\", \".bzr\", \"_darcs\", \"__pycache__\" }"), builder_mod.EmitConfig.forExpression());
}
