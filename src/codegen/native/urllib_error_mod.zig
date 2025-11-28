/// Python urllib.error module - URL error exceptions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate urllib.error.URLError exception
pub fn genURLError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.URLError");
}

/// Generate urllib.error.HTTPError exception
pub fn genHTTPError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.HTTPError");
}

/// Generate urllib.error.ContentTooShortError exception
pub fn genContentTooShortError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ContentTooShortError");
}
