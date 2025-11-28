/// Python pickletools module - Tools for working with pickle data streams
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pickletools.dis(pickle, annotate=0)
pub fn genDis(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pickletools.genops(pickle)
pub fn genGenops(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate pickletools.optimize(picklestring)
pub fn genOptimize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate pickletools.OpcodeInfo class
pub fn genOpcodeInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .code = \"\", .arg = null, .stack_before = &[_][]const u8{}, .stack_after = &[_][]const u8{}, .proto = 0, .doc = \"\" }");
}

/// Generate pickletools.opcodes constant
pub fn genOpcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate pickletools.bytes_types constant
pub fn genBytesTypes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]type{ []const u8 }");
}

/// Generate pickletools.UP_TO_NEWLINE constant
pub fn genUpToNewline(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

/// Generate pickletools.TAKEN_FROM_ARGUMENT1 constant
pub fn genTakenFromArgument1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -2)");
}

/// Generate pickletools.TAKEN_FROM_ARGUMENT4 constant
pub fn genTakenFromArgument4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -3)");
}

/// Generate pickletools.TAKEN_FROM_ARGUMENT4U constant
pub fn genTakenFromArgument4U(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -4)");
}

/// Generate pickletools.TAKEN_FROM_ARGUMENT8U constant
pub fn genTakenFromArgument8U(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -5)");
}
