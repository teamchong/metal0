/// Python socket module - Basic TCP/UDP socket operations
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Socket creation
    .{ "socket", genSocket },
    .{ "create_connection", genCreateConn },
    // Host resolution
    .{ "gethostname", genGethostname },
    .{ "getfqdn", genGethostname },
    .{ "gethostbyname", h.pass("\"127.0.0.1\"") }, // Simplified - returns IP string
    .{ "gethostbyaddr", h.pass("\"localhost\"") }, // Simplified - returns hostname
    .{ "getservbyname", h.pass("@as(i64, 0)") }, // Returns port number
    .{ "getservbyport", h.pass("\"\"") }, // Returns service name
    .{ "getaddrinfo", h.c("&[_]@TypeOf(.{ .{ .@\"0\" = @as(i64, 2), .@\"1\" = @as(i64, 1), .@\"2\" = @as(i64, 6), .@\"3\" = \"\", .@\"4\" = .{ \"0.0.0.0\", @as(i64, 0) } } }){}") },
    .{ "getnameinfo", h.c(".{ \"localhost\", \"http\" }") },
    // Address conversion
    .{ "inet_aton", genInetAton },
    .{ "inet_ntoa", genInetNtoa },
    .{ "inet_pton", h.pass("\"\"") }, // Packed binary address
    .{ "inet_ntop", h.pass("\"0.0.0.0\"") }, // String address
    // Byte order
    .{ "htons", h.wrap("@as(i64, @intCast(std.mem.nativeToBig(u16, @intCast(", "))))", "0") },
    .{ "htonl", h.wrap("@as(i64, @intCast(std.mem.nativeToBig(u32, @intCast(", "))))", "0") },
    .{ "ntohs", h.wrap("@as(i64, @intCast(std.mem.bigToNative(u16, @intCast(", "))))", "0") },
    .{ "ntohl", h.wrap("@as(i64, @intCast(std.mem.bigToNative(u32, @intCast(", "))))", "0") },
    // Timeout
    .{ "setdefaulttimeout", h.c("{}") },
    .{ "getdefaulttimeout", h.c("null") },
    // Address family constants
    .{ "AF_INET", h.c("@as(i64, 2)") },
    .{ "AF_INET6", h.c("@as(i64, 30)") },
    .{ "AF_UNIX", h.c("@as(i64, 1)") },
    .{ "AF_UNSPEC", h.c("@as(i64, 0)") },
    // Socket type constants
    .{ "SOCK_STREAM", h.c("@as(i64, 1)") },
    .{ "SOCK_DGRAM", h.c("@as(i64, 2)") },
    .{ "SOCK_RAW", h.c("@as(i64, 3)") },
    .{ "SOCK_SEQPACKET", h.c("@as(i64, 5)") },
    // Protocol constants
    .{ "IPPROTO_TCP", h.c("@as(i64, 6)") },
    .{ "IPPROTO_UDP", h.c("@as(i64, 17)") },
    .{ "IPPROTO_IP", h.c("@as(i64, 0)") },
    .{ "IPPROTO_ICMP", h.c("@as(i64, 1)") },
    .{ "IPPROTO_RAW", h.c("@as(i64, 255)") },
    // Socket options
    .{ "SOL_SOCKET", h.c("@as(i64, 0xffff)") },
    .{ "SO_REUSEADDR", h.c("@as(i64, 4)") },
    .{ "SO_REUSEPORT", h.c("@as(i64, 512)") },
    .{ "SO_KEEPALIVE", h.c("@as(i64, 8)") },
    .{ "SO_BROADCAST", h.c("@as(i64, 32)") },
    .{ "SO_LINGER", h.c("@as(i64, 128)") },
    .{ "SO_RCVBUF", h.c("@as(i64, 4098)") },
    .{ "SO_SNDBUF", h.c("@as(i64, 4097)") },
    .{ "SO_RCVTIMEO", h.c("@as(i64, 4102)") },
    .{ "SO_SNDTIMEO", h.c("@as(i64, 4101)") },
    .{ "TCP_NODELAY", h.c("@as(i64, 1)") },
    // Address info flags
    .{ "AI_PASSIVE", h.c("@as(i64, 1)") },
    .{ "AI_CANONNAME", h.c("@as(i64, 2)") },
    .{ "AI_NUMERICHOST", h.c("@as(i64, 4)") },
    .{ "AI_NUMERICSERV", h.c("@as(i64, 4096)") },
    // Shutdown how values
    .{ "SHUT_RD", h.c("@as(i64, 0)") },
    .{ "SHUT_WR", h.c("@as(i64, 1)") },
    .{ "SHUT_RDWR", h.c("@as(i64, 2)") },
    // Special addresses
    .{ "INADDR_ANY", h.c("@as(i64, 0)") },
    .{ "INADDR_BROADCAST", h.c("@as(i64, 0xffffffff)") },
    .{ "INADDR_LOOPBACK", h.c("@as(i64, 0x7f000001)") },
    // Error constants
    .{ "error", h.c("error.SocketError") },
    .{ "timeout", h.c("error.TimeoutError") },
    .{ "herror", h.c("error.HostError") },
    .{ "gaierror", h.c("error.AddressInfoError") },
    // MSG flags
    .{ "MSG_PEEK", h.c("@as(i64, 2)") },
    .{ "MSG_OOB", h.c("@as(i64, 1)") },
    .{ "MSG_WAITALL", h.c("@as(i64, 64)") },
    .{ "MSG_DONTWAIT", h.c("@as(i64, 128)") },
    // Has functions for feature detection
    .{ "has_ipv6", h.c("true") },
    .{ "has_dualstack_ipv6", h.c("@TypeOf(true)") },
});

