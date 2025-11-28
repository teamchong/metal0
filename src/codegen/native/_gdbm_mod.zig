/// Python _gdbm module - GNU DBM database
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _gdbm.open(filename, flag='r', mode=0o666)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate gdbm.close()
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate gdbm.keys()
pub fn genKeys(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate gdbm.firstkey()
pub fn genFirstkey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate gdbm.nextkey(key)
pub fn genNextkey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate gdbm.reorganize()
pub fn genReorganize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate gdbm.sync()
pub fn genSync(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _gdbm.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.GdbmError");
}
