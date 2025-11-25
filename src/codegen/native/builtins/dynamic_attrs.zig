/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.getattr_builtin(");
    try self.genExpr(args[0]); // object
    try self.emit(", ");
    try self.genExpr(args[1]); // name
    try self.emit(")");
}

pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.setattr_builtin(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", ");
    try self.genExpr(args[2]);
    try self.emit(")");
}

pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.hasattr_builtin(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.vars_builtin(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit(")");
}

pub fn genGlobals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.globals_builtin()");
}

pub fn genLocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.locals_builtin()");
}
