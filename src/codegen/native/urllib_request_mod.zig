/// Python urllib.request module - URL handling
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "urlopen", h.c(".{ .status = @as(i32, 200), .reason = \"OK\", .headers = .{}, .url = \"\" }") },
    .{ "install_opener", h.c("{}") },
    .{ "build_opener", h.c(".{ .handlers = &[_]*anyopaque{} }") },
    .{ "pathname2url", h.pass("\"\"") }, .{ "url2pathname", h.pass("\"\"") },
    .{ "getproxies", h.c(".{}") },
    .{ "Request", h.wrap("blk: { const url = ", "; break :blk .{ .full_url = url, .type = \"GET\", .data = @as(?[]const u8, null), .headers = .{}, .origin_req_host = @as(?[]const u8, null), .unverifiable = false, .method = @as(?[]const u8, null) }; }", ".{ .full_url = \"\", .type = \"GET\", .data = @as(?[]const u8, null), .headers = .{}, .origin_req_host = @as(?[]const u8, null), .unverifiable = false, .method = @as(?[]const u8, null) }") },
    .{ "OpenerDirector", h.c(".{ .handlers = &[_]*anyopaque{} }") },
    .{ "BaseHandler", h.c(".{}") }, .{ "HTTPDefaultErrorHandler", h.c(".{}") },
    .{ "HTTPRedirectHandler", h.c(".{ .max_redirections = @as(i32, 10), .max_repeats = @as(i32, 4) }") },
    .{ "HTTPCookieProcessor", h.c(".{ .cookiejar = @as(?*anyopaque, null) }") },
    .{ "ProxyHandler", h.c(".{ .proxies = .{} }") },
    .{ "HTTPPasswordMgr", h.c(".{}") }, .{ "HTTPPasswordMgrWithDefaultRealm", h.c(".{}") },
    .{ "HTTPPasswordMgrWithPriorAuth", h.c(".{}") },
    .{ "AbstractBasicAuthHandler", h.c(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "HTTPBasicAuthHandler", h.c(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "ProxyBasicAuthHandler", h.c(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "AbstractDigestAuthHandler", h.c(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "HTTPDigestAuthHandler", h.c(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "ProxyDigestAuthHandler", h.c(".{ .passwd = @as(?*anyopaque, null) }") },
    .{ "HTTPHandler", h.c(".{}") }, .{ "HTTPSHandler", h.c(".{ .context = @as(?*anyopaque, null), .check_hostname = @as(?bool, null) }") },
    .{ "FileHandler", h.c(".{}") }, .{ "FTPHandler", h.c(".{}") },
    .{ "CacheFTPHandler", h.c(".{ .max_conns = @as(i32, 0) }") }, .{ "DataHandler", h.c(".{}") },
    .{ "UnknownHandler", h.c(".{}") }, .{ "HTTPErrorProcessor", h.c(".{}") },
    .{ "URLError", h.err("URLError") }, .{ "HTTPError", h.err("HTTPError") },
    .{ "ContentTooShortError", h.err("ContentTooShortError") },
});

