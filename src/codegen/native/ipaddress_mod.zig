/// Python ipaddress module - IPv4/IPv6 manipulation library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ip_address", genIpAddress }, .{ "ip_network", genIpNetwork }, .{ "ip_interface", genIpInterface },
    .{ "IPv4Address", genIPv4Address }, .{ "IPv4Network", genConst(".{ .network_address = \"0.0.0.0\", .broadcast_address = \"0.0.0.0\", .netmask = \"0.0.0.0\", .hostmask = \"255.255.255.255\", .prefixlen = @as(i32, 0), .num_addresses = @as(i64, 1), .version = @as(i32, 4) }") },
    .{ "IPv4Interface", genConst(".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }") },
    .{ "IPv6Address", genIPv6Address }, .{ "IPv6Network", genConst(".{ .network_address = \"::\", .broadcast_address = \"::\", .netmask = \"::\", .hostmask = \"::\", .prefixlen = @as(i32, 0), .num_addresses = @as(i128, 1), .version = @as(i32, 6) }") },
    .{ "IPv6Interface", genConst(".{ .ip = .{ .address = \"::\" }, .network = .{ .network_address = \"::\", .prefixlen = @as(i32, 0) } }") },
    .{ "v4_int_to_packed", genConst("&[_]u8{0, 0, 0, 0}") }, .{ "v6_int_to_packed", genConst("&[_]u8{0} ** 16") },
    .{ "summarize_address_range", genConst("&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}") },
    .{ "collapse_addresses", genConst("&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}") },
    .{ "get_mixed_type_key", genConst(".{ @as(i32, 4), @as(?*anyopaque, null) }") },
    .{ "AddressValueError", genConst("error.AddressValueError") }, .{ "NetmaskValueError", genConst("error.NetmaskValueError") },
});

fn genIpAddress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 4) }; }"); }
    else try self.emit(".{ .address = \"0.0.0.0\", .version = @as(i32, 4) }");
}

fn genIpNetwork(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .network_address = addr, .prefixlen = @as(i32, 24), .version = @as(i32, 4) }; }"); }
    else try self.emit(".{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0), .version = @as(i32, 4) }");
}

fn genIpInterface(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .ip = .{ .address = addr }, .network = .{ .network_address = addr, .prefixlen = @as(i32, 24) } }; }"); }
    else try self.emit(".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }");
}

fn genIPv4Address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }; }"); }
    else try self.emit(".{ .address = \"0.0.0.0\", .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }");
}

fn genIPv6Address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }; }"); }
    else try self.emit(".{ .address = \"::\", .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }");
}
