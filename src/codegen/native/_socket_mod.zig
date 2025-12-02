/// Python _socket module - C accelerator for socket (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "socket", genSocket }, .{ "getaddrinfo", genGetaddrinfo }, .{ "getnameinfo", genGetnameinfo },
    .{ "gethostname", genLocalhost }, .{ "getfqdn", genLocalhost }, .{ "gethostbyname", genGethostbyname },
    .{ "gethostbyname_ex", genHostTuple }, .{ "gethostbyaddr", genHostTuple },
    .{ "getservbyname", genI32_0 }, .{ "getprotobyname", genI32_0 },
    .{ "getservbyport", genEmptyStr }, .{ "getdefaulttimeout", genNull }, .{ "setdefaulttimeout", genUnit },
    .{ "ntohs", genNtohs }, .{ "ntohl", genNtohl }, .{ "htons", genNtohs }, .{ "htonl", genNtohl },
    .{ "inet_aton", genLoopbackBytes }, .{ "inet_pton", genLoopbackBytes },
    .{ "inet_ntoa", genLoopbackStr }, .{ "inet_ntop", genLoopbackStr },
    .{ "AF_INET", genI32_2 }, .{ "AF_INET6", genI32_30 }, .{ "AF_UNIX", genI32_1 },
    .{ "SOCK_STREAM", genI32_1 }, .{ "SOCK_DGRAM", genI32_2 }, .{ "SOCK_RAW", genI32_3 },
    .{ "SOL_SOCKET", genSOL_SOCKET }, .{ "SO_REUSEADDR", genI32_4 }, .{ "SO_KEEPALIVE", genI32_8 },
    .{ "IPPROTO_TCP", genI32_6 }, .{ "IPPROTO_UDP", genI32_17 },
    .{ "error", genSocketError }, .{ "timeout", genSocketTimeout },
    .{ "gaierror", genSocketGaierror }, .{ "herror", genSocketHerror },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genLocalhost(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"localhost\""); }
fn genLoopbackStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"127.0.0.1\""); }
fn genLoopbackBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{127, 0, 0, 1}"); }
fn genHostTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }"); }

// Integer constants
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_17(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 17)"); }
fn genI32_30(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 30)"); }
fn genSOL_SOCKET(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 65535)"); }

// Socket types
fn genSocket(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }"); }
fn genGetaddrinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}"); }
fn genGetnameinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"localhost\", \"0\" }"); }

// Exceptions
fn genSocketError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SocketError"); }
fn genSocketTimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SocketTimeout"); }
fn genSocketGaierror(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SocketGaierror"); }
fn genSocketHerror(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SocketHerror"); }

// Byte swap helpers
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
