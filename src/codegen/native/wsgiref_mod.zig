/// Python wsgiref module - WSGI utilities and reference implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "validator", genValidator },
    .{ "assert_", genConst("{}") }, .{ "check_status", genConst("{}") }, .{ "check_headers", genConst("{}") },
    .{ "check_content_type", genConst("{}") }, .{ "check_exc_info", genConst("{}") }, .{ "check_environ", genConst("{}") },
    .{ "WSGIWarning", genConst("error.WSGIWarning") },
    .{ "make_server", genConst(".{ .server_address = .{ \"\", @as(i32, 8000) } }") },
    .{ "WSGIServer", genConst(".{ .server_address = .{ \"\", @as(i32, 8000) }, .application = @as(?*anyopaque, null) }") },
    .{ "WSGIRequestHandler", genConst(".{}") },
    .{ "demo_app", genConst("&[_][]const u8{\"Hello world!\"}") },
    .{ "setup_testing_defaults", genConst("{}") },
    .{ "request_uri", genConst("\"/\"") }, .{ "application_uri", genConst("\"http://localhost/\"") },
    .{ "shift_path_info", genConst("@as(?[]const u8, null)") },
    .{ "FileWrapper", genConst(".{ .filelike = @as(?*anyopaque, null), .blksize = @as(i32, 8192) }") },
    .{ "Headers", genConst(".{ .headers = &[_].{ []const u8, []const u8 }{} }") },
    .{ "BaseHandler", genConst(".{ .wsgi_multithread = true, .wsgi_multiprocess = true, .wsgi_run_once = false }") },
    .{ "SimpleHandler", genConst(".{ .stdin = @as(?*anyopaque, null), .stdout = @as(?*anyopaque, null), .stderr = @as(?*anyopaque, null), .environ = .{} }") },
    .{ "BaseCGIHandler", genConst(".{ .stdin = @as(?*anyopaque, null), .stdout = @as(?*anyopaque, null), .stderr = @as(?*anyopaque, null), .environ = .{} }") },
    .{ "CGIHandler", genConst(".{}") }, .{ "IISCGIHandler", genConst(".{}") },
});

fn genValidator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("@as(?*anyopaque, null)"); }
}
