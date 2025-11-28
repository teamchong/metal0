/// Python linecache module - Random access to text lines
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate linecache.getline(filename, lineno, module_globals=None) -> str
pub fn genGetline(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate linecache.getlines(filename, module_globals=None) -> list of lines
pub fn genGetlines(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate linecache.clearcache() -> None
pub fn genClearcache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate linecache.checkcache(filename=None) -> None
pub fn genCheckcache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate linecache.updatecache(filename, module_globals=None) -> list
pub fn genUpdatecache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate linecache.lazycache(filename, module_globals) -> bool
pub fn genLazycache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate linecache.cache dict
pub fn genCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap([][]const u8).init(allocator)");
}
