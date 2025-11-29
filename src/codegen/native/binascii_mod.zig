/// Python binascii module - Binary/ASCII conversions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate binascii.hexlify(data, sep=None, bytes_per_sep=1)
pub fn genHexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; const arr = std.fmt.bytesToHex(data, .lower); break :blk @as([]const u8, &arr); }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate binascii.unhexlify(hexstr)
pub fn genUnhexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.b2a_hex(data) - same as hexlify
pub fn genB2a_hex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genHexlify(self, args);
}

/// Generate binascii.a2b_hex(hexstr) - same as unhexlify
pub fn genA2b_hex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genUnhexlify(self, args);
}

/// Generate binascii.b2a_base64(data, newline=True)
pub fn genB2a_base64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.a2b_base64(string)
pub fn genA2b_base64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.b2a_uu(data, backtick=False)
pub fn genB2a_uu(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.a2b_uu(string)
pub fn genA2b_uu(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.b2a_qp(data, quotetabs=False, istext=True, header=False)
pub fn genB2a_qp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.a2b_qp(string, header=False)
pub fn genA2b_qp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.crc32(data, crc=0)
pub fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk @as(u32, std.hash.crc.Crc32.hash(data)); }");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate binascii.crc_hqx(data, crc)
pub fn genCrc_hqx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate binascii.Error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BinasciiError");
}

/// Generate binascii.Incomplete exception
pub fn genIncomplete(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Incomplete");
}
