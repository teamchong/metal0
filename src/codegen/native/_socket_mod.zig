/// Python _socket module - C accelerator for socket (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "socket", genSocket },
    .{ "getaddrinfo", genGetaddrinfo },
    .{ "getnameinfo", genGetnameinfo },
    .{ "gethostname", genGethostname },
    .{ "getfqdn", genGetfqdn },
    .{ "gethostbyname", genGethostbyname },
    .{ "gethostbyname_ex", genGethostbynameEx },
    .{ "gethostbyaddr", genGethostbyaddr },
    .{ "getservbyname", genGetservbyname },
    .{ "getprotobyname", genGetprotobyname },
    .{ "getservbyport", genGetservbyport },
    .{ "getdefaulttimeout", genGetdefaulttimeout },
    .{ "setdefaulttimeout", genSetdefaulttimeout },
    .{ "ntohs", genNtohs },
    .{ "ntohl", genNtohl },
    .{ "htons", genHtons },
    .{ "htonl", genHtonl },
    .{ "inet_aton", genInetAton },
    .{ "inet_pton", genInetPton },
    .{ "inet_ntoa", genInetNtoa },
    .{ "inet_ntop", genInetNtop },
    .{ "AF_INET", genAfInet },
    .{ "AF_INET6", genAfInet6 },
    .{ "AF_UNIX", genAfUnix },
    .{ "SOCK_STREAM", genSockStream },
    .{ "SOCK_DGRAM", genSockDgram },
    .{ "SOCK_RAW", genSockRaw },
    .{ "SOL_SOCKET", genSolSocket },
    .{ "SO_REUSEADDR", genSoReuseaddr },
    .{ "SO_KEEPALIVE", genSoKeepalive },
    .{ "IPPROTO_TCP", genIpprotoTcp },
    .{ "IPPROTO_UDP", genIpprotoUdp },
    .{ "error", genError },
    .{ "timeout", genTimeout },
    .{ "gaierror", genGaierror },
    .{ "herror", genHerror },
});

const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn genSocket(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }");
}

fn genGetaddrinfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}");
}

fn genGetnameinfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ \"localhost\", \"0\" }");
}

fn genGethostname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"localhost\"");
}

fn genGetfqdn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"localhost\"");
}

fn genGethostbyname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ghn", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; _ = __v; break :{s} \"127.0.0.1\"", .{label});
            }
        }.emit);
    } else {
        try self.emit("\"127.0.0.1\"");
    }
}

fn genGethostbynameEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }");
}

fn genGethostbyaddr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }");
}

fn genGetservbyname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 0)");
}

fn genGetprotobyname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 0)");
}

fn genGetservbyport(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"\"");
}

fn genGetdefaulttimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genSetdefaulttimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("{}");
}

fn genNtohs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u16, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u16, 0)");
    }
}

fn genNtohl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

fn genHtons(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u16, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u16, 0)");
    }
}

fn genHtonl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

fn genInetAton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_]u8{127, 0, 0, 1}");
}

fn genInetPton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_]u8{127, 0, 0, 1}");
}

fn genInetNtoa(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"127.0.0.1\"");
}

fn genInetNtop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"127.0.0.1\"");
}

fn genAfInet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 2)");
}

fn genAfInet6(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 30)");
}

fn genAfUnix(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 1)");
}

fn genSockStream(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 1)");
}

fn genSockDgram(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 2)");
}

fn genSockRaw(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 3)");
}

fn genSolSocket(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 65535)");
}

fn genSoReuseaddr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genSoKeepalive(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 8)");
}

fn genIpprotoTcp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 6)");
}

fn genIpprotoUdp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 17)");
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("error.SocketError");
}

fn genTimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("error.SocketTimeout");
}

fn genGaierror(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("error.SocketGaierror");
}

fn genHerror(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("error.SocketHerror");
}
