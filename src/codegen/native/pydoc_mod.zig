/// Python pydoc module - Documentation generation and display
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "help", genConst("{}") }, .{ "doc", genConst("{}") }, .{ "writedoc", genConst("{}") }, .{ "writedocs", genConst("{}") },
    .{ "render_doc", genConst("\"\"") }, .{ "plain", genPlain }, .{ "describe", genConst("\"object\"") },
    .{ "locate", genConst("null") }, .{ "resolve", genConst(".{ null, \"\" }") }, .{ "getdoc", genConst("\"\"") },
    .{ "splitdoc", genConst(".{ \"\", \"\" }") }, .{ "classname", genConst("\"object\"") }, .{ "isdata", genConst("false") },
    .{ "ispackage", genConst("false") }, .{ "source_synopsis", genConst("null") }, .{ "synopsis", genConst("null") },
    .{ "allmethods", genConst(".{}") }, .{ "apropos", genConst("{}") }, .{ "serve", genConst("{}") }, .{ "browse", genConst("{}") },
});

fn genPlain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
