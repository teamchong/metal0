/// Python http.cookiejar module - Cookie handling for HTTP clients
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

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

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

fn genFileCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitRaw(".{ .filename = @as(?[]const u8, null), .delayload = false }");
        try self.flushBuilder();
        return;
    }
    const filename_val = try self.captureExpr(args[0]);
    try b.withLabeledBlock("__fcj", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
            try bld.emitConstWithValue("filename", "", ctx, "");
            try scope.breakWithRaw(".{ .filename = filename, .delayload = false }");
        }
    }.emit, filename_val);
    try self.flushBuilder();
}
