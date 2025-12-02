/// Python wsgiref module - WSGI utilities and reference implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.WSGIWarning"); }
fn genServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .server_address = .{ \"\", @as(i32, 8000) } }"); }
fn genWSGIServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .server_address = .{ \"\", @as(i32, 8000) }, .application = @as(?*anyopaque, null) }"); }
fn genReqUri(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"/\""); }
fn genAppUri(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"http://localhost/\""); }
fn genShiftPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[]const u8, null)"); }
fn genFileWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .filelike = @as(?*anyopaque, null), .blksize = @as(i32, 8192) }"); }
fn genHeaders(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .headers = &[_].{ []const u8, []const u8 }{} }"); }
fn genBaseHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .wsgi_multithread = true, .wsgi_multiprocess = true, .wsgi_run_once = false }"); }
fn genSimpleHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .stdin = @as(?*anyopaque, null), .stdout = @as(?*anyopaque, null), .stderr = @as(?*anyopaque, null), .environ = .{} }"); }
fn genDemoApp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{\"Hello world!\"}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "validator", genValidator }, .{ "assert_", genUnit }, .{ "check_status", genUnit }, .{ "check_headers", genUnit },
    .{ "check_content_type", genUnit }, .{ "check_exc_info", genUnit }, .{ "check_environ", genUnit }, .{ "WSGIWarning", genErr },
    .{ "make_server", genServer }, .{ "WSGIServer", genWSGIServer }, .{ "WSGIRequestHandler", genEmpty }, .{ "demo_app", genDemoApp },
    .{ "setup_testing_defaults", genUnit }, .{ "request_uri", genReqUri }, .{ "application_uri", genAppUri },
    .{ "shift_path_info", genShiftPath }, .{ "FileWrapper", genFileWrapper }, .{ "Headers", genHeaders },
    .{ "BaseHandler", genBaseHandler }, .{ "SimpleHandler", genSimpleHandler }, .{ "BaseCGIHandler", genSimpleHandler },
    .{ "CGIHandler", genEmpty }, .{ "IISCGIHandler", genEmpty },
});

fn genValidator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("@as(?*anyopaque, null)"); }
}
