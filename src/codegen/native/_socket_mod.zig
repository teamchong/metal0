/// Python _socket module - C accelerator for socket (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _socket.socket(family=AF_INET, type=SOCK_STREAM, proto=0, fileno=None)
pub fn genSocket(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .family = 2, .type = 1, .proto = 0, .fd = -1 }");
}

/// Generate _socket.getaddrinfo(host, port, family=0, type=0, proto=0, flags=0)
pub fn genGetaddrinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .family = 2, .type = 1, .proto = 0, .canonname = \"\", .sockaddr = .{} }){}");
}

/// Generate _socket.getnameinfo(sockaddr, flags)
pub fn genGetnameinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"localhost\", \"0\" }");
}

/// Generate _socket.gethostname()
pub fn genGethostname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"localhost\"");
}

/// Generate _socket.gethostbyname(hostname)
pub fn genGethostbyname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const hostname = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = hostname; break :blk \"127.0.0.1\"; }");
    } else {
        try self.emit("\"127.0.0.1\"");
    }
}

/// Generate _socket.gethostbyname_ex(hostname)
pub fn genGethostbynameEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }");
}

/// Generate _socket.gethostbyaddr(ip_address)
pub fn genGethostbyaddr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"localhost\", &[_][]const u8{}, &[_][]const u8{\"127.0.0.1\"} }");
}

/// Generate _socket.getfqdn(name='')
pub fn genGetfqdn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"localhost\"");
}

/// Generate _socket.getservbyname(servicename, protocolname='tcp')
pub fn genGetservbyname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _socket.getservbyport(port, protocolname='tcp')
pub fn genGetservbyport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _socket.getprotobyname(protocolname)
pub fn genGetprotobyname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _socket.getdefaulttimeout()
pub fn genGetdefaulttimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _socket.setdefaulttimeout(timeout)
pub fn genSetdefaulttimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _socket.ntohs(x)
pub fn genNtohs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u16, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u16, 0)");
    }
}

/// Generate _socket.ntohl(x)
pub fn genNtohl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate _socket.htons(x)
pub fn genHtons(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u16, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u16, 0)");
    }
}

/// Generate _socket.htonl(x)
pub fn genHtonl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@byteSwap(@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate _socket.inet_aton(ip_string)
pub fn genInetAton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{127, 0, 0, 1}");
}

/// Generate _socket.inet_ntoa(packed_ip)
pub fn genInetNtoa(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"127.0.0.1\"");
}

/// Generate _socket.inet_pton(address_family, ip_string)
pub fn genInetPton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{127, 0, 0, 1}");
}

/// Generate _socket.inet_ntop(address_family, packed_ip)
pub fn genInetNtop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"127.0.0.1\"");
}

// Socket constants
pub fn genAF_INET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genAF_INET6(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 30)");
}

pub fn genAF_UNIX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genSOCK_STREAM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genSOCK_DGRAM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genSOCK_RAW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genSOL_SOCKET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 65535)");
}

pub fn genSO_REUSEADDR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genSO_KEEPALIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genIPPROTO_TCP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genIPPROTO_UDP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 17)");
}

// Exceptions
pub fn genSocketError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SocketError");
}

pub fn genSocketTimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SocketTimeout");
}

pub fn genSocketGaierror(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SocketGaierror");
}

pub fn genSocketHerror(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SocketHerror");
}
