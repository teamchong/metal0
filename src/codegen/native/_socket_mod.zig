/// Python _socket module - C accelerator for socket (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genLocalhost(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"localhost\""); }
fn genLoopbackStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"127.0.0.1\""); }
fn genLoopbackBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{127, 0, 0, 1}"); }
fn genHostTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }"); }
fn genSocket(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }"); }
fn genGetaddrinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}"); }
fn genGetnameinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"localhost\", \"0\" }"); }
fn genErr(comptime name: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error." ++ name); } }.f;
}
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "socket", genSocket }, .{ "getaddrinfo", genGetaddrinfo }, .{ "getnameinfo", genGetnameinfo },
    .{ "gethostname", genLocalhost }, .{ "getfqdn", genLocalhost }, .{ "gethostbyname", genGethostbyname },
    .{ "gethostbyname_ex", genHostTuple }, .{ "gethostbyaddr", genHostTuple },
    .{ "getservbyname", genI32(0) }, .{ "getprotobyname", genI32(0) },
    .{ "getservbyport", genEmptyStr }, .{ "getdefaulttimeout", genNull }, .{ "setdefaulttimeout", genUnit },
    .{ "ntohs", genNtohs }, .{ "ntohl", genNtohl }, .{ "htons", genNtohs }, .{ "htonl", genNtohl },
    .{ "inet_aton", genLoopbackBytes }, .{ "inet_pton", genLoopbackBytes },
    .{ "inet_ntoa", genLoopbackStr }, .{ "inet_ntop", genLoopbackStr },
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
