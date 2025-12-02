/// Python cgi module - CGI utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genConst(".{}") }, .{ "parse_qs", genConst(".{}") }, .{ "parse_multipart", genConst(".{}") },
    .{ "parse_qsl", genConst("&[_].{ []const u8, []const u8 }{}") }, .{ "parse_header", genConst(".{ \"\", .{} }") },
    .{ "test", genConst("{}") }, .{ "print_environ", genConst("{}") }, .{ "print_form", genConst("{}") },
    .{ "print_directory", genConst("{}") }, .{ "print_environ_usage", genConst("{}") },
    .{ "escape", genEscape }, .{ "FieldStorage", genConst(".{ .name = @as(?[]const u8, null), .filename = @as(?[]const u8, null), .value = @as(?[]const u8, null), .file = @as(?*anyopaque, null), .type = \"text/plain\", .type_options = .{}, .disposition = @as(?[]const u8, null), .disposition_options = .{}, .headers = .{}, .list = @as(?*anyopaque, null) }") },
    .{ "MiniFieldStorage", genConst(".{ .name = @as(?[]const u8, null), .value = @as(?[]const u8, null) }") },
    .{ "maxlen", genConst("@as(i64, 0)") },
});

fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
