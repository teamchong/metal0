/// Python _socket module - C accelerator for socket (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

const genNtohs = h.wrap("@byteSwap(@as(u16, @intCast(", ")))", "@as(u16, 0)");
const genNtohl = h.wrap("@byteSwap(@as(u32, @intCast(", ")))", "@as(u32, 0)");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "socket", h.c(".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }") }, .{ "getaddrinfo", h.c("&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}") }, .{ "getnameinfo", h.c(".{ \"localhost\", \"0\" }") },
    .{ "gethostname", h.c("\"localhost\"") }, .{ "getfqdn", h.c("\"localhost\"") },
    .{ "gethostbyname", h.wrap("blk: { const hostname = ", "; _ = hostname; break :blk \"127.0.0.1\"; }", "\"127.0.0.1\"") },
    .{ "gethostbyname_ex", h.c(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }") }, .{ "gethostbyaddr", h.c(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }") },
    .{ "getservbyname", h.I32(0) }, .{ "getprotobyname", h.I32(0) },
    .{ "getservbyport", h.c("\"\"") }, .{ "getdefaulttimeout", h.c("null") }, .{ "setdefaulttimeout", h.c("{}") },
    .{ "ntohs", genNtohs }, .{ "ntohl", genNtohl }, .{ "htons", genNtohs }, .{ "htonl", genNtohl },
    .{ "inet_aton", h.c("&[_]u8{127, 0, 0, 1}") }, .{ "inet_pton", h.c("&[_]u8{127, 0, 0, 1}") },
    .{ "inet_ntoa", h.c("\"127.0.0.1\"") }, .{ "inet_ntop", h.c("\"127.0.0.1\"") },
    .{ "AF_INET", h.I32(2) }, .{ "AF_INET6", h.I32(30) }, .{ "AF_UNIX", h.I32(1) },
    .{ "SOCK_STREAM", h.I32(1) }, .{ "SOCK_DGRAM", h.I32(2) }, .{ "SOCK_RAW", h.I32(3) },
    .{ "SOL_SOCKET", h.I32(65535) }, .{ "SO_REUSEADDR", h.I32(4) }, .{ "SO_KEEPALIVE", h.I32(8) },
    .{ "IPPROTO_TCP", h.I32(6) }, .{ "IPPROTO_UDP", h.I32(17) },
    .{ "error", h.err("SocketError") }, .{ "timeout", h.err("SocketTimeout") },
    .{ "gaierror", h.err("SocketGaierror") }, .{ "herror", h.err("SocketHerror") },
});
