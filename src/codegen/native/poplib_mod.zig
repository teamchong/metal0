/// Python poplib module - POP3 protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "POP3", genConst(".{ .host = \"\", .port = @as(i32, 110), .timeout = @as(f64, -1.0) }") },
    .{ "POP3_SSL", genConst(".{ .host = \"\", .port = @as(i32, 995), .timeout = @as(f64, -1.0) }") },
    .{ "POP3_PORT", genConst("@as(i32, 110)") }, .{ "POP3_SSL_PORT", genConst("@as(i32, 995)") },
    .{ "error_proto", genConst("error.POP3ProtoError") },
});
