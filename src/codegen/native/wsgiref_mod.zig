/// Python wsgiref module - WSGI utilities and reference implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "validator", h.pass("@as(?*anyopaque, null)") },
    .{ "assert_", h.c("{}") }, .{ "check_status", h.c("{}") }, .{ "check_headers", h.c("{}") },
    .{ "check_content_type", h.c("{}") }, .{ "check_exc_info", h.c("{}") }, .{ "check_environ", h.c("{}") },
    .{ "WSGIWarning", h.err("WSGIWarning") },
    .{ "make_server", h.c(".{ .server_address = .{ \"\", @as(i32, 8000) } }") },
    .{ "WSGIServer", h.c(".{ .server_address = .{ \"\", @as(i32, 8000) }, .application = @as(?*anyopaque, null) }") },
    .{ "WSGIRequestHandler", h.c(".{}") },
    .{ "demo_app", h.c("&[_][]const u8{\"Hello world!\"}") },
    .{ "setup_testing_defaults", h.c("{}") },
    .{ "request_uri", h.c("\"/\"") }, .{ "application_uri", h.c("\"http://localhost/\"") },
    .{ "shift_path_info", h.c("@as(?[]const u8, null)") },
    .{ "FileWrapper", h.c(".{ .filelike = @as(?*anyopaque, null), .blksize = @as(i32, 8192) }") },
    .{ "Headers", h.c(".{ .headers = &[_].{ []const u8, []const u8 }{} }") },
    .{ "BaseHandler", h.c(".{ .wsgi_multithread = true, .wsgi_multiprocess = true, .wsgi_run_once = false }") },
    .{ "SimpleHandler", h.c(".{ .stdin = @as(?*anyopaque, null), .stdout = @as(?*anyopaque, null), .stderr = @as(?*anyopaque, null), .environ = .{} }") },
    .{ "BaseCGIHandler", h.c(".{ .stdin = @as(?*anyopaque, null), .stdout = @as(?*anyopaque, null), .stderr = @as(?*anyopaque, null), .environ = .{} }") },
    .{ "CGIHandler", h.c(".{}") }, .{ "IISCGIHandler", h.c(".{}") },
});
