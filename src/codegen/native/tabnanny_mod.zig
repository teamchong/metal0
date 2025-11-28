/// Python tabnanny module - Detection of ambiguous indentation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate tabnanny.check(file)
pub fn genCheck(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate tabnanny.process_tokens(tokens)
pub fn genProcessTokens(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate tabnanny.NannyNag exception
pub fn genNannyNag(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NannyNag");
}

/// Generate tabnanny.verbose flag
pub fn genVerbose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate tabnanny.filename_only flag
pub fn genFilenameOnly(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}
