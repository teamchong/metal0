/// Python _scproxy module - macOS system proxy configuration
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_proxy_settings", h.c(".{ .http = null, .https = null, .ftp = null }") },
    .{ "get_proxies", h.c(".{}") },
});
