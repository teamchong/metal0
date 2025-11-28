/// Python socket module - Basic TCP/UDP socket operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate socket.socket(family, type) -> socket object
/// Creates a new socket (returns file descriptor as integer)
pub fn genSocket(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Create TCP socket by default (AF_INET, SOCK_STREAM)
    try self.emit("socket_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch break :socket_blk @as(i64, -1);\n");
    try self.emitIndent();
    try self.emit("break :socket_blk @as(i64, @intCast(_sock));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate socket.create_connection((host, port)) -> socket
/// High-level function to create a connected TCP socket
pub fn genCreateConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("conn_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _addr_tuple = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _host = _addr_tuple.@\"0\";\n");
    try self.emitIndent();
    try self.emit("const _port = _addr_tuple.@\"1\";\n");
    try self.emitIndent();
    try self.emit("const _sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch break :conn_blk @as(i64, -1);\n");
    try self.emitIndent();
    // Resolve hostname - for simplicity assume numeric IP or localhost
    try self.emit("var _addr: std.posix.sockaddr.in = .{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".family = std.posix.AF.INET,\n");
    try self.emitIndent();
    try self.emit(".port = std.mem.nativeToBig(u16, @intCast(_port)),\n");
    try self.emitIndent();
    try self.emit(".addr = blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (std.mem.eql(u8, _host, \"localhost\") or std.mem.eql(u8, _host, \"127.0.0.1\")) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :blk .{ .s_addr = std.mem.nativeToBig(u32, 0x7f000001) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :blk .{ .s_addr = 0 }; // Would need DNS resolution\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("},\n");
    try self.emitIndent();
    try self.emit(".zero = [_]u8{0} ** 8,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    try self.emitIndent();
    try self.emit("std.posix.connect(_sock, @ptrCast(&_addr), @sizeOf(@TypeOf(_addr))) catch break :conn_blk @as(i64, -1);\n");
    try self.emitIndent();
    try self.emit("break :conn_blk @as(i64, @intCast(_sock));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate socket.gethostname() -> str
pub fn genGethostname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hostname_blk: {\n");
    self.indent();
    try self.emitIndent();
    // Use HOST_NAME_MAX (72 on macOS, 64 on Linux)
    try self.emit("var _buf: [std.posix.HOST_NAME_MAX]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _result = std.posix.gethostname(&_buf);\n");
    try self.emitIndent();
    try self.emit("if (_result) |_name| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :hostname_blk __global_allocator.dupe(u8, _name) catch \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else |_| break :hostname_blk \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate socket.getfqdn() -> str (returns hostname for simplicity)
pub fn genGetfqdn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genGethostname(self, args);
}

/// Generate socket.inet_aton(ip_string) -> packed bytes
pub fn genInetAton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("inet_aton_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _ip_str = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _parts: [4]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("var _iter = std.mem.splitScalar(u8, _ip_str, '.');\n");
    try self.emitIndent();
    try self.emit("var _i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_iter.next()) |_part| : (_i += 1) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_i >= 4) break;\n");
    try self.emitIndent();
    try self.emit("_parts[_i] = std.fmt.parseInt(u8, _part, 10) catch 0;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :inet_aton_blk __global_allocator.dupe(u8, &_parts) catch \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate socket.inet_ntoa(packed_bytes) -> ip_string
pub fn genInetNtoa(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("inet_ntoa_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _packed = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_packed.len < 4) break :inet_ntoa_blk \"0.0.0.0\";\n");
    try self.emitIndent();
    try self.emit("var _buf: [16]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _len = std.fmt.bufPrint(&_buf, \"{d}.{d}.{d}.{d}\", .{ _packed[0], _packed[1], _packed[2], _packed[3] }) catch break :inet_ntoa_blk \"0.0.0.0\";\n");
    try self.emitIndent();
    try self.emit("break :inet_ntoa_blk __global_allocator.dupe(u8, _len) catch \"0.0.0.0\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate socket.htons(x) -> network byte order short
pub fn genHtons(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("@as(i64, @intCast(std.mem.nativeToBig(u16, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate socket.htonl(x) -> network byte order long
pub fn genHtonl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("@as(i64, @intCast(std.mem.nativeToBig(u32, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate socket.ntohs(x) -> host byte order short
pub fn genNtohs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("@as(i64, @intCast(std.mem.bigToNative(u16, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate socket.ntohl(x) -> host byte order long
pub fn genNtohl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("@as(i64, @intCast(std.mem.bigToNative(u32, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate socket.setdefaulttimeout(timeout) -> None
pub fn genSetdefaulttimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // No-op for now - would need to track global timeout
    try self.emit("{}");
}

/// Generate socket.getdefaulttimeout() -> float or None
pub fn genGetdefaulttimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}
