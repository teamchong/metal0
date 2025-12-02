/// Python telnetlib module - Telnet client class
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Telnet", genTelnet }, .{ "TELNET_PORT", genTelnetPort },
    .{ "THEOPT", genU8_0 }, .{ "ECHO", genU8_1 }, .{ "SGA", genU8_3 }, .{ "TTYPE", genU8_24 },
    .{ "NAWS", genU8_31 }, .{ "LINEMODE", genU8_34 }, .{ "XDISPLOC", genU8_35 },
    .{ "AUTHENTICATION", genU8_37 }, .{ "ENCRYPT", genU8_38 }, .{ "NEW_ENVIRON", genU8_39 },
    .{ "SE", genU8_240 }, .{ "NOP", genU8_241 }, .{ "DM", genU8_242 }, .{ "BRK", genU8_243 },
    .{ "IP", genU8_244 }, .{ "AO", genU8_245 }, .{ "AYT", genU8_246 }, .{ "EC", genU8_247 },
    .{ "EL", genU8_248 }, .{ "GA", genU8_249 }, .{ "SB", genU8_250 }, .{ "WILL", genU8_251 },
    .{ "WONT", genU8_252 }, .{ "DO", genU8_253 }, .{ "DONT", genU8_254 }, .{ "IAC", genU8_255 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genTelnet(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = @as(?[]const u8, null), .port = @as(i32, 23), .timeout = @as(f64, -1.0), .sock = @as(?*anyopaque, null) }"); }
fn genTelnetPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 23)"); }
fn genU8_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 0)"); }
fn genU8_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 1)"); }
fn genU8_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 3)"); }
fn genU8_24(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 24)"); }
fn genU8_31(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 31)"); }
fn genU8_34(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 34)"); }
fn genU8_35(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 35)"); }
fn genU8_37(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 37)"); }
fn genU8_38(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 38)"); }
fn genU8_39(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 39)"); }
fn genU8_240(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 240)"); }
fn genU8_241(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 241)"); }
fn genU8_242(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 242)"); }
fn genU8_243(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 243)"); }
fn genU8_244(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 244)"); }
fn genU8_245(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 245)"); }
fn genU8_246(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 246)"); }
fn genU8_247(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 247)"); }
fn genU8_248(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 248)"); }
fn genU8_249(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 249)"); }
fn genU8_250(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 250)"); }
fn genU8_251(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 251)"); }
fn genU8_252(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 252)"); }
fn genU8_253(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 253)"); }
fn genU8_254(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 254)"); }
fn genU8_255(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 255)"); }
