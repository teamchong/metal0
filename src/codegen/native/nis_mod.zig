/// Python nis module - NIS (Yellow Pages) interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate nis.match(key, mapname, domain=None) - Match key in NIS map
pub fn genMatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate nis.cat(mapname, domain=None) - Get NIS map contents
pub fn genCat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate nis.maps(domain=None) - List all NIS maps
pub fn genMaps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate nis.get_default_domain() - Get default NIS domain
pub fn genGetDefaultDomain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate nis.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NisError");
}
