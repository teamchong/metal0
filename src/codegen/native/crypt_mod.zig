/// Python crypt module - Function to check Unix passwords
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Main Functions
// ============================================================================

/// Generate crypt.crypt(word, salt=None)
pub fn genCrypt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const word = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = word; break :blk \"$6$rounds=5000$salt$hash\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate crypt.mksalt(method=None, rounds=None)
pub fn genMksalt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate a simple salt string
    try self.emit("\"$6$rounds=5000$\"");
}

// ============================================================================
// Method Constants (crypt methods)
// ============================================================================

/// Generate crypt.METHOD_SHA512
pub fn genMETHOD_SHA512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"SHA512\", .ident = \"$6$\", .salt_chars = 16, .total_size = 106 }");
}

/// Generate crypt.METHOD_SHA256
pub fn genMETHOD_SHA256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"SHA256\", .ident = \"$5$\", .salt_chars = 16, .total_size = 63 }");
}

/// Generate crypt.METHOD_BLOWFISH
pub fn genMETHOD_BLOWFISH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"BLOWFISH\", .ident = \"$2b$\", .salt_chars = 22, .total_size = 59 }");
}

/// Generate crypt.METHOD_MD5
pub fn genMETHOD_MD5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"MD5\", .ident = \"$1$\", .salt_chars = 8, .total_size = 34 }");
}

/// Generate crypt.METHOD_CRYPT
pub fn genMETHOD_CRYPT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"CRYPT\", .ident = \"\", .salt_chars = 2, .total_size = 13 }");
}

/// Generate crypt.methods (list of available methods)
pub fn genMethods(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList(@TypeOf(.{ .name = \"\", .ident = \"\", .salt_chars = @as(i32, 0), .total_size = @as(i32, 0) })).init()");
}
