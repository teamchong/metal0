/// Python fileinput module - Iterate over lines from multiple input streams
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate fileinput.input(files=None, inplace=False, backup='', *, mode='r', openhook=None, encoding=None, errors=None)
pub fn genInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\" }");
}

/// Generate fileinput.filename()
pub fn genFilename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate fileinput.fileno()
pub fn genFileno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

/// Generate fileinput.lineno()
pub fn genLineno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate fileinput.filelineno()
pub fn genFilelineno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate fileinput.isfirstline()
pub fn genIsfirstline(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate fileinput.isstdin()
pub fn genIsstdin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate fileinput.nextfile()
pub fn genNextfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate fileinput.close()
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate fileinput.FileInput class
pub fn genFileInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\", .encoding = null, .errors = null }");
}

/// Generate fileinput.hook_compressed(filename, mode, *, encoding=None, errors=None)
pub fn genHookCompressed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate fileinput.hook_encoded(encoding, errors=None)
pub fn genHookEncoded(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}
