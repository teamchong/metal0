/// Python ipaddress module - IPv4/IPv6 manipulation library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ip_address", genIpAddress }, .{ "ip_network", genIpNetwork }, .{ "ip_interface", genIpInterface },
    .{ "IPv4Address", genIPv4Address }, .{ "IPv4Network", genIPv4Network }, .{ "IPv4Interface", genIPv4Interface },
    .{ "IPv6Address", genIPv6Address }, .{ "IPv6Network", genIPv6Network }, .{ "IPv6Interface", genIPv6Interface },
    .{ "v4_int_to_packed", genV4Packed }, .{ "v6_int_to_packed", genV6Packed },
    .{ "summarize_address_range", genEmptyNetList }, .{ "collapse_addresses", genEmptyNetList },
    .{ "get_mixed_type_key", genMixedTypeKey },
    .{ "AddressValueError", genAddrErr }, .{ "NetmaskValueError", genNetmaskErr },
});

fn genV4Packed(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{0, 0, 0, 0}"); }
fn genV6Packed(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{0} ** 16"); }
fn genEmptyNetList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}"); }
fn genMixedTypeKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 4), @as(?*anyopaque, null) }"); }
fn genAddrErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.AddressValueError"); }
fn genNetmaskErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NetmaskValueError"); }
fn genIPv4Network(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .network_address = \"0.0.0.0\", .broadcast_address = \"0.0.0.0\", .netmask = \"0.0.0.0\", .hostmask = \"255.255.255.255\", .prefixlen = @as(i32, 0), .num_addresses = @as(i64, 1), .version = @as(i32, 4) }"); }
fn genIPv4Interface(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }"); }
fn genIPv6Network(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .network_address = \"::\", .broadcast_address = \"::\", .netmask = \"::\", .hostmask = \"::\", .prefixlen = @as(i32, 0), .num_addresses = @as(i128, 1), .version = @as(i32, 6) }"); }
fn genIPv6Interface(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .ip = .{ .address = \"::\" }, .network = .{ .network_address = \"::\", .prefixlen = @as(i32, 0) } }"); }

fn genIpAddress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 4) }; }"); }
    else { try self.emit(".{ .address = \"0.0.0.0\", .version = @as(i32, 4) }"); }
}

fn genIpNetwork(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .network_address = addr, .prefixlen = @as(i32, 24), .version = @as(i32, 4) }; }"); }
    else { try self.emit(".{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0), .version = @as(i32, 4) }"); }
}

fn genIpInterface(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .ip = .{ .address = addr }, .network = .{ .network_address = addr, .prefixlen = @as(i32, 24) } }; }"); }
    else { try self.emit(".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }"); }
}

fn genIPv4Address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }; }"); }
    else { try self.emit(".{ .address = \"0.0.0.0\", .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }"); }
}

fn genIPv6Address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }; }"); }
    else { try self.emit(".{ .address = \"::\", .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }"); }
}
