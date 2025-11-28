/// Python nntplib module - NNTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate nntplib.NNTP class
pub fn genNNTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 119), .timeout = @as(f64, -1.0) }");
}

/// Generate nntplib.NNTP_SSL class
pub fn genNNTP_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 563), .timeout = @as(f64, -1.0) }");
}

// ============================================================================
// Port constants
// ============================================================================

pub fn genNNTP_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 119)");
}

pub fn genNNTP_SSL_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 563)");
}

// ============================================================================
// Exception and info classes
// ============================================================================

pub fn genNNTPError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NNTPError");
}

pub fn genNNTPReplyError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NNTPReplyError");
}

pub fn genNNTPTemporaryError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NNTPTemporaryError");
}

pub fn genNNTPPermanentError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NNTPPermanentError");
}

pub fn genNNTPProtocolError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NNTPProtocolError");
}

pub fn genNNTPDataError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NNTPDataError");
}

/// Generate nntplib.GroupInfo namedtuple
pub fn genGroupInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .group = \"\", .last = @as(i32, 0), .first = @as(i32, 0), .flag = \"\" }");
}

/// Generate nntplib.ArticleInfo namedtuple
pub fn genArticleInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .number = @as(i32, 0), .message_id = \"\", .lines = &[_][]const u8{} }");
}

/// Generate nntplib.decode_header(header_str) function
pub fn genDecode_header(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}
