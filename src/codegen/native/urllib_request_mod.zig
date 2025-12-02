/// Python urllib.request module - URL handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "urlopen", genConst(".{ .status = @as(i32, 200), .reason = \"OK\", .headers = .{}, .url = \"\" }") },
    .{ "install_opener", genConst("{}") },
    .{ "build_opener", genConst(".{ .handlers = &[_]*anyopaque{} }") },
    .{ "pathname2url", genPassthrough }, .{ "url2pathname", genPassthrough },
    .{ "getproxies", genConst(".{}") },
    .{ "Request", genRequest }, .{ "OpenerDirector", genConst(".{ .handlers = &[_]*anyopaque{} }") },
    .{ "BaseHandler", genConst(".{}") }, .{ "HTTPDefaultErrorHandler", genConst(".{}") },
    .{ "HTTPRedirectHandler", genConst(".{ .max_redirections = @as(i32, 10), .max_repeats = @as(i32, 4) }") },
    .{ "HTTPCookieProcessor", genConst(".{ .cookiejar = @as(?*anyopaque, null) }") },
    .{ "ProxyHandler", genConst(".{ .proxies = .{} }") },
    .{ "HTTPPasswordMgr", genConst(".{}") }, .{ "HTTPPasswordMgrWithDefaultRealm", genConst(".{}") },
    .{ "HTTPPasswordMgrWithPriorAuth", genConst(".{}") },
    .{ "AbstractBasicAuthHandler", genConst(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "HTTPBasicAuthHandler", genConst(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "ProxyBasicAuthHandler", genConst(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "AbstractDigestAuthHandler", genConst(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "HTTPDigestAuthHandler", genConst(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "ProxyDigestAuthHandler", genConst(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "HTTPHandler", genConst(".{}") }, .{ "HTTPSHandler", genConst(".{ .context = @as(?*anyopaque, null), .check_hostname = @as(?bool, null) }") },
    .{ "FileHandler", genConst(".{}") }, .{ "FTPHandler", genConst(".{}") },
    .{ "CacheFTPHandler", genConst(".{ .max_conns = @as(i32, 0) }") }, .{ "DataHandler", genConst(".{}") },
    .{ "UnknownHandler", genConst(".{}") }, .{ "HTTPErrorProcessor", genConst(".{}") },
    .{ "URLError", genConst("error.URLError") }, .{ "HTTPError", genConst("error.HTTPError") },
    .{ "ContentTooShortError", genConst("error.ContentTooShortError") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

fn genRequest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = "); try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .full_url = url, .type = \"GET\", .data = @as(?[]const u8, null), .headers = .{}, .origin_req_host = @as(?[]const u8, null), .unverifiable = false, .method = @as(?[]const u8, null) }; }");
    } else try self.emit(".{ .full_url = \"\", .type = \"GET\", .data = @as(?[]const u8, null), .headers = .{}, .origin_req_host = @as(?[]const u8, null), .unverifiable = false, .method = @as(?[]const u8, null) }");
}
