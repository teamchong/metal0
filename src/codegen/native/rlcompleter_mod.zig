/// Python rlcompleter module - Readline completion support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate rlcompleter.Completer(namespace=None)
pub fn genCompleter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .namespace = .{}, .use_main_ns = @as(i32, 0) }");
}
