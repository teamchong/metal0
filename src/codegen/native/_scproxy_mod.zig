/// Python _scproxy module - macOS system proxy configuration
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _scproxy._get_proxy_settings() - Get system proxy settings
pub fn genGetProxySettings(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .http = null, .https = null, .ftp = null }");
}

/// Generate _scproxy._get_proxies() - Get all proxy URLs
pub fn genGetProxies(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
