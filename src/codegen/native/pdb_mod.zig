/// Python pdb module - Python debugger
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pdb.Pdb class
pub fn genPdb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .skip = @as(?[]const []const u8, null), .nosigint = false }");
}

/// Generate pdb.run(statement, globals=None, locals=None)
pub fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pdb.runeval(expression, globals=None, locals=None)
pub fn genRuneval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate pdb.runcall(function, *args, **kwargs)
pub fn genRuncall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate pdb.set_trace(*, header=None)
pub fn genSet_trace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pdb.post_mortem(traceback=None)
pub fn genPost_mortem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pdb.pm() - post-mortem from sys.last_traceback
pub fn genPm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pdb.help()
pub fn genHelp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pdb.Breakpoint class
pub fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .file = \"\", .line = @as(i32, 0), .temporary = false, .cond = @as(?[]const u8, null), .funcname = @as(?[]const u8, null), .enabled = true, .ignore = @as(i32, 0), .hits = @as(i32, 0), .number = @as(i32, 0) }");
}
