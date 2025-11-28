/// Python ipaddress module - IPv4/IPv6 manipulation library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate ipaddress.ip_address(address) - factory function
pub fn genIp_address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const addr = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 4) }; }");
    } else {
        try self.emit(".{ .address = \"0.0.0.0\", .version = @as(i32, 4) }");
    }
}

/// Generate ipaddress.ip_network(address, strict=True) - factory function
pub fn genIp_network(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const addr = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .network_address = addr, .prefixlen = @as(i32, 24), .version = @as(i32, 4) }; }");
    } else {
        try self.emit(".{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0), .version = @as(i32, 4) }");
    }
}

/// Generate ipaddress.ip_interface(address) - factory function
pub fn genIp_interface(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const addr = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .ip = .{ .address = addr }, .network = .{ .network_address = addr, .prefixlen = @as(i32, 24) } }; }");
    } else {
        try self.emit(".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }");
    }
}

/// Generate ipaddress.IPv4Address class
pub fn genIPv4Address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const addr = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }; }");
    } else {
        try self.emit(".{ .address = \"0.0.0.0\", .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }");
    }
}

/// Generate ipaddress.IPv4Network class
pub fn genIPv4Network(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .network_address = \"0.0.0.0\", .broadcast_address = \"0.0.0.0\", .netmask = \"0.0.0.0\", .hostmask = \"255.255.255.255\", .prefixlen = @as(i32, 0), .num_addresses = @as(i64, 1), .version = @as(i32, 4) }");
}

/// Generate ipaddress.IPv4Interface class
pub fn genIPv4Interface(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }");
}

/// Generate ipaddress.IPv6Address class
pub fn genIPv6Address(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const addr = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .address = addr, .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }; }");
    } else {
        try self.emit(".{ .address = \"::\", .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }");
    }
}

/// Generate ipaddress.IPv6Network class
pub fn genIPv6Network(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .network_address = \"::\", .broadcast_address = \"::\", .netmask = \"::\", .hostmask = \"::\", .prefixlen = @as(i32, 0), .num_addresses = @as(i128, 1), .version = @as(i32, 6) }");
}

/// Generate ipaddress.IPv6Interface class
pub fn genIPv6Interface(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .ip = .{ .address = \"::\" }, .network = .{ .network_address = \"::\", .prefixlen = @as(i32, 0) } }");
}

/// Generate ipaddress.v4_int_to_packed(address)
pub fn genV4_int_to_packed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{0, 0, 0, 0}");
}

/// Generate ipaddress.v6_int_to_packed(address)
pub fn genV6_int_to_packed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{0} ** 16");
}

/// Generate ipaddress.summarize_address_range(first, last)
pub fn genSummarize_address_range(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}");
}

/// Generate ipaddress.collapse_addresses(addresses)
pub fn genCollapse_addresses(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}");
}

/// Generate ipaddress.get_mixed_type_key(obj)
pub fn genGet_mixed_type_key(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 4), @as(?*anyopaque, null) }");
}

// ============================================================================
// Exception classes
// ============================================================================

pub fn genAddressValueError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.AddressValueError");
}

pub fn genNetmaskValueError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NetmaskValueError");
}
