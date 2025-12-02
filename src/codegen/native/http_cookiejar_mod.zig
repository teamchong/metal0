/// Python http.cookiejar module - Cookie handling for HTTP clients
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CookieJar", genConst(".{ .policy = @as(?*anyopaque, null) }") }, .{ "FileCookieJar", genFileCookieJar },
    .{ "MozillaCookieJar", genFileCookieJar }, .{ "LWPCookieJar", genFileCookieJar },
    .{ "Cookie", genConst(".{ .version = @as(i32, 0), .name = \"\", .value = \"\", .port = @as(?[]const u8, null), .port_specified = false, .domain = \"\", .domain_specified = false, .domain_initial_dot = false, .path = \"/\", .path_specified = false, .secure = false, .expires = @as(?i64, null), .discard = true, .comment = @as(?[]const u8, null), .comment_url = @as(?[]const u8, null), .rest = .{}, .rfc2109 = false }") },
    .{ "DefaultCookiePolicy", genConst(".{ .netscape = true, .rfc2965 = false, .rfc2109_as_netscape = @as(?bool, null), .hide_cookie2 = false, .strict_domain = false, .strict_rfc2965_unverifiable = true, .strict_ns_unverifiable = false, .strict_ns_domain = @as(i32, 0), .strict_ns_set_initial_dollar = false, .strict_ns_set_path = false }") },
    .{ "BlockingPolicy", genConst(".{}") }, .{ "BlockAllCookies", genConst(".{}") },
    .{ "DomainStrictNoDots", genConst("@as(i32, 1)") }, .{ "DomainStrictNonDomain", genConst("@as(i32, 2)") },
    .{ "DomainRFC2965Match", genConst("@as(i32, 4)") }, .{ "DomainLiberal", genConst("@as(i32, 0)") }, .{ "DomainStrict", genConst("@as(i32, 3)") },
    .{ "LoadError", genConst("error.LoadError") }, .{ "time2isoz", genConst("\"1970-01-01 00:00:00Z\"") }, .{ "time2netscape", genConst("\"Thu, 01-Jan-1970 00:00:00 GMT\"") },
});

fn genFileCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const filename = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .filename = filename, .delayload = false }; }"); }
    else { try self.emit(".{ .filename = @as(?[]const u8, null), .delayload = false }"); }
}
