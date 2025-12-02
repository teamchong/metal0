/// Python ast module - Abstract Syntax Trees
const std = @import("std");
const ast_types = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast_types.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast_types.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i32, 0x{x})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genConst("@as(?*anyopaque, null)") }, .{ "literal_eval", genConst("@as(?*anyopaque, null)") },
    .{ "fix_missing_locations", genConst("@as(?*anyopaque, null)") }, .{ "increment_lineno", genConst("@as(?*anyopaque, null)") },
    .{ "copy_location", genConst("@as(?*anyopaque, null)") }, .{ "dump", genConst("\"\"") }, .{ "unparse", genConst("\"\"") },
    .{ "get_docstring", genConst("null") }, .{ "get_source_segment", genConst("null") },
    .{ "iter_fields", genConst("&[_]struct { name: []const u8, value: *anyopaque }{}") },
    .{ "iter_child_nodes", genConst("&[_]*anyopaque{}") }, .{ "walk", genConst("&[_]*anyopaque{}") },
    .{ "AST", genConst(".{}") }, .{ "NodeVisitor", genConst(".{}") }, .{ "NodeTransformer", genConst(".{}") },
    .{ "Module", genConst(".{ .body = &[_]*anyopaque{}, .type_ignores = &[_]*anyopaque{} }") },
    .{ "Expression", genConst(".{ .body = @as(?*anyopaque, null) }") },
    .{ "Interactive", genConst(".{ .body = &[_]*anyopaque{} }") },
    .{ "FunctionDef", genConst(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }") },
    .{ "AsyncFunctionDef", genConst(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }") },
    .{ "ClassDef", genConst(".{ .name = \"\", .bases = &[_]*anyopaque{}, .keywords = &[_]*anyopaque{}, .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{} }") },
    .{ "Return", genConst(".{ .value = @as(?*anyopaque, null) }") },
    .{ "Name", genConst(".{ .id = \"\", .ctx = @as(?*anyopaque, null) }") },
    .{ "Constant", genConst(".{ .value = @as(?*anyopaque, null), .kind = @as(?[]const u8, null) }") },
    .{ "PyCF_ONLY_AST", genI32(0x400) }, .{ "PyCF_TYPE_COMMENTS", genI32(0x1000) },
});
