/// Python _socket module - C accelerator for socket (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
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

fn genSocket(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }"), builder_mod.EmitConfig.forExpression());
}

fn genGetaddrinfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}"), builder_mod.EmitConfig.forExpression());
}

fn genGetnameinfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"localhost\", \"0\" }"), builder_mod.EmitConfig.forExpression());
}

fn genGethostname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("localhost"), builder_mod.EmitConfig.forExpression());
}

fn genGetfqdn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("localhost"), builder_mod.EmitConfig.forExpression());
}

fn genGethostbyname(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_ghn: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v; break :__m");
        try self.emitFmt("{d}_ghn \"127.0.0.1\"; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.string("127.0.0.1"), builder_mod.EmitConfig.forExpression());
    }
}

fn genGethostbynameEx(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }"), builder_mod.EmitConfig.forExpression());
}

fn genGethostbyaddr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }"), builder_mod.EmitConfig.forExpression());
}

fn genGetservbyname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genGetprotobyname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genGetservbyport(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genGetdefaulttimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genSetdefaulttimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genNtohs(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u16, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genNtohl(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genHtons(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u16, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genHtonl(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genInetAton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{127, 0, 0, 1}"), builder_mod.EmitConfig.forExpression());
}

fn genInetPton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{127, 0, 0, 1}"), builder_mod.EmitConfig.forExpression());
}

fn genInetNtoa(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("127.0.0.1"), builder_mod.EmitConfig.forExpression());
}

fn genInetNtop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("127.0.0.1"), builder_mod.EmitConfig.forExpression());
}

fn genAfInet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genAfInet6(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 30)"), builder_mod.EmitConfig.forExpression());
}

fn genAfUnix(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genSockStream(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genSockDgram(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genSockRaw(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genSolSocket(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 65535)"), builder_mod.EmitConfig.forExpression());
}

fn genSoReuseaddr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genSoKeepalive(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 8)"), builder_mod.EmitConfig.forExpression());
}

fn genIpprotoTcp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn genIpprotoUdp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 17)"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SocketError"), builder_mod.EmitConfig.forExpression());
}

fn genTimeout(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SocketTimeout"), builder_mod.EmitConfig.forExpression());
}

fn genGaierror(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SocketGaierror"), builder_mod.EmitConfig.forExpression());
}

fn genHerror(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SocketHerror"), builder_mod.EmitConfig.forExpression());
}
