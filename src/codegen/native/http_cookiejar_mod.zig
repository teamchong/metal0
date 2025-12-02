/// Python http.cookiejar module - Cookie handling for HTTP clients
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CookieJar", genCookieJar }, .{ "FileCookieJar", genFileCookieJar },
    .{ "MozillaCookieJar", genFileCookieJar }, .{ "LWPCookieJar", genFileCookieJar },
    .{ "Cookie", genCookie }, .{ "DefaultCookiePolicy", genDefaultCookiePolicy },
    .{ "BlockingPolicy", genEmpty }, .{ "BlockAllCookies", genEmpty },
    .{ "DomainStrictNoDots", genI32(1) }, .{ "DomainStrictNonDomain", genI32(2) },
    .{ "DomainRFC2965Match", genI32(4) }, .{ "DomainLiberal", genI32(0) }, .{ "DomainStrict", genI32(3) },
    .{ "LoadError", genLoadError }, .{ "time2isoz", genTime2isoz }, .{ "time2netscape", genTime2netscape },
});

fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .policy = @as(?*anyopaque, null) }"); }
fn genFileCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const filename = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .filename = filename, .delayload = false }; }"); }
    else { try self.emit(".{ .filename = @as(?[]const u8, null), .delayload = false }"); }
}
fn genCookie(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .version = @as(i32, 0), .name = \"\", .value = \"\", .port = @as(?[]const u8, null), .port_specified = false, .domain = \"\", .domain_specified = false, .domain_initial_dot = false, .path = \"/\", .path_specified = false, .secure = false, .expires = @as(?i64, null), .discard = true, .comment = @as(?[]const u8, null), .comment_url = @as(?[]const u8, null), .rest = .{}, .rfc2109 = false }"); }
fn genDefaultCookiePolicy(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .netscape = true, .rfc2965 = false, .rfc2109_as_netscape = @as(?bool, null), .hide_cookie2 = false, .strict_domain = false, .strict_rfc2965_unverifiable = true, .strict_ns_unverifiable = false, .strict_ns_domain = @as(i32, 0), .strict_ns_set_initial_dollar = false, .strict_ns_set_path = false }"); }
fn genLoadError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.LoadError"); }
fn genTime2isoz(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"1970-01-01 00:00:00Z\""); }
fn genTime2netscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Thu, 01-Jan-1970 00:00:00 GMT\""); }
