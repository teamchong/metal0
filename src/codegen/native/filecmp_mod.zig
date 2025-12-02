/// Python filecmp module - File and Directory Comparisons
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "cmp", genConst("true") }, .{ "cmpfiles", genConst(".{ &[_][]const u8{}, &[_][]const u8{}, &[_][]const u8{} }") },
    .{ "dircmp", genConst("struct { left: []const u8 = \"\", right: []const u8 = \"\", left_list: [][]const u8 = &[_][]const u8{}, right_list: [][]const u8 = &[_][]const u8{}, common: [][]const u8 = &[_][]const u8{}, common_dirs: [][]const u8 = &[_][]const u8{}, common_files: [][]const u8 = &[_][]const u8{}, common_funny: [][]const u8 = &[_][]const u8{}, left_only: [][]const u8 = &[_][]const u8{}, right_only: [][]const u8 = &[_][]const u8{}, same_files: [][]const u8 = &[_][]const u8{}, diff_files: [][]const u8 = &[_][]const u8{}, funny_files: [][]const u8 = &[_][]const u8{}, subdirs: hashmap_helper.StringHashMap(*@This()) = .{}, pub fn report(__self: *@This()) void { _ = __self; } pub fn report_partial_closure(__self: *@This()) void { _ = __self; } pub fn report_full_closure(__self: *@This()) void { _ = __self; } }{}") },
    .{ "clear_cache", genConst("{}") }, .{ "DEFAULT_IGNORES", genConst("&[_][]const u8{ \"RCS\", \"CVS\", \"tags\", \".git\", \".hg\", \".bzr\", \"_darcs\", \"__pycache__\" }") },
});
