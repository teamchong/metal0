/// Python nntplib module - NNTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "NNTP", genConst(".{ .host = \"\", .port = @as(i32, 119), .timeout = @as(f64, -1.0) }") },
    .{ "NNTP_SSL", genConst(".{ .host = \"\", .port = @as(i32, 563), .timeout = @as(f64, -1.0) }") },
    .{ "NNTP_PORT", genConst("@as(i32, 119)") }, .{ "NNTP_SSL_PORT", genConst("@as(i32, 563)") },
    .{ "NNTPError", genConst("error.NNTPError") }, .{ "NNTPReplyError", genConst("error.NNTPReplyError") },
    .{ "NNTPTemporaryError", genConst("error.NNTPTemporaryError") }, .{ "NNTPPermanentError", genConst("error.NNTPPermanentError") },
    .{ "NNTPProtocolError", genConst("error.NNTPProtocolError") }, .{ "NNTPDataError", genConst("error.NNTPDataError") },
    .{ "GroupInfo", genConst(".{ .group = \"\", .last = @as(i32, 0), .first = @as(i32, 0), .flag = \"\" }") },
    .{ "ArticleInfo", genConst(".{ .number = @as(i32, 0), .message_id = \"\", .lines = &[_][]const u8{} }") },
    .{ "decode_header", genDecodeHeader },
});

fn genDecodeHeader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
