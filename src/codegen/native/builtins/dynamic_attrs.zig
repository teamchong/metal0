/// Dynamic attribute and scope access builtins
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.output.appendSlice(self.allocator, "runtime.getattr_builtin(");
    try self.genExpr(args[0]); // object
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]); // name
    try self.output.appendSlice(self.allocator, ")");
}

pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.output.appendSlice(self.allocator, "runtime.setattr_builtin(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[2]);
    try self.output.appendSlice(self.allocator, ")");
}

pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.output.appendSlice(self.allocator, "runtime.hasattr_builtin(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.output.appendSlice(self.allocator, "runtime.vars_builtin(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.output.appendSlice(self.allocator, ")");
}

pub fn genGlobals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "runtime.globals_builtin()");
}

pub fn genLocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "runtime.locals_builtin()");
}
