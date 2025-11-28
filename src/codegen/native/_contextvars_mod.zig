/// Python _contextvars module - Internal contextvars support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _contextvars.ContextVar(name, *, default=None)
pub fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .name = name, .default = null }; }");
    } else {
        try self.emit(".{ .name = \"\", .default = null }");
    }
}

/// Generate _contextvars.Context()
pub fn genContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _contextvars.Token class
pub fn genToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .var = null, .old_value = null, .used = false }");
}

/// Generate _contextvars.copy_context()
pub fn genCopyContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate ContextVar.get(default=None)
pub fn genGet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ContextVar.set(value)
pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .var = null, .old_value = null, .used = false }");
}

/// Generate ContextVar.reset(token)
pub fn genReset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Context.run(callable, *args, **kwargs)
pub fn genRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Context.copy()
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
