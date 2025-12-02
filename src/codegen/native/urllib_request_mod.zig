/// Python urllib.request module - URL handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "urlopen", genUrlopen }, .{ "install_opener", genUnit }, .{ "build_opener", genBuildOpener },
    .{ "pathname2url", genPassthrough }, .{ "url2pathname", genPassthrough }, .{ "getproxies", genEmpty },
    .{ "Request", genRequest }, .{ "OpenerDirector", genBuildOpener },
    .{ "BaseHandler", genEmpty }, .{ "HTTPDefaultErrorHandler", genEmpty },
    .{ "HTTPRedirectHandler", genRedirectHandler }, .{ "HTTPCookieProcessor", genCookieProcessor },
    .{ "ProxyHandler", genProxyHandler }, .{ "HTTPPasswordMgr", genEmpty },
    .{ "HTTPPasswordMgrWithDefaultRealm", genEmpty }, .{ "HTTPPasswordMgrWithPriorAuth", genEmpty },
    .{ "AbstractBasicAuthHandler", genPasswdHandler }, .{ "HTTPBasicAuthHandler", genPasswdHandler },
    .{ "ProxyBasicAuthHandler", genPasswdHandler }, .{ "AbstractDigestAuthHandler", genPasswdHandler },
    .{ "HTTPDigestAuthHandler", genPasswdHandler }, .{ "ProxyDigestAuthHandler", genPasswdHandler },
    .{ "HTTPHandler", genEmpty }, .{ "HTTPSHandler", genHTTPSHandler },
    .{ "FileHandler", genEmpty }, .{ "FTPHandler", genEmpty },
    .{ "CacheFTPHandler", genCacheFTPHandler }, .{ "DataHandler", genEmpty },
    .{ "UnknownHandler", genEmpty }, .{ "HTTPErrorProcessor", genEmpty },
    .{ "URLError", genURLError }, .{ "HTTPError", genHTTPError }, .{ "ContentTooShortError", genContentTooShortError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

// Struct constants
fn genUrlopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .status = @as(i32, 200), .reason = \"OK\", .headers = .{}, .url = \"\" }"); }
fn genBuildOpener(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .handlers = &[_]*anyopaque{} }"); }
fn genRedirectHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .max_redirections = @as(i32, 10), .max_repeats = @as(i32, 4) }"); }
fn genCookieProcessor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .cookiejar = @as(?*anyopaque, null) }"); }
fn genProxyHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .proxies = .{} }"); }
fn genPasswdHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .passwd = @as(?*anyopaque, null) }"); }
fn genHTTPSHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .context = @as(?*anyopaque, null), .check_hostname = @as(?bool, null) }"); }
fn genCacheFTPHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .max_conns = @as(i32, 0) }"); }

// Exceptions
fn genURLError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.URLError"); }
fn genHTTPError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.HTTPError"); }
fn genContentTooShortError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ContentTooShortError"); }

// Functions with logic
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

fn genRequest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = "); try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .full_url = url, .type = \"GET\", .data = @as(?[]const u8, null), .headers = .{}, .origin_req_host = @as(?[]const u8, null), .unverifiable = false, .method = @as(?[]const u8, null) }; }");
    } else try self.emit(".{ .full_url = \"\", .type = \"GET\", .data = @as(?[]const u8, null), .headers = .{}, .origin_req_host = @as(?[]const u8, null), .unverifiable = false, .method = @as(?[]const u8, null) }");
}
