/// Python http.cookiejar module - Cookie handling for HTTP clients
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate http.cookiejar.CookieJar class
pub fn genCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .policy = @as(?*anyopaque, null) }");
}

/// Generate http.cookiejar.FileCookieJar class
pub fn genFileCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const filename = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .filename = filename, .delayload = false }; }");
    } else {
        try self.emit(".{ .filename = @as(?[]const u8, null), .delayload = false }");
    }
}

/// Generate http.cookiejar.MozillaCookieJar class
pub fn genMozillaCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const filename = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .filename = filename, .delayload = false }; }");
    } else {
        try self.emit(".{ .filename = @as(?[]const u8, null), .delayload = false }");
    }
}

/// Generate http.cookiejar.LWPCookieJar class
pub fn genLWPCookieJar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const filename = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .filename = filename, .delayload = false }; }");
    } else {
        try self.emit(".{ .filename = @as(?[]const u8, null), .delayload = false }");
    }
}

/// Generate http.cookiejar.Cookie class
pub fn genCookie(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .version = @as(i32, 0), .name = \"\", .value = \"\", .port = @as(?[]const u8, null), .port_specified = false, .domain = \"\", .domain_specified = false, .domain_initial_dot = false, .path = \"/\", .path_specified = false, .secure = false, .expires = @as(?i64, null), .discard = true, .comment = @as(?[]const u8, null), .comment_url = @as(?[]const u8, null), .rest = .{}, .rfc2109 = false }");
}

/// Generate http.cookiejar.DefaultCookiePolicy class
pub fn genDefaultCookiePolicy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .netscape = true, .rfc2965 = false, .rfc2109_as_netscape = @as(?bool, null), .hide_cookie2 = false, .strict_domain = false, .strict_rfc2965_unverifiable = true, .strict_ns_unverifiable = false, .strict_ns_domain = @as(i32, 0), .strict_ns_set_initial_dollar = false, .strict_ns_set_path = false }");
}

/// Generate http.cookiejar.BlockingPolicy class (blocks all cookies)
pub fn genBlockingPolicy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate http.cookiejar.BlockAllCookies alias
pub fn genBlockAllCookies(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// Policy flags
// ============================================================================

pub fn genDomainStrictNoDots(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genDomainStrictNonDomain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genDomainRFC2965Match(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genDomainLiberal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genDomainStrict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genLoadError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.LoadError");
}

// ============================================================================
// Utility functions
// ============================================================================

/// Generate http.cookiejar.time2isoz(t=None)
pub fn genTime2isoz(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"1970-01-01 00:00:00Z\"");
}

/// Generate http.cookiejar.time2netscape(t=None)
pub fn genTime2netscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Thu, 01-Jan-1970 00:00:00 GMT\"");
}
