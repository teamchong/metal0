/// HTTP module - http.get() and http.post() code generation
/// Uses custom runtime HTTP client (packages/runtime/src/http.zig)
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for http.get(url)
/// Maps to custom runtime: @import("runtime").http.get(allocator, url)
/// NOTE: Zig std.http.Client in 0.15.2 has complex Writer API - use custom impl instead
pub fn genHttpGet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Use runtime.http (already imported in header)
    try self.output.appendSlice(self.allocator, "runtime.http.get(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ").body");
}

/// Generate code for http.post(url, body)
/// Maps to custom runtime: @import("runtime").http.post(allocator, url, body)
pub fn genHttpPost(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        // TODO: Error handling
        return;
    }

    // Use runtime.http (already imported in header)
    try self.output.appendSlice(self.allocator, "runtime.http.post(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ").body");
}
