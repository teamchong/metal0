/// Python telnetlib module - Telnet client class
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Telnet", genTelnet },
    .{ "TELNET_PORT", genTelnetPort },
    .{ "THEOPT", genTheopt },
    .{ "ECHO", genEcho },
    .{ "SGA", genSga },
    .{ "TTYPE", genTtype },
    .{ "NAWS", genNaws },
    .{ "LINEMODE", genLinemode },
    .{ "XDISPLOC", genXdisploc },
    .{ "AUTHENTICATION", genAuthentication },
    .{ "ENCRYPT", genEncrypt },
    .{ "NEW_ENVIRON", genNewEnviron },
    .{ "SE", genSe },
    .{ "NOP", genNop },
    .{ "DM", genDm },
    .{ "BRK", genBrk },
    .{ "IP", genIp },
    .{ "AO", genAo },
    .{ "AYT", genAyt },
    .{ "EC", genEc },
    .{ "EL", genEl },
    .{ "GA", genGa },
    .{ "SB", genSb },
    .{ "WILL", genWill },
    .{ "WONT", genWont },
    .{ "DO", genDo },
    .{ "DONT", genDont },
    .{ "IAC", genIac },
});

fn genTelnet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = @as(?[]const u8, null), .port = @as(i32, 23), .timeout = @as(f64, -1.0), .sock = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genTelnetPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(23), builder_mod.EmitConfig.forExpression());
}

fn genTheopt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genEcho(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genSga(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genTtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 24)"), builder_mod.EmitConfig.forExpression());
}

fn genNaws(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 31)"), builder_mod.EmitConfig.forExpression());
}

fn genLinemode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 34)"), builder_mod.EmitConfig.forExpression());
}

fn genXdisploc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 35)"), builder_mod.EmitConfig.forExpression());
}

fn genAuthentication(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 37)"), builder_mod.EmitConfig.forExpression());
}

fn genEncrypt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 38)"), builder_mod.EmitConfig.forExpression());
}

fn genNewEnviron(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 39)"), builder_mod.EmitConfig.forExpression());
}

fn genSe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 240)"), builder_mod.EmitConfig.forExpression());
}

fn genNop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 241)"), builder_mod.EmitConfig.forExpression());
}

fn genDm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 242)"), builder_mod.EmitConfig.forExpression());
}

fn genBrk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 243)"), builder_mod.EmitConfig.forExpression());
}

fn genIp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 244)"), builder_mod.EmitConfig.forExpression());
}

fn genAo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 245)"), builder_mod.EmitConfig.forExpression());
}

fn genAyt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 246)"), builder_mod.EmitConfig.forExpression());
}

fn genEc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 247)"), builder_mod.EmitConfig.forExpression());
}

fn genEl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 248)"), builder_mod.EmitConfig.forExpression());
}

fn genGa(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 249)"), builder_mod.EmitConfig.forExpression());
}

fn genSb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 250)"), builder_mod.EmitConfig.forExpression());
}

fn genWill(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 251)"), builder_mod.EmitConfig.forExpression());
}

fn genWont(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 252)"), builder_mod.EmitConfig.forExpression());
}

fn genDo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 253)"), builder_mod.EmitConfig.forExpression());
}

fn genDont(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 254)"), builder_mod.EmitConfig.forExpression());
}

fn genIac(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 255)"), builder_mod.EmitConfig.forExpression());
}
