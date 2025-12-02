/// Python http.cookiejar module - Cookie handling for HTTP clients
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "CookieJar", h.c(".{ .policy = @as(?*anyopaque, null) }") }, .{ "FileCookieJar", genFileCookieJar },
    .{ "MozillaCookieJar", genFileCookieJar }, .{ "LWPCookieJar", genFileCookieJar },
    .{ "Cookie", h.c(".{ .version = @as(i32, 0), .name = \"\", .value = \"\", .port = @as(?[]const u8, null), .port_specified = false, .domain = \"\", .domain_specified = false, .domain_initial_dot = false, .path = \"/\", .path_specified = false, .secure = false, .expires = @as(?i64, null), .discard = true, .comment = @as(?[]const u8, null), .comment_url = @as(?[]const u8, null), .rest = .{}, .rfc2109 = false }") },
    .{ "DefaultCookiePolicy", h.c(".{ .netscape = true, .rfc2965 = false, .rfc2109_as_netscape = @as(?bool, null), .hide_cookie2 = false, .strict_domain = false, .strict_rfc2965_unverifiable = true, .strict_ns_unverifiable = false, .strict_ns_domain = @as(i32, 0), .strict_ns_set_initial_dollar = false, .strict_ns_set_path = false }") },
    .{ "BlockingPolicy", h.c(".{}") }, .{ "BlockAllCookies", h.c(".{}") },
    .{ "DomainStrictNoDots", h.I32(1) }, .{ "DomainStrictNonDomain", h.I32(2) },
    .{ "DomainRFC2965Match", h.I32(4) }, .{ "DomainLiberal", h.I32(0) }, .{ "DomainStrict", h.I32(3) },
    .{ "LoadError", h.err("LoadError") }, .{ "time2isoz", h.c("\"1970-01-01 00:00:00Z\"") }, .{ "time2netscape", h.c("\"Thu, 01-Jan-1970 00:00:00 GMT\"") },
});

fn genFileCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const filename = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .filename = filename, .delayload = false }; }"); }
    else { try self.emit(".{ .filename = @as(?[]const u8, null), .delayload = false }"); }
}
