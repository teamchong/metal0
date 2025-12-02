/// Python socket module - Basic TCP/UDP socket operations
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn genByteSwap(comptime pre: []const u8, comptime ty: []const u8, comptime func: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) return;
        try self.emit(pre ++ "std.mem." ++ func ++ "(" ++ ty ++ ", @intCast("); try self.genExpr(args[0]); try self.emit("))))");
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "socket", h.c("blk: { const _sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch break :blk @as(i64, -1); break :blk @as(i64, @intCast(_sock)); }") },
    .{ "create_connection", genCreateConnection },
    .{ "gethostname", h.c("blk: { var _buf: [std.posix.HOST_NAME_MAX]u8 = undefined; const _result = std.posix.gethostname(&_buf); if (_result) |_name| { break :blk __global_allocator.dupe(u8, _name) catch \"\"; } else |_| break :blk \"\"; }") },
    .{ "getfqdn", h.c("blk: { var _buf: [std.posix.HOST_NAME_MAX]u8 = undefined; const _result = std.posix.gethostname(&_buf); if (_result) |_name| { break :blk __global_allocator.dupe(u8, _name) catch \"\"; } else |_| break :blk \"\"; }") },
    .{ "inet_aton", genInetAton }, .{ "inet_ntoa", genInetNtoa },
    .{ "htons", genByteSwap("@as(i64, @intCast(", "u16", "nativeToBig") },
    .{ "htonl", genByteSwap("@as(i64, @intCast(", "u32", "nativeToBig") },
    .{ "ntohs", genByteSwap("@as(i64, @intCast(", "u16", "bigToNative") },
    .{ "ntohl", genByteSwap("@as(i64, @intCast(", "u32", "bigToNative") },
    .{ "setdefaulttimeout", h.c("{}") }, .{ "getdefaulttimeout", h.c("null") },
});

fn genCreateConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _addr_tuple = "); try self.genExpr(args[0]);
    try self.emit("; const _host = _addr_tuple.@\"0\"; const _port = _addr_tuple.@\"1\"; const _sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch break :blk @as(i64, -1); var _addr: std.posix.sockaddr.in = .{ .family = std.posix.AF.INET, .port = std.mem.nativeToBig(u16, @intCast(_port)), .addr = blk2: { if (std.mem.eql(u8, _host, \"localhost\") or std.mem.eql(u8, _host, \"127.0.0.1\")) { break :blk2 .{ .s_addr = std.mem.nativeToBig(u32, 0x7f000001) }; } else { break :blk2 .{ .s_addr = 0 }; } }, .zero = [_]u8{0} ** 8 }; std.posix.connect(_sock, @ptrCast(&_addr), @sizeOf(@TypeOf(_addr))) catch break :blk @as(i64, -1); break :blk @as(i64, @intCast(_sock)); }");
}
fn genInetAton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _ip_str = "); try self.genExpr(args[0]);
    try self.emit("; var _parts: [4]u8 = undefined; var _iter = std.mem.splitScalar(u8, _ip_str, '.'); var _i: usize = 0; while (_iter.next()) |_part| : (_i += 1) { if (_i >= 4) break; _parts[_i] = std.fmt.parseInt(u8, _part, 10) catch 0; } break :blk __global_allocator.dupe(u8, &_parts) catch \"\"; }");
}
fn genInetNtoa(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _packed = "); try self.genExpr(args[0]);
    try self.emit("; if (_packed.len < 4) break :blk \"0.0.0.0\"; var _buf: [16]u8 = undefined; const _len = std.fmt.bufPrint(&_buf, \"{d}.{d}.{d}.{d}\", .{ _packed[0], _packed[1], _packed[2], _packed[3] }) catch break :blk \"0.0.0.0\"; break :blk __global_allocator.dupe(u8, _len) catch \"0.0.0.0\"; }");
}
