/// Python pyclbr module - Python class browser support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pyclbr.readmodule(module, path=None)
pub fn genReadmodule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const modname = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = modname; break :blk .{}; }");
    } else {
        try self.emit(".{}");
    }
}

/// Generate pyclbr.readmodule_ex(module, path=None)
pub fn genReadmoduleEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const modname = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = modname; break :blk .{}; }");
    } else {
        try self.emit(".{}");
    }
}

/// Generate pyclbr.Class class
pub fn genClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .module = \"\", .name = \"\", .super = &[_]@TypeOf(.{}){}, .methods = .{}, .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{} }");
}

/// Generate pyclbr.Function class
pub fn genFunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .module = \"\", .name = \"\", .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{}, .is_async = false }");
}
