/// Python pipes module - Interface to shell pipelines (deprecated in 3.11)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Template", genConst(".{ .steps = &[_][]const u8{}, .debugging = false }") }, .{ "reset", genConst("{}") },
    .{ "clone", genConst(".{ .steps = &[_][]const u8{}, .debugging = false }") }, .{ "debug", genConst("{}") },
    .{ "append", genConst("{}") }, .{ "prepend", genConst("{}") }, .{ "open", genConst("null") }, .{ "copy", genConst("{}") },
    .{ "FILEIN_FILEOUT", genConst("\"ff\"") }, .{ "STDIN_FILEOUT", genConst("\"-f\"") },
    .{ "FILEIN_STDOUT", genConst("\"f-\"") }, .{ "STDIN_STDOUT", genConst("\"--\"") },
    .{ "quote", genQuote },
});

fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; _ = s; break :blk \"''\"; }"); }
    else try self.emit("\"''\"");
}
