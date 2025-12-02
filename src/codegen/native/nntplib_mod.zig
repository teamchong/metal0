/// Python nntplib module - NNTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNNTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 119), .timeout = @as(f64, -1.0) }"); }
fn genNNTP_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 563), .timeout = @as(f64, -1.0) }"); }
fn genPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 119)"); }
fn genSslPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 563)"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NNTPError"); }
fn genReplyErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NNTPReplyError"); }
fn genTempErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NNTPTemporaryError"); }
fn genPermErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NNTPPermanentError"); }
fn genProtoErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NNTPProtocolError"); }
fn genDataErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NNTPDataError"); }
fn genGroupInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .group = \"\", .last = @as(i32, 0), .first = @as(i32, 0), .flag = \"\" }"); }
fn genArticleInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .number = @as(i32, 0), .message_id = \"\", .lines = &[_][]const u8{} }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "NNTP", genNNTP }, .{ "NNTP_SSL", genNNTP_SSL }, .{ "NNTP_PORT", genPort }, .{ "NNTP_SSL_PORT", genSslPort },
    .{ "NNTPError", genErr }, .{ "NNTPReplyError", genReplyErr }, .{ "NNTPTemporaryError", genTempErr },
    .{ "NNTPPermanentError", genPermErr }, .{ "NNTPProtocolError", genProtoErr }, .{ "NNTPDataError", genDataErr },
    .{ "GroupInfo", genGroupInfo }, .{ "ArticleInfo", genArticleInfo }, .{ "decode_header", genDecodeHeader },
});

fn genDecodeHeader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
