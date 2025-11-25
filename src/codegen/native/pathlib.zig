/// Pathlib module - pathlib.Path(), Path.exists(), Path.read_text() code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for pathlib.Path(str)
/// Creates a Path object from a string path
pub fn genPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.pathlib.Path.create(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for Path.exists()
/// Checks if the path exists on the filesystem
pub fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // exists() takes no arguments (called on Path instance)
    if (args.len != 0) {
        return;
    }
    _ = self;
    // Note: This is generated as a method call, handled in methods dispatch
}

/// Generate code for Path.read_text()
/// Reads the file contents as a string
pub fn genReadText(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // read_text() takes no arguments (called on Path instance)
    if (args.len != 0) {
        return;
    }
    _ = self;
    // Note: This is generated as a method call, handled in methods dispatch
}

/// Generate code for Path.is_file()
/// Checks if path is a regular file
pub fn genIsFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 0) {
        return;
    }
    _ = self;
}

/// Generate code for Path.is_dir()
/// Checks if path is a directory
pub fn genIsDir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 0) {
        return;
    }
    _ = self;
}
