/// Python _socket module - C accelerator for socket (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler {
    return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n}));
}
fn genErr(comptime name: []const u8) ModuleHandler { return genConst("error." ++ name); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "socket", genConst(".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }") }, .{ "getaddrinfo", genConst("&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}") }, .{ "getnameinfo", genConst(".{ \"localhost\", \"0\" }") },
    .{ "gethostname", genConst("\"localhost\"") }, .{ "getfqdn", genConst("\"localhost\"") }, .{ "gethostbyname", genGethostbyname },
    .{ "gethostbyname_ex", genConst(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }") }, .{ "gethostbyaddr", genConst(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }") },
    .{ "getservbyname", genI32(0) }, .{ "getprotobyname", genI32(0) },
    .{ "getservbyport", genConst("\"\"") }, .{ "getdefaulttimeout", genConst("null") }, .{ "setdefaulttimeout", genConst("{}") },
    .{ "ntohs", genNtohs }, .{ "ntohl", genNtohl }, .{ "htons", genNtohs }, .{ "htonl", genNtohl },
    .{ "inet_aton", genConst("&[_]u8{127, 0, 0, 1}") }, .{ "inet_pton", genConst("&[_]u8{127, 0, 0, 1}") },
    .{ "inet_ntoa", genConst("\"127.0.0.1\"") }, .{ "inet_ntop", genConst("\"127.0.0.1\"") },
    .{ "AF_INET", genI32(2) }, .{ "AF_INET6", genI32(30) }, .{ "AF_UNIX", genI32(1) },
    .{ "SOCK_STREAM", genI32(1) }, .{ "SOCK_DGRAM", genI32(2) }, .{ "SOCK_RAW", genI32(3) },
    .{ "SOL_SOCKET", genI32(65535) }, .{ "SO_REUSEADDR", genI32(4) }, .{ "SO_KEEPALIVE", genI32(8) },
    .{ "IPPROTO_TCP", genI32(6) }, .{ "IPPROTO_UDP", genI32(17) },
    .{ "error", genErr("SocketError") }, .{ "timeout", genErr("SocketTimeout") },
    .{ "gaierror", genErr("SocketGaierror") }, .{ "herror", genErr("SocketHerror") },
});

fn genNtohs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@byteSwap(@as(u16, @intCast("); try self.genExpr(args[0]); try self.emit(")))"); }
    else try self.emit("@as(u16, 0)");
}
fn genNtohl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@byteSwap(@as(u32, @intCast("); try self.genExpr(args[0]); try self.emit(")))"); }
    else try self.emit("@as(u32, 0)");
}
fn genGethostbyname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const hostname = "); try self.genExpr(args[0]); try self.emit("; _ = hostname; break :blk \"127.0.0.1\"; }"); }
    else try self.emit("\"127.0.0.1\"");
}
