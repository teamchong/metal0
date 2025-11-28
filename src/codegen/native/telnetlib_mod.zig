/// Python telnetlib module - Telnet client class
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate telnetlib.Telnet class
pub fn genTelnet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = @as(?[]const u8, null), .port = @as(i32, 23), .timeout = @as(f64, -1.0), .sock = @as(?*anyopaque, null) }");
}

// ============================================================================
// Telnet option constants (RFC 854, 855)
// ============================================================================

pub fn genTHEOPT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 0)");
}

pub fn genSE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 240)"); // End of subnegotiation
}

pub fn genNOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 241)"); // No operation
}

pub fn genDM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 242)"); // Data mark
}

pub fn genBRK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 243)"); // Break
}

pub fn genIP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 244)"); // Interrupt Process
}

pub fn genAO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 245)"); // Abort Output
}

pub fn genAYT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 246)"); // Are You There
}

pub fn genEC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 247)"); // Erase Character
}

pub fn genEL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 248)"); // Erase Line
}

pub fn genGA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 249)"); // Go Ahead
}

pub fn genSB(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 250)"); // Subnegotiation Begin
}

pub fn genWILL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 251)"); // Will
}

pub fn genWONT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 252)"); // Won't
}

pub fn genDO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 253)"); // Do
}

pub fn genDONT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 254)"); // Don't
}

pub fn genIAC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 255)"); // Interpret As Command
}

// ============================================================================
// Telnet option codes (RFC 856-861, etc)
// ============================================================================

pub fn genECHO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 1)"); // Echo
}

pub fn genSGA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 3)"); // Suppress Go Ahead
}

pub fn genTTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 24)"); // Terminal Type
}

pub fn genNAWS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 31)"); // Window Size
}

pub fn genLINEMODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 34)"); // Linemode
}

pub fn genNEW_ENVIRON(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 39)"); // New Environment Option
}

pub fn genXDISPLOC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 35)"); // X Display Location
}

pub fn genAUTHENTICATION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 37)"); // Authentication
}

pub fn genENCRYPT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 38)"); // Encryption Option
}

// ============================================================================
// Port constant
// ============================================================================

pub fn genTELNET_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 23)");
}
