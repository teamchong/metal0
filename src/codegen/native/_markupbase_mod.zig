/// Python _markupbase module - Internal markup base support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parser_base", genConst(".{ .lasttag = \"\", .interesting = null }") }, .{ "reset", genConst("{}") },
    .{ "getpos", genConst(".{ @as(i64, 1), @as(i64, 0) }") }, .{ "updatepos", genConst("@as(i64, 0)") }, .{ "error", genConst("error.ParserError") },
});