fn genSocket(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("sock");
    try self.emitFmt("const _sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch break :{s} @as(i64, -1); break :{s} @as(i64, @intCast(_sock)); ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genCreateConn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) { try self.emit("@as(i64, -1)"); return; }
    const label = try self.emitInlineBlockStart("conn");
    const addr_label = try b.freshInlineLabel("addr");
    try self.emit("const _addr_tuple = "); try self.genExpr(args[0]);
    try self.emitFmt("; const _host = _addr_tuple.@\"0\"; const _port = _addr_tuple.@\"1\"; const _sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch break :{s} @as(i64, -1); var _addr: std.posix.sockaddr.in = .{{ .family = std.posix.AF.INET, .port = std.mem.nativeToBig(u16, @intCast(_port)), .addr = {s}: {{ if (std.mem.eql(u8, _host, \"localhost\") or std.mem.eql(u8, _host, \"127.0.0.1\")) {{ break :{s} .{{ .s_addr = std.mem.nativeToBig(u32, 0x7f000001) }}; }} else {{ break :{s} .{{ .s_addr = 0 }}; }} }}, .zero = [_]u8{{0}} ** 8 }}; std.posix.connect(_sock, @ptrCast(&_addr), @sizeOf(@TypeOf(_addr))) catch break :{s} @as(i64, -1); break :{s} @as(i64, @intCast(_sock)); ", .{ label, addr_label, addr_label, addr_label, label, label });
    try self.emitInlineBlockEnd();
}

fn genGethostname(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("ghn");
    try self.emitFmt("var _buf: [std.posix.HOST_NAME_MAX]u8 = undefined; const _result = std.posix.gethostname(&_buf); if (_result) |_name| {{ break :{s} __global_allocator.dupe(u8, _name) catch \"\"; }} else |_| break :{s} \"\"; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genInetAton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const label = try self.emitInlineBlockStart("aton");
    try self.emit("const _ip_str = "); try self.genExpr(args[0]);
    try self.emitFmt("; var _parts: [4]u8 = undefined; var _iter = std.mem.splitScalar(u8, _ip_str, '.'); var _i: usize = 0; while (_iter.next()) |_part| : (_i += 1) {{ if (_i >= 4) break; _parts[_i] = std.fmt.parseInt(u8, _part, 10) catch 0; }} break :{s} __global_allocator.dupe(u8, &_parts) catch \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genInetNtoa(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"0.0.0.0\""); return; }
    const label = try self.emitInlineBlockStart("ntoa");
    try self.emit("const _packed = "); try self.genExpr(args[0]);
    try self.emitFmt("; if (_packed.len < 4) break :{s} \"0.0.0.0\"; var _buf: [16]u8 = undefined; const _len = std.fmt.bufPrint(&_buf, \"{{d}}.{{d}}.{{d}}.{{d}}\", .{{ _packed[0], _packed[1], _packed[2], _packed[3] }}) catch break :{s} \"0.0.0.0\"; break :{s} __global_allocator.dupe(u8, _len) catch \"0.0.0.0\"; ", .{ label, label, label });
    try self.emitInlineBlockEnd();
}
